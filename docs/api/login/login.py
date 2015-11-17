import requests, sys

server = 'http://127.0.0.1:3000'
endpoint = '/api/login'

r = requests.get(server+endpoint, auth=('trackhub1', 'trackhub1'))
if not r.ok:
    # r.raise_for_status()
    print "Couldn\'t login, reason: %s [%d]" % (r.text, r.status_code) 
    sys.exit()

auth_token = r.json()[u'auth_token']
print 'Logged in'
