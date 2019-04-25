class TagCustomization < ApplicationRecord
  validate :tag_list_must_be_unique, :fields_cannot_be_blank
  validates :tag_list, presence: true
  belongs_to :blog, touch: true, optional: true
  acts_as_taggable_on :tags

  def instagram_hashtags_to_a
    self.instagram_hashtags.split(/\s+/)
  end

  def flickr_groups_to_a
    self.flickr_groups.split(/\s+/)
  end

  def flickr_groups_slugs
    self.flickr_groups_to_a.map { |g| g.split('/').last }
  end

  def flickr_albums_to_a
    self.flickr_albums.split(/\s+/)
  end

  def matches_tags?(tags)
    self.tags.all? { |t| tags.include? t }
  end

  def location_name
    return nil if self.instagram_location_id.blank?
    self.instagram_location_name.present? ? self.instagram_location_name : self.tag_list.join(', ')
  end

  private

  def tag_list_must_be_unique
    tag_customizations = TagCustomization.where.not(id: self.id).tagged_with(self.tag_list, :match_all => true)
    if tag_customizations.any? { |tc| tc.tag_list.size == self.tag_list.size }
      errors.add(:tag_list, "already exists")
    end
  end

  def fields_cannot_be_blank
    if self.instagram_hashtags.blank? && self.instagram_location_id.blank? && self.flickr_groups.blank? && self.flickr_albums.blank?
      errors.add(:base, 'You need to fill out at least one of the fields')
    end
  end
end
