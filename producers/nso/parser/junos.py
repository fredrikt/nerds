from models import Interface, BgpPeering, Router
from utils import find, find_first, find_all, hostname_clean


def parse_interface(item, logical_system=None):
    iface = Interface()
    iface.name = item['name']
    iface.description = item.get('description')
    iface.vlantagging = 'vlan-tagging' in item or 'flexible-vlan-tagging' in item
    iface.unitdict = [parse_unit(u, logical_system) for u in item.get('unit', [])]
    iface.bundle = find_first('bundle', item) or None
    iface.tunneldict = [
        {
            'source': find('tunnel.source', u),
            'destination': find('tunnel.destination', u)
        } for u in item.get('unit', []) if 'tunnel' in u
    ]
    return iface


def parse_unit(item, logical_system=None):
    unit = {
        'unit': item['name'],
        'description': item.get('description'),
        'vlanid': item.get('vlan-id'),
        'address': find_all('name', find_all('address', item)),
    }
    if logical_system:
        unit['logical_system'] = logical_system
    return unit


def parse_interfaces(data):
    return [parse_interface(item) for item in find('junos:interfaces.interface', data, default=[])]

def parse_logical_interfaces(data, interfaces):
    # make interface map for quick lookups
    if_map = { i.name: i for i in interfaces }
    for ls in find('collection.junos:logical-systems', data, default=[]):
        for i in find('interfaces.interface', ls, default=[]):
            iface = parse_interface(i, logical_system=ls['name'])
            if iface.name in if_map:
                if_map[iface.name].unitdict += iface.unitdict
            else:
                interfaces.append(iface)
    return interfaces

def parse_bgp_sessions(data):
    peerings = []

    for group in find('junos:bgp.group', data, default=[]):
        # inactive groups not shown it seems
        groupName = group['name']
        groupType = group.get('type')
        localAddress = group.get('local-address')

        for neighbor in group.get('neighbor', []):
            # still no inactive
            peering = BgpPeering()
            peering.type = groupType
            peering.group = groupName
            peering.remote_address = neighbor.get('name')
            peering.description = neighbor.get('description')
            peering.local_address = localAddress
            peering.as_number = neighbor.get('peer-as')
            peerings.append(peering)
    return peerings


def is_junos(data):
    return find('tailf-ncs:device.config.junos:configuration', data) is not None


def parse_chassis(data):
    chassis = {}
    sub_modules = []
    for key, val in data.items():
        # Submodules all end in -module / contains
        if '-module' in key:
            sub_modules += [parse_chassis(mod) for mod in val]
        else:
            chassis[key] = val
    if sub_modules:
        chassis['sub-modules'] = sub_modules
    return chassis

def parse_router(data, chassis_data=None):
    router_data = data['tailf-ncs:device']

    router = Router()
    name = hostname_clean(router_data['address'])
    router.name = name
    router.version = find('config.junos:configuration.version', router_data)
    if chassis_data:
        chassis = find('junos-rpc:output.chassis-inventory.chassis', chassis_data, default={})
        if chassis:
            router.model = chassis['description']
        router.hardware = parse_chassis(chassis)
    return router
