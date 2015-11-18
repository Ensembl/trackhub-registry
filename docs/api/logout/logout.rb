require 'net/https'
require 'uri'

require 'rubygems'
require 'json'

def login(user, pass)
  request = Net::HTTP::Get.new('/api/login')
  request.basic_auth(user, pass)
  response = $http.request(request)
  
  if response.code != "200"
    puts "Couldn't login, reason: #{response.body} [#{response.code}]"
    exit
  end

  result = JSON.parse(response.body)
  puts "Logged in [#{result["auth_token"]}]"
  
  return result["auth_token"]
end

server = 'http://127.0.0.1:3000'
user = 'trackhub1'
pass = 'trackhub1'

url = URI.parse(server)
$http = Net::HTTP.new(url.host, url.port)
# $http.use_ssl = true
# $http.verify_mode = OpenSSL::SSL::VERIFY_NONE

auth_token = login(user, pass)

request = Net::HTTP::Get.new('/api/logout')
request["User"] = user
request["Auth-Token"] = auth_token
response = $http.request(request)
 
if response.code != "200"
  puts "Invalid response: #{response.code}"
  puts response.body
  exit
end

puts 'Logged out'
