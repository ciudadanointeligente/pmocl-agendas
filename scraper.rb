require 'rubygems'
require 'scraperwiki'
#require 'rest-client'
require 'nokogiri'
require 'open-uri'
require 'pdf-reader'
require 'json'

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
    # RestClient.post @API_url + @model, record, {:content_type => :json}
  end
end

class StorageableInfo
  include RestfulApiMethods

  def initialize(location = '')
    @API_url = 'http://localhost:3000/'
    @location = location
  end

  def process
    doc_locations.each do |doc_location|
      begin
        doc = read doc_location
        # puts "<!---- raw doc ------>"
        # puts doc
        # puts "<----- raw doc -----/>"
        info = get_info doc

        info.delete_if { |k, v| v.nil? }
        if !info['bill_list'].empty? # if the document is valid then
          record = format info
          # puts '<!---- debug ' + @chamber + ' ------>'
          # puts record
          # puts '<----- debug ' + @chamber + ' -----/>'
          save record
        else
          puts "The current " + @chamber.to_s + " agenda hasn't relevant information."
        end
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


# ---------------
# agendas_info.rb
# ---------------

class CongressTable < StorageableInfo

  def initialize()
    super()
    @model = 'agendas'
    @API_url = 'http://middleware.congresoabierto.cl/'
    @chamber = ''
  end

  def save record
    post record
  end

  def post record
    #######################
    # for use with morph.io
    #######################

    if ((ScraperWiki.select("* from data where `uid`='#{record['uid']}'").empty?) rescue true)
      # Convert the array record['bill_list'] to a string (by converting to json)
      record['bill_list'] = JSON.dump(record['bill_list'])
      ScraperWiki.save_sqlite(['uid'], record)
      puts "Adds new record " + record['uid']
    else
      puts "Skipping already saved record " + record['uid']
    end

    ###############################
    # for use with pmocl middleware
    ###############################

    #RestClient.post @API_url + @model, {agenda: record}, {:content_type => :json}
    #puts "Saved"
  end

  def format info
    record = {
      'uid' => info['legislature'] + '-' + info['session'],
      'date' => info['date'],
      'chamber' => @chamber,
      'legislature' => info['legislature'],
      'session' => info['session'],
      'bill_list' => info['bill_list'],
      'date_scraped' => Date.today.to_s
    }
  end

  def date_format date
    day = date [0]
    month = date [1]
    year = date [2]
    if day.length < 2 then day = "0" + day end
    months_num = {'enero' => '01', 'febrero' => '02', 'marzo' => '03', 'abril' => '04', 'mayo' => '05', 'junio' => '06', 'julio' => '07', 'agosto' => '08', 'septiembre' => '09', 'octubre' => '10', 'noviembre' => '11', 'diciembre' => '12'}

    date = [year, months_num[month], day]
    return date
  end

  def get_link(url, base_url, xpath)
    html = Nokogiri::HTML.parse(read(url), nil, 'utf-8')
    base_url + html.xpath(xpath).first['href']
  end
end

class CurrentHighChamberAgenda < CongressTable
  def initialize()
    super()
    @location = 'http://www.senado.cl/appsenado/index.php?mo=sesionessala&ac=doctosSesion&tipo=27'
    @base_url = 'http://www.senado.cl'
    @chamber = 'Senado'
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

    # get date
    rx_date = /(\d{1,2}) (?:de ){0,1}(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre) (?:de ){0,1}(\d{4})/
    date_sp = doc.scan(rx_date).first
    if !date_sp.nil? then date = date_format(date_sp).join('-') end

    # get legislature
    rx_legislature = /LEGISLATURA\sN\W+.(\d{3})/
    legislature = doc.scan(rx_legislature).flatten.first

    # get session
    rx_session = /Sesi\Wn+.(\d{1,3})/
    session = doc.scan(rx_session).flatten.first

    return {'bill_list' => bill_list, 'date' => date, 'legislature' => legislature, 'session' => session}
  end
end

class CurrentLowChamberAgenda < CongressTable

  def initialize()
    super()
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
    if !date_sp.nil? then date = date_format(date_sp).join('-') end

    # get legislature
    rx_legislature = /(\d{3}).+LEGISLATURA/
    legislature = doc.scan(rx_legislature).flatten.first

    # get session
    rx_session = /Sesi.+?(\d{1,3})/
    session = doc.scan(rx_session).flatten.first

    return {'bill_list' => bill_list, 'date' => date, 'legislature' => legislature, 'session' => session}
  end
end

class CurrentLowChamberBillQuorum < CongressTable

  def initialize()
    super()
    @location = 'http://www.camara.cl/trabajamos/sala_documentos.aspx?prmTIPO=TABLA'
    @chamber = 'C.Diputados'
    @model = 'bill_quorums'
    @session_base_url = 'http://www.camara.cl/trabajamos/'
    @table_base_url = 'http://www.camara.cl'
    @session_xpath = '//*[@id="detail"]/table/tbody/tr[1]/td[2]/a'
    @table_xpath = '//*[@id="detail"]/table/tbody/tr[1]/td/a'
  end

  def process
    doc_locations.each do |doc_location|
      #begin
        doc = read doc_location
        infos = get_info doc
        i = 0
        infos.each do |info|
          record = format info[1]
          puts "<!----- debug ------>"
          puts record
          puts "API url: " + @API_url.to_s
          puts "model  : " + @model.to_s
          puts "<------ debug -----/>"
          save record
          i = i + 1
        end
        puts "Finish"
      #rescue Exception=>e
      #end
    end
  end

  def post record
    #######################
    # for use with morph.io
    #######################

    if ((ScraperWiki.select("* from data where `uid`='#{record['uid']}'").empty?) rescue true)
      # Convert the array record['bill_list'] to a string (by converting to json)
      record['bill_list'] = JSON.dump(record['bill_list'])
      ScraperWiki.save_sqlite(['uid'], record)
      puts "Adds new record " + record['uid']
    else
      puts "Skipping already saved record " + record['uid']
    end

    ###############################
    # for use with pmocl middleware
    ###############################

    #RestClient.post @API_url + @model, {bill_quorum: record}, {:content_type => :json}
    #puts "Saved"
    #sleep 0.1
  end

  def format info
    record = {
      'uid' => info['bill_id'],
      'num_quorum' => info['num_quorum'],
      'raw_quorum' => info['raw_quorum'],
      'date_scraped' => Date.today.to_s
    }
  end

  def doc_locations
    doc_locations_array = Array.new
    # session_url = get_link(@location, @session_base_url, @session_xpath)
    table_url = get_link(@location, @table_base_url, @table_xpath)
    # puts "<!-------------- table_url --------------->"
    # table_url = "http://www.camara.cl/pdf.aspx?prmID=10374&prmTIPO=TEXTOSESION"         # for testing
    # puts table_url
    # puts "<--------------- table_url --------------/>"
    doc_locations_array.push(table_url)
    # get all with doc.xpath('//*[@id="detail"]/table/tbody/tr[(position()>0)]/td[2]/a/@href').each do |tr|
  end

  def get_info doc
    rx_voting_quorums = /Bolet\D*(\d*-\d*)(?mx:.*?)(?mx:\*{3}(?mx:(.*?)))(?:\s{4})/
    voting_quorums = doc.scan(rx_voting_quorums)

    rx_bill_num = /(\d*-\d*)/
    rx_quorum_case_1 = /Este proyecto contiene disposiciones de(.+)/
    rx_quorum_case_2 = /(qu.rum.+)/
    rx_quorum_case_3 = /(\d\/\d)/

    i = 0
    bill_quorum = Hash.new

    voting_quorums.each do |voting_quorum|
      bill_id = String.new
      raw_quorum = Array.new
      num_quorum = Array.new

      # obtain bill_id
      voting_quorum.each do |bill|
        if !bill.scan(rx_bill_num).empty?
          bill_id = bill.scan(rx_bill_num).flatten.first
        end
      end

      # obtain raw_quorum
      voting_quorum.each do |quorum|
        if !quorum.scan(rx_quorum_case_1).empty?
          raw_quorum.push(quorum.scan(rx_quorum_case_1).flatten.first.gsub('de', '').gsub(' y ', '').gsub('.', '').strip)
        end

        if !quorum.scan(rx_quorum_case_2).empty?
          raw_quorum.push(quorum.scan(rx_quorum_case_2).flatten.first.gsub('de', '').gsub(' y ', '').gsub('.', '').strip)
        end

        if !quorum.scan(rx_quorum_case_3).empty?
          raw_quorum.push(quorum.scan(rx_quorum_case_3).flatten.first.gsub('de', '').gsub(' y ', '').gsub('.', '').strip)
        end
      end

      # formatting to a fractional representation
      raw_quorum.each do |quorum|
        if quorum.include? "orgánica constitucional"
          num_quorum.push("4/7")
        elsif quorum.include? "interpretativa de la constitución"
          num_quorum.push("3/5")
        elsif quorum.include? "quórum calificado" #mayoría absoluta
          num_quorum.push("60+")
        else
          num_quorum.push(quorum)
        end
      end

      if !raw_quorum.empty?
        bill_quorum[i] = { 'bill_id' => bill_id, 'num_quorum' => num_quorum, 'raw_quorum' => raw_quorum }
        i = i+1
      end
    end
    bill_quorum
  end
end


# -----------------
# agendas_runner.rb
# -----------------

if !(defined? Test::Unit::TestCase)
  CurrentHighChamberAgenda.new.process
  # CurrentHighChamberBillQuorum.new.process
  CurrentLowChamberAgenda.new.process
  #CurrentLowChamberBillQuorum.new.process
end
