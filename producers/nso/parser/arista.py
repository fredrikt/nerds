from models import Switch, Interface
from utils import find, hostname_clean


def eos_version(data):
    return data.replace('flash:/', '').replace('.swi', '')


def parse_interface(data):
    iface = Interface()
    iface.name = 'et{}'.format(data['name'])
    iface.description = data.get('description')

    return iface


def parse_interfaces(data):
    ifaces = find('tailf-ned-arista-dcs:interface.Ethernet', data, default=[])
    return [parse_interface(d) for d in ifaces]


def parse_switch(data):
    switch_data = data['tailf-ncs:device']

    switch = Switch()
    switch.name = hostname_clean(switch_data['address'])
    switch.version = eos_version(find('config.tailf-ned-arista-dcs:boot.system', switch_data, default=''))
    return switch


def is_arista(data):
    return find('tailf-ncs:device.config.tailf-ned-arista-dcs:boot', data) is not None
