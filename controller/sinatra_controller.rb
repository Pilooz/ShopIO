# coding: utf-8
require 'sinatra/reloader' if ENV['RACK_ENV'] == 'development'
require 'socket'
require 'data_uri'

# Application Sinatra servant de base
class SinatraApp < Sinatra::Base
  configure do
    set :app_file, __FILE__
    set :port, APP_PORT
    set :root, APP_ROOT
    set :public_folder, proc { File.join(root, 'public') }
    set :inline_templates, true
    set :protection, true
    set :lock, true
    set :bind, '0.0.0.0' # allowing acces to the lan
  end

  configure :development do
    register Sinatra::Reloader
    also_reload "#{APP_ROOT}/lib/db.rb"
    # dont_reload '/path/to/other/file'
  end

  helpers do
    # Text Translation function
    def _t(s)
      if TRANSLATE[s].nil?
        s = "@@-- #{s} --@@"
        return s
      end
      s = TRANSLATE[s][APP_LANG] unless TRANSLATE[s].nil?
      s
    end

    # Help Translation function
    def _h(s)
      if HELP[s].nil?
        s = "@@-- #{s} --@@"
        return s
      end
      s = HELP[s][APP_LANG] unless HELP[s].nil?
      s
    end
  end

  before do
    @nav_list = ''
    @nav_out = ''
    @nav_new = ''
    @nav_barcode = ''
    @nav_populate = ''
    @nav_tags = ''
    @nav_checkin = ''
    @code = params['code']
    @item = DB.read @code
    @publiclist = false
  end

  get APP_PATH + '/?' do
    unless @code.nil? || @code.empty?
      # See where we have to go now... don't exists => In, else Out
      if !DB.exists? @code
        # Item doesn't exist in inventory, add it.
        redirect to APP_PATH + "/new?code=#{@code}"
      else
        # Item exist, if it wasn't out, then checkout
        if !DB.checkout? @code
          redirect to APP_PATH + "/out?code=#{@code}"
        else
          # If it is allready out, propose a confirm view to checkin
          redirect to APP_PATH + "/checkin?code=#{@code}"
        end
      end
    end
    @ip = ""
    s = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }
    unless s.nil?
      @ip = s.ip_address.to_s 
    end
    # @server_url = "http://" + ip + ":" + APP_PORT.to_s + APP_PATH + "/"
    erb :index
  end

  # Route for admin list of the TechShop
  get APP_PATH + '/list' do
    # Propose list of TechShop on index page
    @items = DB.select_all_items
    @nav_list = 'active'
    @main_title = _t 'List'
    @placeholder =  _t 'type or scan reference'
    erb :list
  end

  # Route for the public version (without admin features) of techShop list
  get APP_PATH + '/catalog' do
    # Propose list of TechShop on index page
    @items = DB.select_all_items
    @nav_publiclist = 'active'
    @main_title = _t 'List'
    @placeholder =  _t 'type or scan reference'
    @publiclist = true
    erb :list
  end

  get APP_PATH + '/out' do
    @main_title = _t 'Check-out stuff from Techshop'
    @nav_out = 'active'
    # Getting all affected tags for this item
    @assigned_tags = DB.select_tags_for_item @code
    # Getting all accessibles tags
    @available_tags = DB.select_available_tags_for_item @code # DB.select_all_tags
    erb :out 
  end

  get APP_PATH + '/new' do
    @main_title = _t 'Adding stuff in TechShop'
    @nav_new = 'active'
    @action = 'new'
    erb :new_modify
  end

  get APP_PATH + '/modify' do
    @main_title = _t 'Modifying stuff in TechShop'
    @nav_new = 'active'
    @action = 'modify'
    # Getting all affected tags for this item
    @assigned_tags = DB.select_tags_for_item @code
    erb :new_modify
  end

  get APP_PATH + '/checkin' do
    @main_title = _t 'Check-in stuff in TechShop'
    @nav_checkin = 'active'
    # Getting all affected tags for this item
    @assigned_tags = DB.select_tags_for_item @code
    erb :checkin
  end

  get APP_PATH + '/delete' do
    DB.delete_item params['code']
    redirect to APP_PATH + "/list"
  end

  get APP_PATH + '/barcode?' do
    @main_title = _t 'Generate barecodes'
    @nav_barcode = 'active'
    # Reading last id from db
    lastid = 0
    lastid = DB.lastid 'items', 'code'
    if lastid =~ /[A-z]/ 
      # Extracting numerical part and alphabetical part
      @radical = lastid.tr('0-9', '')
      lastid = lastid.tr('A-z', '')
    end 
    @from = lastid.to_i + 1
    @to = @from + 100
    erb :barcode
  end

  get APP_PATH + '/tags' do
    @tags = DB.select_all_tags
    @main_title = _t 'Dealing with tags stuff'
    @nav_tags = 'active'
    erb :tags
  end

  get APP_PATH + '/populate' do
    @main_title = _t 'Populate TechShop massively'
    @nav_populate = 'active'
    erb :populate
  end

  # Receive csv data
  post APP_PATH + '/populate' do
    # TODO : See how to get barcode, if code are in csv file, perhaps will we have to produce these codes ?
    DB.add_serveral_items  JSON.parse params['jsondata'] unless params['jsondata'].nil?
    # Redirect to the Techshop's list
    redirect to APP_PATH + "/list"
  end

   # Create or modify item
  post APP_PATH + '/item/new_modify' do
    if params['code']
      begin
        if params['action'] == 'new'
          # TODO : Deals with Image Upload !!
          DB.add_item params['code'], params['name'], params['description'], params['image_link']
        else
          DB.update_item params['code'], params['name'], params['description'], params['image_link']
        end
      rescue Exception => e
        puts "#{e.message}"
        e.backtrace[0..10].each { |t| puts "#{t}"}
        {'result' => 'Error', "message" => e.message }.to_json
      end

    end
     redirect to APP_PATH + "/list"
  end

   # Checkout item
  post APP_PATH + '/item/checkout' do
    if params['code']
      DB.checkout params['code']
    end
    redirect to APP_PATH + "/list"
  end

  # Checkin item
  get APP_PATH + '/item/checkin' do
    if params['code']
      DB.unlink_item params['code']
      DB.checkin params['code']
    end
    redirect to APP_PATH + "/list"
  end

  #
  # CRUD and Ajax Room service !
  #

  # Posting thumbnail in Base64 mode.
  post APP_PATH + '/item/picture' do  
    if params['code'] && params['label'] && params['labelthumb'] && params['thumb'] && params['picture']
      begin
        uri = URI::Data.new params['thumb']
        # Writing thumbnail
        File.open("#{APP_ROOT}/public/pictures/#{params['labelthumb']}", 'wb') do |f|
          f.write uri.data 
        end
        # Writing picture
        File.open("#{APP_ROOT}/public/pictures/#{params['label']}", 'wb') do |f|
          f.write (params['picture'][:tempfile].read)
        end
        # Updating db.
        DB.update_item_image_link @code, params['label']
        {'result' => 'Ok'}.to_json
      rescue Exception => e
        puts "#{e.message}"
        e.backtrace[0..10].each { |t| puts "#{t}"}
        {'result' => 'Error', "message" => e.message }.to_json
      end
    end
  end

  # Receive tags data
  post APP_PATH + '/tag/add' do
    DB.add_tag params['tag'], params['color']
    # Redirect to the tags' list
    redirect to APP_PATH + "/tags"
  end

  get APP_PATH + '/tag/delete' do
    DB.delete_tag params['id']
    # Redirect to the tags' list
    redirect to APP_PATH + "/tags"
  end

  # Linking Tag to item
  get APP_PATH + '/tags/add/' do
    if params['code'] && params['id']
      DB.link_tag params['code'], params['id']
    end
    {'result' => 'Ok'}.to_json
  end

  # Unlinking Tag from item
  get APP_PATH + '/tags/remove/' do
    if params['code'] && params['id']
      DB.unlink_tag_from_item params['code'], params['id']
    end
    {'result' => 'Ok'}.to_json
  end

  # sending Tag infos
  get APP_PATH + '/tag/info/' do
    res = nil
    if params['id']
      res = DB.select_items_for_tag params['id']
    end
    res.to_json
  end

end
