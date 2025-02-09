json.set! '@context', 'http://schema.org'
json.set! '@type', 'BlogPosting'
json.set! 'mainEntityOfPage', entry.permalink_url
json.headline entry.plain_title
json.description entry.meta_description
json.set! 'datePublished', entry.published_at
json.set! 'dateModified', entry.modified_at
if entry.is_photo?
  json.image json_schema_images(@photos.first)
end
json.author do
  json.set! '@type', 'Person'
  json.name entry.user.name
  json.url about_url
end
json.publisher do
  json.set! '@type', 'Organization'
  json.name @photoblog.name
  if @photoblog.logo.attached?
    json.logo do
      json.set! '@type', 'ImageObject'
      json.width 145
      json.height 60
      json.url @photoblog.logo_url(w: 145, h: 60, fm: 'png', pad: 6, fit: 'fill', bg: '0fff')
    end
  end
end
