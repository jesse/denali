class EntriesController < ApplicationController
  include TagList

  skip_before_action :verify_authenticity_token
  skip_before_action :set_link_headers, only: [:amp]
  before_action :set_request_format, only: [:index, :tagged, :show]
  before_action :load_tags, only: [:tagged, :tag_feed]
  before_action :set_max_age, only: [:index, :tagged, :feed, :tag_feed, :search]
  before_action :set_entry_max_age, only: [:show, :preview, :photo, :amp]
  before_action :set_sitemap_entry_count, only: [:sitemap_index, :sitemap]

  layout 'amp', only: :amp

  def index
    if stale?(@photoblog, public: true)
      @page = (params[:page] || 1).to_i
      @count = @photoblog.posts_per_page
      @entries = @photoblog.entries.includes(:photos).published.photo_entries.page(@page).per(@count)
      raise ActiveRecord::RecordNotFound if @entries.empty? && request.format != 'js'
      respond_to do |format|
        format.html
        format.json
        format.js { render status: @entries.empty? ? 404 : 200 }
        format.atom {
          if @page == 1
            redirect_to feed_url(page: nil, format: 'atom'), status: 301
          else
            redirect_to feed_url(page: @page, format: 'atom'), status: 301
          end
        }
        format.all {
          if @page == 1
            redirect_to entries_url, status: 301
          else
            redirect_to entries_url(page: @page), status: 301
          end
        }
      end
    end
  end

  def tagged
    if stale?(@photoblog, public: true)
      @page = (params[:page] || 1).to_i
      @count = @photoblog.posts_per_page
      @entries = @photoblog.entries.includes(:photos).published.photo_entries.tagged_with(@tag_list, any: true).page(@page).per(@count)
      raise ActiveRecord::RecordNotFound if (@tags.empty? || @entries.empty?) && request.format != 'js'
      respond_to do |format|
        format.html
        format.json
        format.js { render status: @entries.empty? ? 404 : 200 }
        format.atom {
          if @page == 1
            redirect_to tag_feed_url(tag: @tag_slug, page: nil, format: 'atom'), status: 301
          else
            redirect_to tag_feed_url(tag: @tag_slug, page: @page, format: 'atom'), status: 301
          end
        }
        format.all {
          if @page == 1
            redirect_to tag_url(@tag_slug), status: 301
          else
            redirect_to tag_url(tag: @tag_slug, page: @page), status: 301
          end
        }
      end
    end
  end

  def search
    raise ActionController::RoutingError unless @photoblog.has_search?
    @page = (params[:page] || 1).to_i
    @count = @photoblog.posts_per_page
    @query = params[:q]
    if @query.present?
      results = Entry.published_search(@query, @page, @count)
      total_count = results.results.total
      records = results.records.includes(:photos)
      @entries = Kaminari.paginate_array(records, total_count: total_count).page(@page).per(@count)
    end
    respond_to do |format|
      format.html
      format.all { redirect_to search_path, status: 301 }
    end
  end

  def show
    if stale?(@photoblog, public: true)
      @entry = @photoblog.entries.includes(:photos, :user, :blog).published.find(params[:id])
      respond_to do |format|
        format.html {
          redirect_to(@entry.permalink_url, status: 301) unless params_match(@entry, params)
        }
        format.json
        format.all { redirect_to(@entry.permalink_url, status: 301) }
      end
    end
  end

  def amp
    if stale?(@photoblog, public: true)
      @entry = @photoblog.entries.includes(:photos, :user, :blog).published.find(params[:id])
      respond_to do |format|
        format.html {
          redirect_to(@entry.amp_url, status: 301) unless params_match(@entry, params)
        }
      end
    end
  end

  def photo
    if stale?(@photoblog, public: true)
      entry = @photoblog.entries.joins(:photos).published.where('photos.id = ?', params[:id]).first
      raise ActiveRecord::RecordNotFound if entry.nil?
      redirect_to(entry.permalink_url, status: 301)
    end
  end

  def feed
    if stale?(@photoblog, public: true)
      @page = (params[:page] || 1).to_i
      @count = @photoblog.posts_per_page
      @entries = @photoblog.entries.includes(:photos, :user).published.photo_entries.page(@page).per(@count)
      raise ActiveRecord::RecordNotFound if @entries.empty?
      respond_to do |format|
        format.atom
        format.json
        format.all { redirect_to feed_url(format: 'atom', page: nil, tag: params[:tag]) }
      end
    end
  end

  def tag_feed
    if stale?(@photoblog, public: true)
      @page = (params[:page] || 1).to_i
      @count = @photoblog.posts_per_page
      @entries = @photoblog.entries.includes(:photos, :user).published.photo_entries.tagged_with(@tag_list, any: true).page(@page).per(@count)
      raise ActiveRecord::RecordNotFound if @tags.empty? || @entries.empty?
      respond_to do |format|
        format.atom
        format.json
        format.all { redirect_to tag_feed_url(format: 'atom', page: nil) }
      end
    end
  end

  def preview
    request.format = 'html'
    if stale?(@photoblog, public: true)
      @entry = @photoblog.entries.includes(:photos, :user, :blog).where(preview_hash: params[:preview_hash]).limit(1).first
      raise ActiveRecord::RecordNotFound if @entry.nil?
      respond_to do |format|
        format.html {
          if @entry.is_published?
            redirect_to @entry.permalink_url
          else
            render 'entries/show'
          end
        }
      end
    end
  end

  def tumblr
    expires_in 1.year, public: true
    @entry = @photoblog.entries.published.where(tumblr_id: params[:tumblr_id]).order('published_at ASC').first
    respond_to do |format|
      format.html {
        redirect_to @entry.present? ? @entry.permalink_url : root_url, status: 301
      }
    end
  end

  def sitemap_index
    expires_in 24.hours, public: true
    if stale?(@photoblog, public: true)
      @pages = @photoblog.entries.published.page(1).per(@entries_per_sitemap).total_pages
      render format: 'xml'
    end
  end

  def sitemap
    expires_in 24.hours, public: true
    if stale?(@photoblog, public: true)
      @page = params[:page]
      @entries = @photoblog.entries.includes(:photos).published.page(@page).per(@entries_per_sitemap)
      render format: 'xml'
    end
  end

  private
  def params_match(entry, params)
    entry_date = entry.published_at
    year = entry_date.strftime('%Y')
    month = entry_date.strftime('%-m')
    day = entry_date.strftime('%-d')
    slug = entry.slug

    year == params[:year] &&
    month == params[:month] &&
    day == params[:day] &&
    slug == params[:slug]
  end

  def set_request_format
    request.format = 'json' if request.headers['Content-Type']&.downcase == 'application/vnd.api+json'
  end

  def set_sitemap_entry_count
    @entries_per_sitemap = 100
  end
end
