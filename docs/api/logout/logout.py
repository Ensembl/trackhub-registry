import requests, sys

server = 'http://127.0.0.1:3000'
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

auth_token = login(server, user, password)
r = requests.get(server+'/api/logout', headers={ 'user': user, 'auth_token': auth_token })
if not r.ok:
    print "Couldn't logout, reason: %s [%d]" % (r.text, r.status_code)
    sys.exit
print 'Logged out'
