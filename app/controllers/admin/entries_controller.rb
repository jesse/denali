class Admin::EntriesController < AdminController
  include TagList

  before_action :set_entry, only: [:show, :edit, :update, :destroy, :publish, :queue, :draft, :crops, :prints, :instagram, :facebook, :twitter, :twitter_banner, :flickr, :flush_caches, :refresh_metadata]
  before_action :get_tags, only: [:new, :edit, :create, :update]
  before_action :load_tags, only: [:tagged]
  before_action :set_redirect_url, if: -> { request.get? }, except: [:photo]
  skip_before_action :require_login, only: [:latest_hashtags]

  # GET /admin/entries
  def index
    set_srcset
    @page = params[:page] || 1
    @entries = @photoblog.entries.includes(photos: [:image_attachment, :image_blob], taggings: :tag).published.page(@page)
    @page_title = 'Published'
    respond_to do |format|
      format.html
    end
  end

  # GET /admin/entries/queued
  def queued
    set_srcset
    @page = params[:page] || 1
    @count = ([@photoblog.publish_schedules_count.presence || 0, 1].max) * 7
    @entries = @photoblog.entries.includes(photos: [:image_attachment, :image_blob], taggings: :tag).queued.page(@page).per(@count)
    @page_title = 'Queued'
    respond_to do |format|
      format.html
    end
  end

  # GET /admin/entries/drafts
  def drafts
    set_srcset
    @page = params[:page] || 1
    @entries = @photoblog.entries.includes(photos: [:image_attachment, :image_blob], taggings: :tag).drafted.page(@page)
    @page_title = 'Drafts'
    respond_to do |format|
      format.html
    end
  end

  # GET /admin/entries/tagged/film
  def tagged
    set_srcset
    @page = params[:page] || 1
    entries = @photoblog.entries.includes(photos: [:image_attachment, :image_blob], taggings: :tag).tagged_with(@tag_list, any: true).order('entries.created_at DESC')
    @entries = entries.page(@page)
    @page_title = "Entries tagged \"#{@tag_list.first}\""
    @tagged_count = entries.size
    raise ActiveRecord::RecordNotFound if @tags.empty? || @entries.empty?
    respond_to do |format|
      format.html
    end
  end

  # GET /admin/entries/:id
  def show
    set_srcset
    @page_title = @entry.plain_title
    respond_to do |format|
      format.html
    end
  end

  # GET /admin/entries/new
  def new
    @entry = @photoblog.entries.new
    @entry.status = 'queued'
    @entry.photos.build
    @page_title = 'New entry'

    previous_entry = @photoblog.entries.order('created_at DESC').first
    if previous_entry.present? && previous_entry.created_at >= 5.minutes.ago
      @entry.title = previous_entry.title
      @entry.slug = previous_entry.slug
      @entry.tag_list = previous_entry.tag_list
    end
  end

  def search
    raise ActionController::RoutingError.new('Not Found') unless @photoblog.has_search?
    set_srcset
    @page = (params[:page] || 1).to_i
    @count = 10
    @query = params[:q]
    @page_title = "Search"
    if @query.present?
      @page_title = "Search results for \"#{@query}\""
      results = Entry.full_search(@query, @page, @count)
      @total_count = results.results.total
      @entries = Kaminari.paginate_array(results.records.includes(photos: [:image_attachment, :image_blob], taggings: :tag), total_count: @total_count).page(@page).per(@count)
    end
    respond_to do |format|
      format.html
    end
  end

  # GET /admin/entries/1/edit
  def edit
    @page_title = "Editing “#{@entry.title}”"
    @srcset = PHOTOS[:admin_edit][:srcset]
    @sizes = PHOTOS[:admin_edit][:sizes].join(', ')
  end

  # PATCH /admin/entries/1/publish
  def publish
    if @entry.publish
      flash[:success] = 'Your entry was published!'
    else
      flash[:warning] = 'Your entry couldn’t be published…'
    end
    redirect_to admin_entries_path
  end

  # PATCH /admin/entries/1/queue
  def queue
    if @entry.queue
      flash[:success] = 'Your entry was sent to the queue.'
    else
      flash[:warning] = 'Your entry couldn’t be queued…'
    end
    redirect_to queued_admin_entries_path
  end

  # PATCH /admin/entries/1/draft
  def draft
    if @entry.draft
      flash[:success] = 'Your entry was moved to the drafts.'
    else
      flash[:warning] = 'Your entry couldn’t be moved to the drafts…'
    end
    redirect_to drafts_admin_entries_path
  end

  # POST /admin/entries
  def create
    @entry = Entry.new(entry_params)
    @entry.user = current_user
    @entry.blog = @photoblog
    respond_to do |format|
      if @entry.save
        @entry.update_tags
        flash[:success] = "Your new entry was saved! <a href=\"#{admin_entry_path(@entry)}\">Check it out.</a>"
        format.html { redirect_to new_admin_entry_path }
      else
        flash[:warning] = 'Your entry couldn’t be saved…'
        format.html { render :new }
      end
    end
  end

  # PATCH/PUT /admin/entries/1
  def update
    respond_to do |format|
      @entry.modified_at = Time.current if @entry.is_published?
      if @entry.update(entry_params)
        @entry.update_tags
        @entry.invalidate
        OpenGraphWorker.perform_in(1.minute, @entry.id) if @entry.is_published?
        flash[:success] = 'Your entry has been updated!'
        format.html { redirect_to session[:redirect_url] || admin_entry_path(@entry) }
      else
        flash[:warning] = 'Your entry couldn’t be updated…'
        format.html { render :edit }
      end
    end
  end

  # DELETE /admin/entries/1
  def destroy
    @entry.invalidate(include_adjacents: true)
    @entry.destroy
    respond_to do |format|
      flash[:danger] = 'Your entry was deleted forever.'
      format.html { redirect_to session[:redirect_url] || admin_entries_path }
    end
  end

  def organize_queue
    @srcset = PHOTOS[:admin_queue][:srcset]
    @sizes = PHOTOS[:admin_queue][:sizes].join(', ')
    @entries = @photoblog.entries.includes(photos: [:image_attachment, :image_blob]).queued
    @page_title = 'Organize queue'
    respond_to do |format|
      format.html
    end
  end

  def update_queue
    entry_ids = params[:entry_ids].map(&:to_i)
    entries = Entry.where(id: entry_ids)
    position = 1
    entry_ids.each do |id|
      entry = entries.find { |e| e.id == id }
      if entry.is_queued?
        entry.position = position
        entry.save
        position += 1
      end
    end
    respond_to do |format|
      format.json {
        response = {
          status: 'success',
          message: 'The changes you’ve made to the queue have been saved!'
        }
        render json: response
      }
    end
  end

  def photo
    @entry = Entry.new
    @count = params[:count] || 1
    @entry.photos.build
    request.format = 'html'
    respond_to do |format|
      format.html { render layout: nil }
    end
  end

  def syndicate
    @entry = @photoblog.entries.published.find(params[:id])
    respond_to do |format|
      format.html {
        if params[:modal]
          render layout: nil
        else
          render
        end
      }
    end
  end

  def crops
    @srcset = PHOTOS[:admin_modal][:srcset]
    @sizes = PHOTOS[:admin_modal][:sizes].join(', ')
    respond_to do |format|
      format.html {
        if params[:modal]
          render layout: nil
        else
          render
        end
      }
    end
  end

  def prints
    @srcset = PHOTOS[:admin_modal][:srcset]
    @sizes = PHOTOS[:admin_modal][:sizes].join(', ')
    @color_print_sizes = YAML.load_file(Rails.root.join('config/prints.yml'))['color']
    @bw_print_sizes = YAML.load_file(Rails.root.join('config/prints.yml'))['blackandwhite']
    respond_to do |format|
      format.html {
        if params[:modal]
          render layout: nil
        else
          render
        end
      }
    end
  end

  def instagram
    raise ActiveRecord::RecordNotFound unless @entry.is_photo?
    InstagramWorker.perform_async(@entry.id, false)
    @message = 'Your entry was sent to your Instagram queue in Buffer.'
    respond_to do |format|
      format.html {
        flash[:success] = @message
        redirect_to session[:redirect_url] || admin_entry_path(@entry)
      }
      format.js { render 'admin/shared/notify' }
    end
  end

  def twitter
    raise ActiveRecord::RecordNotFound unless @entry.is_published? && @entry.is_photo?
    TwitterWorker.perform_async(@entry.id)
    @message = 'Your entry was sent to Twitter.'
    respond_to do |format|
      format.html {
        flash[:success] = @message
        redirect_to session[:redirect_url] || admin_entry_path(@entry)
      }
      format.js { render 'admin/shared/notify' }
    end
  end

  def twitter_banner
    raise ActiveRecord::RecordNotFound unless @entry.is_published? && @entry.is_photo?
    TwitterBannerWorker.perform_async(@entry.id)
    @message = 'Your entry was sent to your Twitter banner.'
    respond_to do |format|
      format.html {
        flash[:success] = @message
        redirect_to session[:redirect_url] || admin_entry_path(@entry)
      }
      format.js { render 'admin/shared/notify' }
    end
  end

  def facebook
    raise ActiveRecord::RecordNotFound unless @entry.is_published? && @entry.is_photo?
    FacebookWorker.perform_async(@entry.id, false)
    @message = 'Your entry was sent to your Facebook queue in Buffer.'
    respond_to do |format|
      format.html {
        flash[:success] = @message
        redirect_to session[:redirect_url] || admin_entry_path(@entry)
      }
      format.js { render 'admin/shared/notify' }
    end
  end

  def flickr
    raise ActiveRecord::RecordNotFound unless @entry.is_published? && @entry.is_photo?
    @entry.photos.each do |p|
      FlickrWorker.perform_async(p.id)
    end
    @message = 'Your entry was sent to Flickr.'
    respond_to do |format|
      format.html {
        flash[:success] = @message
        redirect_to session[:redirect_url] || admin_entry_path(@entry)
      }
      format.js { render 'admin/shared/notify' }
    end
  end

  def flush_caches
    @entry.invalidate
    OpenGraphWorker.perform_in(1.minute, @entry.id) if @entry.is_published?
    @message = 'Your entry is being cleared from cache. This may take a few moments.'
    respond_to do |format|
      format.html {
        flash[:success] = @message
        redirect_to session[:redirect_url] || admin_entry_path(@entry)
      }
      format.js { render 'admin/shared/notify' }
    end
  end

  def refresh_metadata
    @entry.update_tags
    @entry.photos.each do |photo|
      photo.extract_metadata
      photo.annotate
      photo.encode_blurhash
    end
    @message = 'Your entry’s metadata is being updated. This may take a few moments.'
    respond_to do |format|
      format.html {
        flash[:success] = @message
        redirect_to session[:redirect_url] || admin_entry_path(@entry)
      }
      format.js { render 'admin/shared/notify' }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_entry
      @entry = @photoblog.entries.find(params[:id])
    end

    def get_tags
      @tags = ActsAsTaggableOn::Tag.order('taggings_count desc')
    end

    def entry_params
      params.require(:entry).permit(:title, :body, :slug, :status, :tag_list, :post_to_twitter, :post_to_flickr, :post_to_flickr_groups, :post_to_instagram, :post_to_facebook, :tweet_text, :instagram_text, :show_in_map, photos_attributes: [:image, :id, :_destroy, :position, :alt_text, :focal_x, :focal_y])
    end

    def set_redirect_url
      session[:redirect_url] = request.referer
    end

    def set_srcset
      @srcset = PHOTOS[:admin_entry][:srcset]
      @sizes = PHOTOS[:admin_entry][:sizes].join(', ')
    end
end
