#!/usr/bin/env python
# -*- coding: utf-8 -*-

# NSO producer
import logging
import argparse
import configparser
import ipaddress
from api import Api
from utils import find
from parser import junos, arista
import json
import sys
sys.path.append('../')
from nerds_utils import to_nerds, save_to_json  # noqa: E402

logger = logging.getLogger('nso')
logger.setLevel(logging.INFO)
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)


def junos_device_to_nerds(device, device_data, api):
    chassis_data = None
    try:
        chassis_data = api.post('/devices/device/{}/rpc/jrpc:rpc-get-chassis-inventory/_operations/get-chassis-inventory'.format(device))
    except Exception as e:
        logger.warning('Could not get chassis inventory for %s. Error: %s', device, e)

    router = junos.parse_router(device_data, chassis_data)
    ifdata = api.get('/devices/device/{}/config/configuration/interfaces?deep'.format(device))
    router.interfaces = junos.parse_interfaces(ifdata)

    bgpdata = api.get('/devices/device/{}/config/configuration/protocols/bgp?deep'.format(device))
    router.bgp_peerings = junos.parse_bgp_sessions(bgpdata)

    # logical systems
    logical_ifdata = api.get('/devices/device/{}/config/configuration/logical-systems?select=name;interfaces(*)'.format(device), collection=True)
    junos.parse_logical_interfaces(logical_ifdata, router.interfaces)


    if device not in router.name:
        logger.warning('%s ==> %s', device, router.name)
    return to_nerds(router.name, 'nso_juniper', router.to_json())


def arista_device_to_nerds(device, device_data, api):
    switch = arista.parse_switch(device_data)
    ifdata = api.get('/devices/device/{}/config/interface?deep'.format(device))
    switch.interfaces = arista.parse_interfaces(ifdata)

    return to_nerds(switch.name, 'nso_arista', switch.to_json())


def is_ipaddr(name):
    result = True
    try:
        ipaddress.ip_address(name)
    except ValueError:
        result = False
    return result


def out_nerds(nerds, out_dir, not_to_disk):
    if not_to_disk:
        print(json.dumps(nerds, indent=4, sort_keys=False))
    else:
        save_to_json(nerds, out_dir, sort_keys=False)


def process_devices(api, out_dir, not_to_disk, devices):
    for device in devices:
        # check if juniper
        logger.info('Processing: %s', device)
        device_data = api.get('/devices/device/' + device)
        out = None
        if junos.is_junos(device_data):
            out = junos_device_to_nerds(device, device_data, api)
        elif arista.is_arista(device_data):
            out = arista_device_to_nerds(device, device_data, api)

        if out:
            if is_ipaddr(out['host']['name']):
                logger.warning('Skipping - %s device name is an ip address (%s).', device, out['host']['name'])
                continue
            out_nerds(out, out_dir, not_to_disk)
        else:
            print('-', device)


def get_devices(section, device_groups):
    devices = set()
    if section.get('devices'):
        devices.update(section['devices'].split())
    if section.get('device_groups'):
        for g in section['device_groups'].split():
            devices.update(device_groups.get(g, []))
    return devices


def main(config, section, out_dir, not_to_disk):
    base_url = config['nso']['url']
    api_user = config['nso']['user']
    api_password = config['nso']['password']

    api = Api(base_url, api_user, api_password)
    device_groups = api.get('/devices/device-group?shallow', collection=True)
    device_groups = {dg['name']: dg['device-name'] for dg in find('collection.tailf-ncs:device-group', device_groups, default=[])}

    if config.has_section(section):
        devices = get_devices(config[section], device_groups)
        logger.debug('Processing %s: %s', section, devices)
        process_devices(api, out_dir, not_to_disk, devices)
    else:
        logger.error('Configuration does not have a %s section', section)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '-C',
        help='Path to configuration file.',
        required=True)
    parser.add_argument(
        '-O',
        '--out',
        help='Path to output directory.')
    parser.add_argument(
        '-N',
        action='store_true',
        help='Don\'t write output to disk.')
    parser.add_argument(
        '-S',
        '--section',
        default='routers',
        help='What configuration section to use')

    args = parser.parse_args()

    config = configparser.ConfigParser()
    config.read(args.C)
    out_dir = 'json'

    if args.out:
        out_dir = args.out
    main(config, args.section, out_dir, args.N)
