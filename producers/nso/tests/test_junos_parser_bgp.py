import unittest
from parser import junos


def wrap_groups(data):
    return {
        'junos:bgp': {
            'group': data
        }
    }


class BgpJunosParserTest(unittest.TestCase):
    def test_internal(self):
        data = wrap_groups([
            {
                'name': 'NORDUnet',
                'type': 'internal',
                'local-address': '192.168.3.5',
                'neighbor': [
                    {
                        'name': '192.168.3.1',
                        'description': 'se-tug',
                    },
                    {
                        'name': '192.168.3.2',
                        'description': 'se-fre',
                    }
                ]
            }
        ])

        peerings = junos.parse_bgp_sessions(data)
        self.assertEqual(len(peerings), 2)
        peering1 = peerings[0]
        self.assertEqual(peering1.type, 'internal')
        self.assertEqual(peering1.group, 'NORDUnet')
        self.assertEqual(peering1.description, 'se-tug')
        self.assertEqual(peering1.local_address, '192.168.3.5')
        self.assertEqual(peering1.remote_address, '192.168.3.1')
        self.assertIsNone(peering1.as_number)

        peering2 = peerings[1]
        self.assertEqual(peering2.type, 'internal')
        self.assertEqual(peering2.group, 'NORDUnet')
        self.assertEqual(peering2.description, 'se-fre')
        self.assertEqual(peering2.local_address, '192.168.3.5')
        self.assertEqual(peering2.remote_address, '192.168.3.2')
        self.assertIsNone(peering2.as_number)

    def test_external(self):
        data = wrap_groups([
            {
                'name': 'NRN-customer',
                'type': 'external',
                'neighbor': [
                    {
                        'name': '192.168.4.11',
                        'description': 'DeIC',
                        'peer-as': '1835'
                    }
                ]
            }
        ])

        peerings = junos.parse_bgp_sessions(data)
        self.assertEqual(len(peerings), 1)
        peering = peerings[0]

        self.assertEqual(peering.group, 'NRN-customer')
        self.assertEqual(peering.type, 'external')
        self.assertEqual(peering.description, 'DeIC')
        self.assertEqual(peering.remote_address, '192.168.4.11')
        self.assertEqual(peering.as_number, '1835')
        self.assertIsNone(peering.local_address)

    def test_no_type(self):
        data = wrap_groups([
            {
                'name': 'Weird',
                'neighbor': [
                    {
                        'name': '192.168.4.12',
                    }
                ]
            }
        ])

        peerings = junos.parse_bgp_sessions(data)
        self.assertEqual(len(peerings), 1)
        peering = peerings[0]

        self.assertEqual(peering.group, 'Weird')
        self.assertEqual(peering.remote_address, '192.168.4.12')
        self.assertIsNone(peering.type)
        self.assertIsNone(peering.description)
        self.assertIsNone(peering.as_number)
        self.assertIsNone(peering.local_address)

    def test_empty(self):
        data = {}
        peerings = junos.parse_bgp_sessions(data)
        self.assertEqual(peerings, [])
