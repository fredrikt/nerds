from xml.dom import minidom
from .interfaces import InterfaceParser
import unittest
import json


class InterfaceParserTest(unittest.TestCase):
    def setUp(self):
        self.xml = minidom.parse("parsers/test_show_config.xml")
        self.interfaces = InterfaceParser().parse(self.xml)

    def test_basic(self):
        self.assertEqual(len(self.interfaces), 6)
        self.contains(lambda i: i.vlantagging)
        self.contains(lambda i: i.name == "xe-0/0/0")
        i = [i for i in self.interfaces if i.name == "xe-0/0/0"][0]
        self.assertTrue(i.vlantagging)
        self.assertEqual(i.description, "patch to sw-test-sw-02, se-tug.se-test-sw-02")
        self.assertFalse(i.inactive)
        self.assertEqual(len(i.unitdict), 3)
        unit = i.unitdict[0]
        self.assertEqual(unit['unit'], "101")
        self.assertEqual(unit['vlanid'], "101")
        self.assertEqual(unit['description'], "ndn-test-l3")
        self.assertIn("192.168.1.45/30", unit['address'])
        self.assertIn("fc00:289:3:b::1/64", unit['address'])
        self.assertEqual(unit['inactive'], False)

        unit = i.unitdict[2]
        self.assertEqual(unit['unit'], "202")
        self.assertEqual(unit['vlanid'], "202")
        self.assertEqual(unit['description'], "se-test testlan se-test-sw-01, se-test.test-serv")
        self.assertIn("192.168.24.17/28", unit['address'])
        self.assertIn("192.168.25.1/26", unit['address'])
        self.assertIn("fc00:521:0:f005::2/64", unit['address'])
        self.assertIn("fc00:345:4:2::1/64", unit['address'])

    def test_bundle(self):
        bundled = [i for i in self.interfaces if i.bundle]
        self.assertEqual(len(bundled), 2)
        self.assertEqual(bundled[0].bundle, "3fe")
        self.assertEqual(bundled[0].name, "xe-0/0/3")
        self.assertEqual(bundled[0].description, "Link to Akamai cluster, akamai-test-phy1")
        self.assertFalse(bundled[0].vlantagging)
        self.assertEqual(bundled[0].unitdict, [])
        self.contains(lambda i: i.name == "3fe")

    def test_with_physical(self):
        physical_interface = ["xe-0/0/0", "xe-0/0/1", "xe-0/0/3", "xe-0/0/4", "3fe", "whoooot", "ae4"]
        self.interfaces = InterfaceParser().parse(self.xml, physical_interface)
        self.assertEqual(len(self.interfaces), 7)
        self.contains(lambda i: i.name == "whoooot")

    def test_logical_systems(self):
        self.interfaces = InterfaceParser().parse(self.xml)
        et = [i for i in self.interfaces if i.name == 'xe-0/0/4']
        self.assertEqual(len(et), 1, 'Expected only one xe-0/0/4 interface')
        # Check that there are two interfaces 10 and 1002
        units = [u.get('unit') for u in i.unitdict]
        self.assertEqual(sorted(units), ['10', '1002'])

    def contains(self, fn):
        result = [i for i in self.interfaces if fn(i)]
        self.assertTrue(len(result) > 0, "Expected at least one matching interface")

    def list_all(self):
        print("Interfaces:")
        for i in self.interfaces:
            print(json.dumps(i.to_json(), indent=2))
