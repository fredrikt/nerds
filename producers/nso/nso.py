#!/usr/bin/env python
# -*- coding: utf-8 -*-

# NSO producer
import logging
import argparse
import configparser
from api import Api
from utils import find, find_all
from parser import junos
import json

logger = logging.getLogger('nso')
logger.setLevel(logging.INFO)


def cli():
    parser = argparse.ArgumentParser()
    parser.add_argument('-C', help='Path to configuration file.')
    parser.add_argument('-O', '--out', help='Path to output directory.')

    args = parser.parse_args()
    config = configparser.ConfigParser()
    config.read(args.C)
    return config, args.out


def junos_router(device, device_data, api):
    router = junos.parse_router(device_data)
    ifdata = api.get('/devices/device/{}/config/configuration/interfaces?deep'.format(device))
    router.interfaces = junos.parse_interfaces(ifdata)
    bgpdata = api.get('/devices/device/{}/config/configuration/protocols/bgp?deep'.format(device))

    router.bgp_peerings = junos.parse_bgp_sessions(bgpdata)
    return router


def main():
    # with open('interfaces-dk-ore-deep.json') as f:
    #     iface_data = json.load(f)
    # interfaces = junos.parse_interfaces(iface_data)
    # print(json.dumps([i.to_json() for i in interfaces], indent=4))
    config, out_dir = cli()

    base_url = config['nso']['url']
    api_user = config['nso']['user']
    api_password = config['nso']['password']

    api = Api(base_url, api_user, api_password)
    # alternatly get /devices/device-groups?shallow
    devices_data = api.get('/devices')
    devices = find_all('name', find('tailf-ncs:devices.device', devices_data))
    for device in devices:
        # check if juniper
        device_data = api.get('/devices/device/' + device)
        if junos.is_junos(device_data):
            router = junos_router(device, device_data, api)
            print(json.dumps(router.to_json(), indent=4, sort_keys=True))
            break
        else:
            print('-', device)

    # Router, no model name
    # is junos check config{} junos:configuration, and device-type(netconf)
    # ... chassis rpc for hardware info.. maybe model name

    # Switches
    # is arista tailf-ned-arista-dcs:logging and device-type(cli)


if __name__ == '__main__':
    main()
