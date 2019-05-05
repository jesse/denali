class Photo < ApplicationRecord
  belongs_to :entry, touch: true, counter_cache: true, optional: true
  belongs_to :camera, optional: true
  belongs_to :lens, optional: true
  belongs_to :film, optional: true
  has_one_attached :image

  acts_as_list scope: :entry

  after_create :extract_metadata, :extract_palette

  after_save :touch_entry, if: :changed_visible_attributes?
  after_save :geocode, if: :changed_coordinates?
  after_save :update_entry_tags, if: :changed_taggable_attributes?
  after_save :validate_amp, if: :changed_dimensions?

  def touch_entry
    self.entry.touch
  end

  def update_entry_tags
    self.entry.update_tags
  end

  def self.oldest
    order('taken_at ASC').limit(1)&.first
  end

  def self.sizes(key)
    PHOTOS[key]['sizes'].join(', ')
  end

  def url(opts = {})
    opts.reverse_merge!(w: 1200, square: false)
    if opts[:square]
      opts[:h] = opts[:w]
      opts.delete(:square)
    end
    if opts[:w].present? && opts[:h].present? && opts[:h] != height_from_width(opts[:w]) && !opts[:fit].present?
      opts[:fit] = 'crop'
      opts.merge!(crop: 'focalpoint', 'fp-x': self.focal_x, 'fp-y': self.focal_y) if self.focal_x.present? && self.focal_y.present?
    end
    Ix.path(self.image.key).to_url(opts.reject { |k,v| v.blank? })
  end

  def srcset(key, opts = {})
    s3_key = self.image.key
    max_width = self.width
    variant = PHOTOS[key]
    square = variant['square'].present?
    widths = variant['srcset'].uniq.sort.reject { |width| max_width.present? && width > max_width }
    opts.merge!(auto: variant['auto']) if variant['auto'].present?
    opts.merge!(q: variant['quality']) if variant['quality'].present?
    src_width = widths.first
    if square
      opts[:fit] = 'crop'
      opts.merge!(crop: 'focalpoint', 'fp-x': self.focal_x, 'fp-y': self.focal_y) if self.focal_x.present? && self.focal_y.present?
      src = Ix.path(s3_key).to_url(opts.merge(w: src_width, h: src_width))
      srcset = widths.map { |w| "#{Ix.path(s3_key).to_url(opts.merge(w: w, h: w))} #{w}w" }.join(', ')
    else
      src = Ix.path(s3_key).to_url(opts.merge(w: src_width))
      srcset = widths.map { |w| "#{Ix.path(s3_key).to_url(opts.merge(w: w))} #{w}w" }.join(', ')
    end
    return src, srcset
  end

  # Returns the url of the image, formatted & sized fit to into instagram's
  # 5:4 ratio
  def instagram_url
    if self.is_vertical? && self.height_from_width(1080) > 1350
      self.url(w: 1080, h: 1350, fit: 'fill', bg: 'fff', q: 90)
    elsif self.is_horizontal? && self.height_from_width(1080) < 566
      self.url(w: 1080, h: 566, fit: 'fill', bg: 'fff', q: 90)
    else
      self.url(w: 1080, q: 90)
    end
  end

  # Returns the url of the image, formatted & sized fit to into instagram stories'
  # 16:9 ratio
  def instagram_story_url
    self.url(w: 2160, h: 3840, fit: 'fill', bg: '000', q: 90, pad: 100)
  end

  def palette_url(opts = {})
    opts.reverse_merge!(palette: 'json', colors: 6)
    Ix.path(self.image.key).to_url(opts)
  end

  def is_square?
    self.width == self.height
  end

  def is_horizontal?
    self.width > self.height
  end

  def is_vertical?
    self.width < self.height
  end

  def has_location?
    self.longitude.present? && self.latitude.present?
  end

  def height_from_width(width)
    return nil if self.width.blank?
    ((self.height.to_f * width.to_f)/self.width.to_f).round
  end

  def width_from_height(height)
    return nil if self.height.blank?
    ((self.width.to_f * height.to_f)/self.height.to_f).round
  end

  def focal_length_with_unit
    return '' if self.focal_length.blank?
    "#{self.focal_length} mm"
  end

  def formatted_aperture
    return '' if self.f_number.blank?
    f = "%g" % ("%.2f" % self.f_number)
    "f/#{f}"
  end

  def formatted_exposure
    return '' if self.exposure.blank?
    exp = self.exposure.to_r
    formatted = exp >= 1 ? "%g" % ("%.2f" % exp) : exp
    "#{formatted}″"
  end

  def long_address
    [self.neighborhood, self.sublocality, self.locality, self.administrative_area, self.postal_code, self.country].uniq.reject(&:blank?).join(', ')
  end

  def short_address
    [self.locality, self.administrative_area, self.country].uniq.reject(&:blank?).reject { |a| a.match? /^united (states|kingdom)/i }.join(', ')
  end

  def extract_metadata
    PhotoMetadataWorker.perform_async(self.id)
  end

  def geocode
    PhotoGeocodeWorker.perform_async(self.id)
  end

  def extract_palette
    PhotoPaletteWorker.perform_async(self.id)
  end

  def prominent_color
    self.color_vibrant || self.color_muted || '#EEEEEE'
  end

  def color?
    return if self.color_palette.blank?
    !self.color_palette.split(',').map { |c| c.gsub('#', '') }.reject { |c| c.scan(/../).uniq.size == 1 }.empty?
  end

  def black_and_white?
    return if self.color_palette.blank?
    !self.color?
  end

  def validate_amp
    AmpValidationWorker.perform_async(self.entry.id)
  end

  private

  def changed_dimensions?
    saved_change_to_width? || saved_change_to_height?
  end

  def changed_visible_attributes?
    saved_change_to_alt_text? || saved_change_to_focal_x? || saved_change_to_focal_y?
  end

  def changed_coordinates?
    saved_change_to_latitude? || saved_change_to_longitude?
  end

  def changed_taggable_attributes?
    saved_change_to_country? || saved_change_to_color_palette? || saved_change_to_camera_id? || saved_change_to_lens_id?
  end
end
