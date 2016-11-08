import requests, sys

r = requests.get('http://127.0.0.1:3000/api/login', auth=('trackhub1', 'trackhub1'), verify=False)
if not r.ok:
    print ("Couldn\'t login, reason: %s [%d]" % (r.text, r.status_code)) 
    sys.exit()

auth_token = r.json()[u'auth_token']
print ('Logged in [%s]' % auth_token)
