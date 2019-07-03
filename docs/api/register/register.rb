require 'net/https'
require 'uri'

require 'rubygems'
require 'json'

server = 'http://127.0.0.1:3000'
hub_url = 'http://genome-test.gi.ucsc.edu/~hiram/hubs/Plants/hub.txt'
user = 'trackhub1'
pass = 'trackhub1'

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

def logout(user, auth_token)
  request = Net::HTTP::Get.new('/api/logout', { 'User' => user, 'Auth-Token' => auth_token })
  response = $http.request(request)
 
  if response.code != "200"
    puts "Invalid response: #{response.code}"
    puts response.body
    exit
  end

  puts 'Logged out'
end
      
url = URI.parse(server)
$http = Net::HTTP.new(url.host, url.port)
# $http.use_ssl = true
# $http.verify_mode = OpenSSL::SSL::VERIFY_NONE

auth_token = login(user, pass)

request = Net::HTTP::Post.new('/api/trackhub', { 'Content-Type' => 'application/json', 'User' => user, 'Auth-Token' => auth_token })
request.body = { 'url' => hub_url, 'assemblies' => { 'araTha1' => 'GCA_000001735.1', 'ricCom1' => 'GCA_000151685.2', 'braRap1' => 'GCA_000309985.1' } }.to_json
response = $http.request(request)
if response.code != "201"
  puts "Invalid response: #{response.code} #{response.body}"
  exit
end

puts "I have registered hub at #{hub_url}" 

logout(user, auth_token)
