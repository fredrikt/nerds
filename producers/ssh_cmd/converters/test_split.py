import unittest
from .list_converter import split

class SplitConverterTest(unittest.TestCase):

    def test_split(self):
        host = 'one.example.org'
        _list = ['MemTotal   : 3969876 kB', 'MemFree: 120056 kB']

        result = split(host, "mem_info", _list, ':')

        self.assertEqual(result['host']['name'], host)
        self.assertEqual(result['host']['version'], 1)
        self.assertEqual(result['host']['mem_info'], {
            'MemTotal': '3969876 kB',
            'MemFree': '120056 kB'
                })
