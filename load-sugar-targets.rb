#Require the library for SOAP
require 'rubygems'
require 'configatron'
require 'soap/wsdlDriver'
require 'digest/md5'
 
puts ''
puts ''
puts 'Starting to load the leads'
#Load our configuration file
$config = configatron.configure_from_yaml(File.expand_path(File.dirname(__FILE__) + "/config/config.yml"))

#Build a hash of the CSV file of the data to be imported
def build_csv_data 
  csv_data = Array.new
  File.open(File.expand_path(File.dirname(__FILE__) + "/" + $config["global_settings"]["csv_filename"])) do |f|
    begin
      loop do
        input_line = f.readline.delete("\r\n")
        input_line = input_line.split(',', 38)
        scrubbed_line = Array.new
        input_line.each do |line|
          scrubbed_line << line.gsub('"','')
        end
        csv_data << scrubbed_line
      end
    rescue EOFError
      puts "Done reading CSV file"
    end
  end
  csv_headers = csv_data.shift.map {|i| i.to_s }
  csv_rows = csv_data.map {|row| row.map {|cell| cell.to_s } }
  csv_leads = csv_rows.map {|row| Hash[*csv_headers.zip(row).flatten] }
  return csv_leads
end

#Build the address field with multiple lines
def build_address lead
  fields = $config["field_associations"]["primary_address"].split(',')
  address = String.new
  fields.each do |field|
    if lead[field] != ""
      address = address + lead[field] + "\n"
    end
  end
  return address
end

#Build the description field with multiple lines
def build_description lead
  fields = $config["field_associations"]["description"].split(',')
  description = String.new
  fields.each do |field|
    if lead[field] != nil
      description = description + field + ": " + lead[field] + "\n"
    end
  end
  return description
end

#Build the record to be inserted from the CSV row
def build_lead lead
  address = build_address(lead)
  description = build_description(lead)
  built_lead = [
                  { :name => "lead_status", :value => $config["global_settings"]["lead_status"] },
                  { :name => "lead_source", :value => $config["global_settings"]["lead_source"] },
                  { :name => "lead_source_description", :value => $config["global_settings"]["lead_source_description"] },
                  { :name => "assigned_to", :value => $config["global_settings"]["assigned_to"] },
                  { :name => "first_name", :value => lead[$config["field_associations"]["first_name"]] },
                  { :name => "last_name", :value => lead[$config["field_associations"]["last_name"]] },
                  { :name => "account_name", :value  => lead[$config["field_associations"]["account_name"]] },
                  { :name => "title", :value => lead[$config["field_associations"]["title"]] },
                  { :name => "office_phone", :value => lead[$config["field_associations"]["office_phone"]] },
                  { :name => "fax", :value => lead[$config["field_associations"]["fax"]] },
                  { :name => "email", :value => lead[$config["field_associations"]["email"]] },
                  { :name => "primary_addresss", :value => address },
                  { :name => "city", :value => lead[$config["field_associations"]["city"]] },
                  { :name => "state", :value => lead[$config["field_associations"]["state"]] },
                  { :name => "postal_code", :value => lead[$config["field_associations"]["postal_code"]] },
                  { :name => "country", :value => lead[$config["field_associations"]["country"]] },
                  { :name => "description", :value => description }
                ]
  return built_lead
end

#Build our credentials hash to be passed to the SOAP factory and converted to XML to pass to Sugar CRM
credentials = { "user_name" => $config["global_settings"]["username"], 
                "password" => Digest::MD5.hexdigest($config["global_settings"]["password"]) }

begin
  #Connect to the Sugar CRM WSDL and build our methods in Ruby
  ws_proxy = SOAP::WSDLDriverFactory.new($config["global_settings"]["wsdl_url"]).create_rpc_driver
  ws_proxy.options['protocol.http.ssl_config.verify_mode'] = OpenSSL::SSL::VERIFY_NONE
  
  #This may be toggled on to log XML requests/responses for debugging
  if $config["global_settings"]["trace_xml_wire"] == true
    ws_proxy.wiredump_file_base = "soap"
  end
  
  #Login to Sugar CRM
  session = ws_proxy.login(credentials, nil)
rescue => err
  puts err
  abort
end
 
#Check to see we got logged in properly
if session.error.number.to_i != 0
  puts session.error.description + " (" + session.error.number + ")"
  puts "Exiting"
  abort
else
  puts "Successfully logged in"
end

csv_leads = build_csv_data

cnt = 0
csv_leads.each do |lead|
  built_lead = build_lead(lead)
  if cnt == 0
    results = ws_proxy.set_entry(session['id'], $config["global_settings"]["module"], built_lead)
    if session.error.number.to_i != 0
      puts session.error.description + " (" + session.error.number + ")"
    else
      puts 'Successfully processed record # ' + (cnt + 1).to_s
    end
  end
  cnt += 1
end

puts "Processed " + (cnt + 1).to_s + " records"