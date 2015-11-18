require 'net/https'
require 'uri'
 
server='http://127.0.0.1:3000'
path = '/api/login'
 
url = URI.parse(server)
http = Net::HTTP.new(url.host, url.port)
#http.use_ssl = true
#http.verify_mode = OpenSSL::SSL::VERIFY_NONE

request = Net::HTTP::Get.new(path)
request.basic_auth("trackhub1", "trackhub1")
response = http.request(request)
 
if response.code != "200"
  puts "Invalid response: #{response.code}"
  puts response.body
  exit
end

require 'rubygems'
require 'json'
 
result = JSON.parse(response.body)
puts "Logged in [#{result["auth_token"]}]"
