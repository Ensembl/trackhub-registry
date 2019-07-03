import requests, sys

server = 'http://127.0.0.1:3000'
hub_url = 'http://genome-test.gi.ucsc.edu/~hiram/hubs/Plants/hub.txt'
user = 'trackhub1'
password = 'trackhub1'

def login(server, user, password):
    r = requests.get(server+'/api/login', auth=(user, password), verify=False)
    if not r.ok:
        print "Couldn't login, reason: %s [%d]" % (r.text, r.status_code)
        sys.exit

    auth_token = r.json()[u'auth_token']
    print 'Logged in [%s]' % auth_token
    return auth_token

def logout(server, user, auth_token):
    r = requests.get(server+'/api/logout', headers={ 'user': user, 'auth_token': auth_token })    
    if not r.ok:
       print "Couldn't logout, reason: %s [%d]" % (r.text, r.status_code)
       sys.exit
    print 'Logged out'

auth_token = login(server, user, password)
headers = { 'user': user, 'auth_token': auth_token }
payload = { 'url': hub_url, 'assemblies': { 'araTha1': 'GCA_000001735.1', 'ricCom1': 'GCA_000151685.2', 'braRap1': 'GCA_000309985.1' } }
r = requests.post(server+'/api/trackhub', headers=headers, json=payload, verify=False)
if not r.ok:
   print "Couldn't logout, reason: %s [%d]" % (r.text, r.status_code)
   sys.exit
print "I have registered hub at %s" % hub_url

logout(server, user, auth_token)
