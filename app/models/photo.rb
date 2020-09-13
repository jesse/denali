class Photo < ApplicationRecord
  belongs_to :entry, touch: true, counter_cache: true, optional: true
  belongs_to :camera, optional: true
  belongs_to :lens, optional: true
  belongs_to :film, optional: true
  has_one_attached :image

  acts_as_list scope: :entry

  after_create_commit :extract_metadata, :extract_palette

  after_commit :touch_entry
  after_commit :geocode, if: :changed_coordinates?
  after_commit :update_entry_equipment_tags, if: :changed_equipment?
  after_commit :update_entry_location_tags, if: :changed_location?
  after_commit :update_entry_style_tags, if: :changed_style?

  def touch_entry
    self.entry&.touch
  end

  def update_entry_equipment_tags
    self.entry.update_equipment_tags
  end

  def update_entry_location_tags
    self.entry.update_location_tags
  end

  def update_entry_style_tags
    self.entry.update_style_tags
  end

  def self.oldest
    order('taken_at ASC').limit(1)&.first
  end

  def url(opts = {})
    opts.reverse_merge!(w: 1200, square: false)
    opts[:h] = opts[:w] if opts[:square]
    if opts[:w].present? && opts[:h].present? && opts[:h] != height_from_width(opts[:w]) && !opts[:fit].present?
      opts.merge!(fit: 'crop')
      opts.merge!(crop: 'focalpoint', 'fp-x': self.focal_x, 'fp-y': self.focal_y) if self.focal_x.present? && self.focal_y.present?
    end
    opts.delete(:square)
    Ix.path(self.image.key).to_url(opts.compact)
  end

  def srcset(srcset:, square: false, opts: { q: 75 })
    imgix_path = Ix.path(self.image.key)
    widths = srcset.reject { |width| width > self.width }
    src_width = widths.first
    if square.presence
      opts.merge!(fit: 'crop')
      opts.merge!(crop: 'focalpoint', 'fp-x': self.focal_x, 'fp-y': self.focal_y) if self.focal_x.present? && self.focal_y.present?
      src = imgix_path.to_url(opts.merge(w: src_width, h: src_width))
      srcset = widths.map { |w| "#{imgix_path.to_url(opts.merge(w: w, h: w))} #{w}w" }.join(', ')
    else
      src = imgix_path.to_url(opts.merge(w: src_width))
      srcset = widths.map { |w| "#{imgix_path.to_url(opts.merge(w: w))} #{w}w" }.join(', ')
    end
    return src, srcset
  end

  # Returns the url of the image, formatted & sized fit to into instagram's
  # 5:4 ratio
  def instagram_url
    opts = { w: 1080, fit: 'fill', bg: 'fff', pad: 50, q: 90, fm: 'jpg' }
    opts[:h] = self.is_vertical? ? 1350 : 1080
    self.url(opts)
  end

  # Returns the url of the image, formatted & sized fit to into instagram stories'
  # 16:9 ratio
  def instagram_story_url
    self.url(w: 2160, h: 3840, fit: 'fill', fill: 'blur', q: 90, fm: 'jpg')
  end

  def facebook_card_url
    self.url(w: 1200, h: 630)
  end

  def twitter_card_url
    self.url(w: 1200, h: 600)
  end

  def twitter_banner_url
    self.url(w: 1500, h: 500)
  end

  def palette_url(opts = {})
    opts.reverse_merge!(palette: 'json', colors: 6)
    Ix.path(self.image.key).to_url(opts)
  end

  def purge
    url = Ix.path(self.image.key).to_url
    uri = URI.parse(url)
    Ix.purge(uri.path)
  end

  def uploaded?
    image&.analyzed?
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
    exp = self.exposure.to_r.rationalize
    formatted = exp >= 1 ? "%g" % ("%.2f" % exp) : exp.to_s
    unit = if exp < 1
      "#{exp.denominator.ordinal} of a second"
    elsif exp == 1
      " second"
    else
      " seconds"
    end
    "#{formatted}#{unit}"
  end

  def location
    [self.neighborhood, self.sublocality, self.locality, self.administrative_area, self.postal_code, self.country].reject(&:blank?).uniq.join(', ')
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

  def color?
    return if self.color_palette.blank?
    !self.color_palette.split(',').map { |c| c.gsub('#', '') }.reject { |c| c.scan(/../).uniq.size == 1 }.empty?
  end

  def black_and_white?
    return if self.color_palette.blank?
    !self.color?
  end

  def changed_dimensions?
    saved_change_to_width? || saved_change_to_height?
  end

  def changed_coordinates?
    saved_change_to_latitude? || saved_change_to_longitude?
  end

  def changed_equipment?
    saved_change_to_camera_id? || saved_change_to_film_id? || saved_change_to_lens_id?
  end

  def changed_location?
    saved_change_to_country? || saved_change_to_locality? || saved_change_to_sublocality?
  end

  def changed_style?
    saved_change_to_color_palette? || saved_change_to_camera_id? || saved_change_to_film_id?
  end
end
