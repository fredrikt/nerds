import unittest
from .list_converter import to_list

class ToListTest(unittest.TestCase):

    def test_to_list(self):
        host = 'syslog.example.org'
        hosts = ['one.example.org', 'two.example.org']
        list_key = 'hosts'

        result = to_list(host, hosts, 'rsyslog', list_key)

        self.assertEqual(result['host']['name'], host)
        self.assertEqual(result['host']['version'], 1)
        self.assertEqual(result['host']['rsyslog'], {'hosts': hosts})




