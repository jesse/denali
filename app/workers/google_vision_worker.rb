class GoogleVisionWorker < ApplicationWorker

  def perform(photo_id)
    return if ENV['google_api_key'].blank?

    photo = Photo.find(photo_id)
    raise UnprocessedPhotoError unless photo.processed?

    response = request_annotations(photo)
    colors = response['responses'].find { |r| r['imagePropertiesAnnotation'].present? }.dig('imagePropertiesAnnotation', 'dominantColors', 'colors')

    photo.dominant_color = dominant_color(colors)
    photo.black_and_white = is_black_and_white?(colors)
    photo.color = !is_black_and_white?(colors)
    photo.save
  end

  private
  def request_annotations(photo)
    payload = {
      requests: [
        {
          image: {
            source: {
              'imageUri': photo.url(width: 1024, fm: 'jpg')
            }
          },
          features: [
            {
              type: 'IMAGE_PROPERTIES'
            }
          ]
        }
      ]
    }
    response = HTTParty.post("https://vision.googleapis.com/v1/images:annotate?key=#{ENV['google_api_key']}", body: payload.to_json, headers: { 'Content-Type': 'application/json' }, timeout: 120)
    raise GoogleVisionError.new(response.code) if response.code >= 400

    json = JSON.parse(response.body)
    raise GoogleVisionError.new(json['responses'].select { |r| r['error'].present? }.map { |r| r.dig('error', 'message') }.join("\n")) if json['responses'].any? { |r| r['error'].present? }
    raise GoogleVisionError.new('No colors present') if json['responses'].none? { |r| r.dig('imagePropertiesAnnotation', 'dominantColors', 'colors').present? }
    json
  end

  def dominant_color(colors)
    return if colors.blank?
    color = colors.sort { |a, b| b['score'] <=> a['score'] }.first['color']
    to_hex(color)
  end

  def to_hex(color)
    return if color['red'].blank? || color['green'].blank? || color['blue'].blank?
    red = color['red'].to_s(16).rjust(2, '0')
    green = color['green'].to_s(16).rjust(2, '0')
    blue = color['blue'].to_s(16).rjust(2, '0')
    "##{red}#{green}#{blue}".upcase
  end

  def is_black_and_white?(colors)
    colors.all? { |c| c['color']['red'] == c['color']['green'] && c['color']['red'] == c['color']['blue'] && c['color']['green'] == c['color']['blue'] }
  end
end
