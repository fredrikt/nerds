#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
# Copyright 2010, NORDUnet A/S.
#
# This file is part of the NERDS producer juniper_conf.py.
#
# NORDUbot is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# NORDUbot is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with NERDS. If not, see <http://www.gnu.org/licenses/>.

from xml.dom import minidom
import sys
from configparser import ConfigParser
import argparse
import logging
from parsers import ElementParser, RouterPaser, ChassisParser
from util import JsonWriter, JunosRemoteSource

logger = logging.getLogger('juniper_conf')
logger.setLevel(logging.INFO)
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)

# JUNOS configuration producer written for the NERDS project
# (http://github.com/fredrikt/nerds/).
#
# Depends on pexpect for remote config gathering.
# If you have Python <2.7 you need to install argparse manually.


def get_physical_interfaces(xmldoc):
    """
    Takes the output of "show interfaces" and creates a list of interface names that
    are physically in the router.
    """
    return [p.first("name").text() for p in ElementParser(xmldoc).all("physical-interfaces")]


def init_config(path):
    """
    Initializes the configuration file located in the path provided.
    """
    try:
        config = ConfigParser()
        config.read(path)
        return config
    except IOError as e:
        logger.error("I/O error: %s", e)
        raise


def get_local_xml(f):
    """
    Parses the provided file to an XML document and returns it.

    Returns False if the XML is malformed.
    """
    try:
        xmldoc = minidom.parse(f)
    except Exception as e:
        logger.error(str(e))
        logger.error('Malformed XML input from %s.' % f)
        return False
    return xmldoc


def parse_args():
    # User friendly usage output
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '-C',
        nargs='?',
        help='Path to the configuration file.')
    parser.add_argument(
        '-O',
        nargs='?',
        help='Path to output directory.')
    parser.add_argument(
        '-N',
        action='store_true',
        help='Don\'t write output to disk.')
    args = parser.parse_args()
    # Load the configuration file
    if not args.C:
        logger.error('Please provide a configuration file with -C.')
        sys.exit(1)
    else:
        config = init_config(args.C)
    not_to_disk = False
    out_dir = 'json/'
    if args.N:
        not_to_disk = True
    if args.O:
        out_dir = args.O

    return config, not_to_disk, out_dir


def scan_remote_host(host, username, password):
    """
    Fetch and parse configuration from a single remote Junos host.
    Returns a Router object, or None if the configuration could not be fetched.
    """
    remote = JunosRemoteSource(host, username, password)
    version_data = remote.show_version()
    configuration = remote.show_configuration()
    if not configuration:
        return None
    interfaces = remote.show_interfaces()
    physical_interfaces = get_physical_interfaces(interfaces) if interfaces else []
    router = RouterPaser().parse(configuration, version_data, physical_interfaces)
    hardware = remote.show_hardware()
    if hardware:
        chassis = ChassisParser().parse(hardware)
        if chassis:
            router.hardware = chassis
    return router


def main():
    config, not_to_disk, out_dir = parse_args()
    jsonWriter = JsonWriter(not_to_disk, out_dir)
    # Process local files
    local_sources = config.get('sources', 'local').split()
    for f in local_sources:
        xmldoc = get_local_xml(f)
        if xmldoc:
            # Parse the xml document to create a Router object
            router = RouterPaser().parse(xmldoc)
            jsonWriter.write(router)
    # Process remote hosts
    remote_sources = config.get('sources', 'remote').split()
    for host in remote_sources:
        router = scan_remote_host(host, config.get('ssh', 'user'), config.get('ssh', 'password'))
        if router:
            jsonWriter.write(router)
    return 0


if __name__ == '__main__':
    main()
