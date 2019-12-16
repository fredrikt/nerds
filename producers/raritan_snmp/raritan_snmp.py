#!/usr/bin/env python
# -*- coding: utf-8 -*-

import logging
import argparse
from configparser import ConfigParser
from subprocess import check_output
import re
import sys
sys.path.append('../')

from nerds_utils.file import save_to_json
from nerds_utils import nerds as _nerds

logger = logging.getLogger('raritan_snmp')
logger.setLevel(logging.WARNING)
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)

SNMP_RARITAN_PORTS = 'SNMPv2-SMI::enterprises.13742.6.3.5.3.1.3.1'
RARITAN_PORTS_RE = re.compile('{}\.(?P<port>\d+) ?= ?STRING: ?"(?P<description>[^"]+)"'.format(SNMP_RARITAN_PORTS))
SIMPLE_IP = re.compile('[0-9]{1,3}(\.[0-9]{1,3}){3}|.*:.*')
HOST_RE = re.compile('name pointer (?P<host>.*).')


def parse_snmpwalk(output):
    if isinstance(output, bytes):
        output = output.decode('utf-8')

    ports = []
    for line in output.splitlines():
        match = RARITAN_PORTS_RE.search(line)
        if match:
            ports.append({
                'name': match.group('port'),
                'description': match.group('description')})
    return ports


def hostname(host):
    if SIMPLE_IP.search(host):
        output = check_output(['host', host])
        if isinstance(output, bytes):
            output = output.decode('utf-8')
        match = HOST_RE.search(output)

        if match:
            host = match.group('host')
        else:
            logger.error('IP %s does not have reverse dns', host)
            host = None
    return host


def snmpwalk(host):
    output = u''
    try:
        output = check_output(['snmpwalk', '-v2c', '-c', 'public', host, SNMP_RARITAN_PORTS])
    except Exception as e:
        logger.error('Unable to snmpwalk %s. Got error: %s', host, e)

    return parse_snmpwalk(output)


def to_nerds(host_name, ports):
    if ports:
        return _nerds.to_nerds(host_name, u'raritan', {u'ports': ports})
    else:
        return None


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('-C', help='Path to configuration file')
    parser.add_argument('-O', required=False, help='Path to output directory')
    parser.add_argument('-N', action='store_true', help='No output to disk')
    parser.add_argument('-V', action='store_true', help='Verbose logging')
    args = parser.parse_args()

    # Load configuration
    config = ConfigParser()
    config.read(args.C)

    out_dir = 'json'
    if args.O:
        out_dir = args.O
    if args.V:
        logger.setLevel(logging.INFO)

    return config, out_dir, args.N


def main():
    config, out_dir, dry_run = parse_args()

    if config.has_option('sources', 'local'):
        logger.info('Processing local sources.')
        local_sources = config.get('sources', 'local').split()
        for local in local_sources:
            logger.info('Processing %s', local)
            data = {}
            with open(local, 'r') as f:
                data = parse_snmpwalk(f.read())
            host_name = re.sub(r'.txt$', '', local)
            nerds = to_nerds(host_name, data)
            if dry_run:
                print(nerds)
            else:
                save_to_json(nerds, out_dir)

    if config.has_option('sources', 'remote'):
        logger.info('Processing remote sources.')
        remote_sources = config.get('sources', 'remote').split()
        for host in remote_sources:
            host_name = hostname(host)
            logger.info('Processing %s', host_name)
            ports = snmpwalk(host)
            nerds = to_nerds(host_name, ports)
            if dry_run:
                print(nerds)
            else:
                save_to_json(nerds, out_dir)


if __name__ == '__main__':
    main()
