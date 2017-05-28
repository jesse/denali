class BlogsController < ApplicationController
  before_action :set_entry_max_age, except: [:offline, :manifest]
  skip_before_action :verify_authenticity_token

  def about
    fresh_when @photoblog, public: true
  end

  def offline
    expires_in 24.hours, public: true
  end

  def manifest
    expires_in 24.hours, public: true
    @icons = @photoblog.touch_icon.present? ? [128, 152, 144, 192].map { |size| { sizes: "#{size}x#{size}", type: 'image/png', src: @photoblog.touch_icon_url(w: size) } } : []
  end
end
