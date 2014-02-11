# coding: utf-8

require 'rubygems'
require 'scraperwiki'
# require 'mechanize'
require 'nokogiri'
require 'pdf-reader'
require 'open-uri'

# --------------------
# scrapable_classes.rb
# --------------------

module RestfulApiMethods

  @model =  ''
  @API_url = ''

  def format info
    info
  end

  def put record
    # RestClient.put @API_url + @model, record, {:content_type => :json}
  end

  def post record
    if (ScraperWiki.select("* from data where `uid`='#{record['uid']}'").empty? rescue true)
      puts "Adds new record " + record['uid']
      ScraperWiki.save_sqlite(['uid'], record)
    else
      puts "Skipping already saved record " + record['uid']
    end
    # RestClient.post @API_url + @model, record, {:content_type => :json}
  end
end

class StorageableInfo
  include RestfulApiMethods

  def initialize(location = '')
    @API_url = 'http://middleware.congresodechile.cl/'
    @location = location
  end

  def process
    doc_locations.each do |doc_location|
      begin
        doc = read doc_location
        info = get_info doc
        record = format info
        save record
      rescue Exception=>e
        p e
      end
    end
  end

  def read location = @location
    # it would be better if instead we used
    # mimetype = `file -Ib #{path}`.gsub(/\n/,"")
    if location.class.name != 'String'
      doc = location
    elsif !location.scan(/pdf/).empty?
      doc_pdf = PDF::Reader.new(open(location))
      doc = ''
      doc_pdf.pages.each do |page|
        doc += page.text
      end
    else
      doc = open(location).read
    end
    doc
  end

  def doc_locations
    [@location]
  end

  def get_info doc
    doc
  end
end


# ------------------------
# sil_scrapable_classes.rb
# ------------------------

class CongressTable < StorageableInfo

  def initialize()
    super()
    @model = 'tables'
    @API_url = 'http://localhost:3000/'
    @chamber = ''
  end

  def save record
    post record
  end

  # def post record
  #   RestClient.post @API_url + @model, {low_chamber_agenda: record}, {:content_type => :json}
  # end

  def format info
    record = {
      :uid => info['legislature'] + '-' + info['session'],
      :date => info['date'],
      :chamber => @chamber,
      :legislature => info['legislature'],
      :session => info['session'],
      :bill_list => info['bill_list']
    }
  end

  def get_link(url, base_url, xpath)
    html = Nokogiri::HTML.parse(read(url), nil, 'utf-8')
    base_url + html.xpath(xpath).first['href']
  end
end

class CurrentHighChamberTable < CongressTable
  def initialize()
    super()
    @location = 'http://www.senado.cl/appsenado/index.php?mo=sesionessala&ac=doctosSesion&tipo=27'
    @base_url = 'http://www.senado.cl'
    @chamber = 'Senado'
  end

  def process
    puts 'processing'
    puts doc_locations
    doc_locations.each do |doc_location|
      begin
        doc = read doc_location
        info = get_info doc #obtain the data values
        record = format info
        puts '</-- record --->'
        puts record
        puts '<--- record --/>'
        save record
      rescue Exception=>e
      end
    end
  end

  def doc_locations
    html = Nokogiri::HTML(read(@location), nil, 'utf-8')
    doc_locations = Array.new

    doc_locations.push @base_url + html.xpath("//a[@class='citaciones']/@href").to_s.strip
    return doc_locations
  end

  def get_info doc
    info = Hash.new

    rx_bills = /Bolet(.*\d+-\d+)*/
    bills = doc.scan(rx_bills)

    bill_list = []
    rx_bill_num = /(\d{0,3})[^0-9]*(\d{0,3})[^0-9]*(\d{1,3})[^0-9]*(-)[^0-9]*(\d{2})/
    bills.each do |bill|
      bill.first.scan(rx_bill_num).each do |bill_num_array|
        bill_num = (bill_num_array).join('')
        bill_list.push(bill_num)
      end
    end

    # Get date
    rx_date = /(\d{1,2}) (?:de ){0,1}(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre) (?:de ){0,1}(\d{4})/
    date_sp = doc.scan(rx_date).first
    date = date_sp_2_en(date_sp).join(' ')

    # Get legislature
    rx_legislature = /LEGISLATURA\sN\W+.(\d{3})/
    legislature = doc.scan(rx_legislature).flatten.first

    # Get session
    rx_session = /Sesi\Wn+.(\d{1,3})/
    session = doc.scan(rx_session).flatten.first

    return {'bill_list' => bill_list, 'date' => date, 'legislature' => legislature, 'session' => session}
  end

  def date_sp_2_en date
    day = date [0]
    month = date [1]
    year = date [2]
    months = {'enero' => 'january', 'febrero' => 'february', 'marzo' => 'march', 'abril' => 'april', 'mayo' => 'may', 'junio' => 'june', 'julio' => 'july', 'agosto' => 'august', 'septiembre' => 'september', 'octubre' => 'october', 'noviembre' => 'november', 'diciembre' => 'december'}
    en_date = [months[month], day, year]
    return en_date
  end
end

class CurrentLowChamberTable < CongressTable

  def initialize()
    super()
    @model = 'low_chamber_agendas'
    @location = 'http://www.camara.cl/trabajamos/sala_documentos.aspx?prmTIPO=TABLA'
    @chamber = 'C.Diputados'
    @session_base_url = 'http://www.camara.cl/trabajamos/'
    @table_base_url = 'http://www.camara.cl'
    @session_xpath = '//*[@id="detail"]/table/tbody/tr[1]/td[2]/a'
    @table_xpath = '//*[@id="detail"]/table/tbody/tr[1]/td/a'
  end

  def doc_locations
    doc_locations_array = Array.new
    # session_url = get_link(@location, @session_base_url, @session_xpath)
    table_url = get_link(@location, @table_base_url, @table_xpath)
    puts "table_url"
    puts table_url
    puts "/table_url"
    doc_locations_array.push(table_url)
    # get all with doc.xpath('//*[@id="detail"]/table/tbody/tr[(position()>0)]/td[2]/a/@href').each do |tr|
  end

  def get_info doc
    rx_bills = /Bolet(.*\d+-\d+)*/
    bills = doc.scan(rx_bills)
    
    bill_list = []
    rx_bill_num = /(\d{0,3})[^0-9]*(\d{0,3})[^0-9]*(\d{1,3})[^0-9]*(-)[^0-9]*(\d{2})/
    bills.each do |bill|
      bill.first.scan(rx_bill_num).each do |bill_num_array|
        bill_num = (bill_num_array).join('')
        bill_list.push(bill_num)
      end
    end

    # get date
    rx_date = /(\d{1,2}) (?:de ){0,1}(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre) (?:de ){0,1}(\d{4})/
    date_sp = doc.scan(rx_date).first
    date = date_sp_2_en(date_sp).join(' ')

    # get legislature
    rx_legislature = /(\d{3}).+LEGISLATURA/
    legislature = doc.scan(rx_legislature).flatten.first

    # get session
    rx_session = /Sesi.+?(\d{1,3})/
    session = doc.scan(rx_session).flatten.first

    return {'bill_list' => bill_list, 'date' => date, 'legislature' => legislature, 'session' => session}
  end
end

class BillCategory < StorageableInfo

  def initialize
    super()
    @location = 'bill_categories'
    @bills_location = 'bills'
    @match_info_location = 'categories'
    @model = 'bills'

    @bills = parse(read(@bills_location))
    @categorized_bills = parse(read(@match_info_location))
  end

  def save record
    post record
  end

  def doc_locations
    parse(read(@location))
  end

  def parse doc
    doc_hash = {}
    doc.split(/\n/).each do |pair|
      key, val = pair.split(/\t/)
      if doc_hash.has_key?(key)
        doc_hash[key].push(val)
      else
        doc_hash.store(key, [val])
      end
    end
    doc_hash
  end

  def get_info doc
    bill, cat_ids = doc
    cat_array = []
    cat_ids.each do |cat_id|
      cat_val = @categorized_bills[cat_id]
      cat_array.push(cat_val)
    end
    [bill, cat_array]
  end

  def format info
    puts 'in format info'
    bill, categories = info
    record = {
      :uid => @bills[bill].first,
      :matters => categories.join('|')
    }
  end
end


# ----------------
# launcher scraper
# ----------------

if !(defined? Test::Unit::TestCase)
  CurrentHighChamberTable.new.process
  # CurrentLowChamberTable.new.process
end
