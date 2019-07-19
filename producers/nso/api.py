import base64
import json
from urllib.request import Request, urlopen


class Api(object):
    def __init__(self, url, user, password):
        self.url = url
        self.user = user
        self.password = password

    def get(self, path):
        url = '{}{}'.format(self.url, path)
        headers = {
            'Authorization': self.auth(),
            'Accept': 'application/vnd.yang.data+json'
        }
        with urlopen(Request(url, headers=headers)) as r:
            result = json.load(r)
        return result

    def auth(self):
        basic = '{}:{}'.format(self.user, self.password).encode('UTF-8')
        return 'Basic {}'.format(base64.encodestring(basic).decode('UTF-8')[:-1])
