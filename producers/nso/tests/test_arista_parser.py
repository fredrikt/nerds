import unittest
from parser import arista


class AristaParserTest(unittest.TestCase):
    def test_parse_switch(self):
        data = {
            'tailf-ncs:device': {
                'name': 'some-switch',
                'address': 'some-switch.nordu.net',
                'config': {
                    'tailf-ned-arista-dcs:boot': {
                        'system': 'flash:/EOS-4.20.5F-INT.swi'
                    }
                }
            }
        }

        switch = arista.parse_switch(data)
        self.assertEqual(switch.name, 'some-switch.nordu.net')
        self.assertEqual(switch.version, 'EOS-4.20.5F-INT')

    def test_parse_switch_lo0(self):
        data = {
            'tailf-ncs:device': {
                'name': 'some-switch',
                'address': 'lo0.some-switch.nordu.net',
            }
        }

        switch = arista.parse_switch(data)
        self.assertEqual(switch.name, 'some-switch.nordu.net')

    def test_is_arista(self):
        data = {
            'tailf-ncs:device': {
                'config': {'tailf-ned-arista-dcs:boot': {}}
            }
        }

        self.assertTrue(arista.is_arista(data))

    def test_is_not_arista(self):
        data = {
            'tailf-ncs:device': {
                'config': {'junos:configuration': {}}
            }
        }

        self.assertFalse(arista.is_arista(data))


def wrap_interface(data):
    return {
        'tailf-ned-arista-dcs:interface': {
            'Ethernet': data
        }
    }


class AristaInterfaceParserTest(unittest.TestCase):
    def test_simple_interface(self):
        data = {
            'name': '1',
            'description': 'awsome description'
        }

        iface = arista.parse_interface(data)
        self.assertEqual(iface.name, 'et1')
        self.assertEqual(iface.description, 'awsome description')

    def test_no_description(self):
        data = {
            'name': '1',
        }

        iface = arista.parse_interface(data)
        self.assertEqual(iface.name, 'et1')
        self.assertIsNone(iface.description)

    def test_parse_interfaces(self):
        data = wrap_interface([
            {'name': '1', 'description': 'description1'},
            {'name': '52/1', 'description': 'description52/1'},
            {'name': '52/2', 'description': 'description52/2'},
        ])

        ifaces = arista.parse_interfaces(data)
        self.assertEqual(len(ifaces), 3)
        for i, name in enumerate(['1', '52/1', '52/2']):
            self.assertEqual(ifaces[i].name, 'et' + name)
            self.assertEqual(ifaces[i].description, 'description' + name)
