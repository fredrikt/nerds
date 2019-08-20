import base64
import json
from urllib.request import Request, urlopen


class Api(object):
    def __init__(self, url, user, password):
        self.url = url
        self.user = user
        self.password = password

    def get(self, path, collection=False):
        url = '{}{}'.format(self.url, path)
        accept = 'application/vnd.yang.data+json'
        if collection:
            accept = 'application/vnd.yang.collection+json'
        headers = {
            'Authorization': self.auth(),
            'Accept': accept
        }
        with urlopen(Request(url, headers=headers)) as r:
            try:
                result = json.load(r)
            except json.decoder.JSONDecodeError:
                # Ignore
                result = {}
        return result

    def post(self, path, data=None):
        url = '{}{}'.format(self.url, path)
        headers = {
            'Authorization': self.auth(),
            'Accept': 'application/vnd.yang.data+json',
        }
        with urlopen(Request(url, headers=headers, method='POST'), data=data) as r:
            try:
                result = json.load(r)
            except json.decoder.JSONDecodeError:
                # Ignore
                result = {}
        return result

    def auth(self):
        basic = '{}:{}'.format(self.user, self.password).encode('UTF-8')
        return 'Basic {}'.format(base64.encodestring(basic).decode('UTF-8')[:-1])
