from models import Interface, BgpPeering, Router
from utils import find, find_first, find_all


def parse_interface(item):
    iface = Interface()
    iface.name = item['name']
    iface.description = item.get('description')
    iface.vlantagging = 'vlan-tagging' in item or 'flexible-vlan-tagging' in item
    iface.unitdict = [parse_unit(u) for u in item.get('unit', [])]
    iface.bundle = find_first('bundle', item) or None
    iface.tunneldict = [
        {
            'source': find('tunnel.source', u),
            'destination': find('tunnel.destination', u)
        } for u in item.get('unit', []) if 'tunnel' in u
    ]
    return iface


def parse_unit(item):
    return {
        'unit': item['name'],
        'description': item.get('description'),
        'vlanid': item.get('vlan-id'),
        'address': find_all('name', find_all('address', item)),
    }


def parse_interfaces(data):
    return [parse_interface(item) for item in find('junos:interfaces.interface', data)]


def parse_bgp_sessions(data):
    peerings = []

    for group in find('junos:bgp.group', data):
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


def parse_router(data):
    router_data = data['tailf-ncs:device']

    router = Router()
    name = router_data['address'].replace('lo0.', '')
    router.name = name
    router.version = find('config.junos:configuration.version', router_data)
    # model missing
    return router
