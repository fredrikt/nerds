import unittest
from parser import junos


def unit_addr(*cidr):
    return {'address': [{'name': a} for a in cidr]}


class JunosParserTest(unittest.TestCase):
    def test_is_junos_with_junos(self):
        data = {
            "tailf-ncs:device": {
                "name": "some-device",
                "config": {
                    "tailf-ned-arista-dcs:EXEC": {
                        "operations": {}
                    },
                    "junos:configuration": {
                        "version": "12.1X44-D30.4",
                    }
                }
            }
        }
        self.assertTrue(junos.is_junos(data))

    def test_is_junos_with_arista(self):
        data = {
            "tailf-ncs:device": {
                "name": "some-device",
                "config": {
                    "tailf-ned-arista-dcs:boot": {
                        "system": "flash:/EOS-4.20.5F-INT.swi"
                    },
                }
            }
        }
        self.assertFalse(junos.is_junos(data))

    def test_parse_router(self):
        data = {
            'tailf-ncs:device': {
                'name': 'some-device',
                'address': 'lo0.some-device.nordu.net',
                'config': {
                    'junos:configuration': {
                        'version': '12.1X44-D30.3'
                    }
                }
            }
        }
        router = junos.parse_router(data)

        self.assertEqual(router.name, 'some-device.nordu.net')
        self.assertEqual(router.version, '12.1X44-D30.3')
        self.assertEqual(router.model, '')
        self.assertEqual(router.hardware, {})

    def test_with_chassis_info(self):
        data = {
            'tailf-ncs:device': {
                'name': 'some-device',
                'address': 'lo0.some-device.nordu.net',
                'config': {
                    'junos:configuration': {
                        'version': '12.1X44-D30.3'
                    }
                }
            }
        }
        chassis_data = {
            'junos-rpc:output': {
                'chassis-inventory': {
                    'chassis': {
                        'name': 'Chassis',
                        'serial-number': 'SNID32AS',
                        'description': 'MX2010',
                        'chassis-module': [
                            {
                                'name': 'Something 1',
                            }
                        ]
                    }
                }
            }
        }
        router = junos.parse_router(data, chassis_data)

        self.assertEqual(router.name, 'some-device.nordu.net')
        self.assertEqual(router.version, '12.1X44-D30.3')
        self.assertEqual(router.model, 'MX2010')
        hw = router.hardware
        self.assertEqual(hw['name'], 'Chassis')
        self.assertEqual(hw['serial-number'], 'SNID32AS')
        self.assertEqual(hw['description'], 'MX2010')
        self.assertEqual(len(hw['sub-modules']), 1)
        self.assertEqual(hw['sub-modules'][0]['name'], 'Something 1')

    def test_with_emptychassis_info(self):
        data = {
            'tailf-ncs:device': {
                'name': 'some-device',
                'address': 'lo0.some-device.nordu.net',
                'config': {
                    'junos:configuration': {
                        'version': '12.1X44-D30.3'
                    }
                }
            }
        }
        chassis_data = {
            'junos-rpc:output': {
            }
        }
        router = junos.parse_router(data, chassis_data)

        self.assertEqual(router.name, 'some-device.nordu.net')
        self.assertEqual(router.version, '12.1X44-D30.3')
        self.assertEqual(router.model, '')
        self.assertEqual(router.hardware, {})


class JunosParseInterfaceTest(unittest.TestCase):

    def test_bundled(self):
        data = {
            'name': 'et-1/0/1',
            'description': 'neat',
            'gigether-options': {
                'ieee-802.3ad': {
                    'bundle': 'ae1',
                }
            }
        }
        iface = junos.parse_interface(data)
        self.assertEqual(iface.name, 'et-1/0/1')
        self.assertEqual(iface.description, 'neat')
        self.assertEqual(iface.bundle, 'ae1')
        self.assertFalse(iface.vlantagging)
        self.assertEqual(iface.unitdict, [])
        self.assertEqual(iface.tunneldict, [])

    def test_with_units(self):
        data = {
            'name': 'xe-1/0/2',
            'description': 'Funkey',
            'vlan-tagging': [None],
            'unit': [
                {
                    'name': '1000',
                    'description': 'unit1',
                    'vlan-id': '1000',
                },
                {
                    'name': '1001',
                    'description': 'unit2',
                    'vlan-id': '1001',
                    'family': {
                        'inet': unit_addr('172.0.0.1/31'),
                        'inet6': unit_addr('2001:948:9:c2::2/127'),
                        'other-like-issi': unit_addr('nice-address')
                    }
                },
            ]
        }
        iface = junos.parse_interface(data)
        self.assertEqual(iface.name, 'xe-1/0/2')
        self.assertEqual(iface.description, 'Funkey')
        self.assertIsNone(iface.bundle)
        self.assertTrue(iface.vlantagging)

        unit1 = [u for u in iface.unitdict if u['unit'] == '1000'][0]
        self.assertEqual('1000', unit1['unit'])
        self.assertEqual('1000', unit1['vlanid'])
        self.assertEqual('unit1', unit1['description'])
        self.assertEqual(unit1['address'], [])

        unit2 = [u for u in iface.unitdict if u['unit'] == '1001'][0]
        self.assertEqual('1001', unit2['unit'])
        self.assertEqual('1001', unit2['vlanid'])
        self.assertEqual('unit2', unit2['description'])
        self.assertIn('172.0.0.1/31', unit2['address'])
        self.assertIn('2001:948:9:c2::2/127', unit2['address'])
        self.assertIn('nice-address', unit2['address'])
        self.assertEqual(len(unit2['address']), 3)
        self.assertEqual(len(iface.unitdict), 2)

    def test_tunnels(self):
        data = {
            'name': 'test1',
            'unit': [
                {
                    'name': 1,
                    'tunnel': {
                        'source': '172.16.0.1',
                        'destination': '172.18.0.2'
                    }
                }
            ]
        }

        iface = junos.parse_interface(data)
        self.assertEqual(iface.name, 'test1')
        self.assertIsNone(iface.description)
        self.assertEqual(iface.tunneldict, [{'source': '172.16.0.1', 'destination': '172.18.0.2'}])

    def test_empty(self):
        data = {}
        interfaces = junos.parse_interfaces(data)
        self.assertEqual(interfaces, [])
