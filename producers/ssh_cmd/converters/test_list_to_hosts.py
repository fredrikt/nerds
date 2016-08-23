import unittest
from .list_converter import list_to_hosts

class ListToHostTest(unittest.TestCase):

    def test_simple(self):
        hosts = ['one.example.org', 'two.example.org']
        template = {'syslog': True}

        result = list_to_hosts(hosts, "syslog", template)

        self.assertEqual(len(result), 2)
        h1, h2 = result
        self.assertEqual(h1['host']['name'], 'one.example.org')
        self.assertEqual(h1['host']['version'], 1)
        self.assertEqual(h1['host']['syslog'], template)

        self.assertEqual(h2['host']['name'], 'two.example.org')
        self.assertEqual(h2['host']['version'], 1)
        self.assertEqual(h2['host']['syslog'], template)
