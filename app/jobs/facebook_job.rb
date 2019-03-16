class FacebookJob < BufferJob
  queue_as :default

  def perform(entry)
    return if !entry.is_published? || !entry.is_photo?
    text = []
    text << entry.plain_title
    text << entry.plain_body if entry.body.present?
    text << entry.permalink_url
    text = text.join("\n\n")
    if entry.is_photo?
      media = media_hash(entry.photos.first, w: 2048)
      post_to_buffer('facebook', text: text, media: media)
    else
      post_to_buffer('facebook', text: text)
    end
  end
end
