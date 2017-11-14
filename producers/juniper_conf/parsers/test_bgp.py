from xml.dom import minidom
from .bgp import BgpPeeringParser
import unittest


class BgpParserTest(unittest.TestCase):
    def setUp(self):
        xml = minidom.parse("parsers/test_show_config.xml")
        self.bgp_peerings = BgpPeeringParser().parse(xml)

    def test_external(self):
        self.assertEqual(len(self.bgp_peerings), 18)
        esport = [bgp for bgp in self.bgp_peerings if bgp.as_number == '1337']
        self.assertEqual(len(esport), 2)
        self.assertEqual(esport[0].description, "D I G I T A L S P O R T S")
        self.assertEqual(esport[0].remote_address, "192.168.143.46")
        self.assertEqual(esport[0].type, "external")
        self.assertEqual(esport[0].group, "PNI")
        self.assertIsNone(esport[0].local_address)

    def test_internal(self):
        internal = [p for p in self.bgp_peerings if p.type == 'internal']
        self.assertEqual(len(internal), 6)
        self.assertEqual(internal[0].local_address, "192.168.67.1")
        self.assertEqual(internal[0].remote_address, "192.168.67.3")
        self.assertEqual(internal[0].group, "NORDUnet")
        self.assertIsNone(internal[0].description)
        self.assertIsNone(internal[0].as_number)

    def test_external_ipv6(self):
        ipv6 = [p for p in self.bgp_peerings if p.group == 'PNI-v6']
        self.assertEqual(len(ipv6), 3)
        self.assertEqual(ipv6[0].type, "external")
        self.assertEqual(ipv6[0].remote_address, "fd83:456:0:f008:0:0:0:3")
        self.assertEqual(ipv6[0].description, "Etwas-etwas")
        self.assertEqual(ipv6[0].as_number, "1234")
        self.assertIsNone(ipv6[0].local_address)

    def test_internal_ipv6(self):
        ipv6 = [p for p in self.bgp_peerings if p.group == 'NORDUnetIPv6']
        self.assertEqual(len(ipv6), 2)
        self.assertEqual(ipv6[0].local_address, "fc39:248:0:fa7:beef::1")
        self.assertEqual(ipv6[0].remote_address, "fc39:248:0:fa7:beef::2")
        self.assertEqual(ipv6[0].type, "internal")
        self.assertIsNone(ipv6[0].description)
        self.assertIsNone(ipv6[0].as_number)
