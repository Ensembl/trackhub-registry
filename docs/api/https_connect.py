import requests, sys

# see http://docs.python-requests.org/en/latest/user/advanced/#ssl-cert-verification

r = requests.get('https://twitter.com', verify=True)
if not r.ok:
    r.raise_for_status()
    sys.exit()
