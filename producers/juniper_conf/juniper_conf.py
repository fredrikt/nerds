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
import ConfigParser
import argparse
import logging
from models import *
from parsers.base import ElementParser
from parsers import *
from util import JsonWriter

logger = logging.getLogger('juniper_conf')
logger.setLevel(logging.INFO)
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)

#JUNOS configuration producer written for the NERDS project
#(http://github.com/fredrikt/nerds/).
#
#Depends on pexpect for remote config gathering.
#If you have Python <2.7 you need to install argparse manually.


def get_hostname(xmldoc):
    """
    Finds and returns the hostname from a JunOS config.
    """
    re = xmldoc.getElementsByTagName('host-name')
    domain = xmldoc.getElementsByTagName('domain-name')
    if re:
        hostname = re[0].firstChild.data
    else:
        logger.error('Could not find host-name in the Juniper configuration.')
        sys.exit(1)
    if domain:
        hostname += '.%s' % domain[0].firstChild.data
    if 're0' in hostname or 're1' in hostname:
        hostname = hostname.replace('-re0','').replace('-re1','')
    return hostname

def parse_router(xmldoc, router_model=None, physical_interfaces=[]):
    """
    Takes a JunOS conf in XML format and returns a Router object.
    """
    routerConf = ElementParser(xmldoc)
    # Until we decide how we will handle logical-systems we remove them from
    # the configuration.
    logical_systems = xmldoc.getElementsByTagName('logical-systems')
    for item in logical_systems:
        item.parentNode.removeChild(item).unlink()
    router = Router()
    router.name = get_hostname(xmldoc)
    router.version = routerConf.first("version").text()
    router.model = router_model
    router.interfaces = InterfaceParser().parse(xmldoc, physical_interfaces)
    router.bgp_peerings = BgpPeeringParser().parse(xmldoc)
    return router

def get_physical_interfaces(xmldoc):
    """
    Takes the output of "show interfaces" and creates a list of interface names that
    are physically in the router.
    """
    return [ p.first("name").text() for p in ElementParser(xmldoc).all("physical-interfaces") ]

def init_config(path):
    """
    Initializes the configuration file located in the path provided.
    """
    try:
       config = ConfigParser.SafeConfigParser()
       config.read(path)
       return config
    except IOError as (errno, strerror):
        logger.error("I/O error({0}): {1}".format(errno, strerror))

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

def get_remote_xml(host, username, password, show_command):
    """
    Tries to ssh to the supplied JunOS machine and execute the command
    to show current configuration i XML format.

    Returns False if the configuration could not be retrieved.
    """
    try:
        import pexpect
    except ImportError:
        logger.error('Install pexpect to be able to use remote sources.')
        return False
    ssh_newkey = 'Are you sure you want to continue connecting'
    login_choices = [ssh_newkey, 'Password:', 'password:', pexpect.EOF]
    try:
        s = pexpect.spawn('ssh %s@%s' % (username,host))
        i = s.expect(login_choices)
        if i == 0:
            s.sendline('yes')
            i = s.expect(login_choices)
        if i == 1 or i == 2:
            s.sendline(password)
        elif i == 3:
            logger.error("[%s] I either got key problems or connection timeout." % host)
            return False
        s.expect('>', timeout=60)
        # Send JunOS command for displaying the configuration in XML
        # format.
        s.sendline(show_command)
        s.expect('</rpc-reply>', timeout=600)   # expect end of the XML
                                                # blob
        xml = s.before # take everything printed before last expect()
        s.sendline('exit')
    except pexpect.ExceptionPexpect as e:
        logger.error('Exception in %s.' % host)
        logger.error(str(e))
        return False
    xml += '</rpc-reply>' # Add the end element as pexpect steals it
    # Remove the first line in the output which is the command sent
    # to JunOS.
    xml = xml.lstrip('show configuration | display xml | no-more')
    try:
        xmldoc = minidom.parseString(xml)
    except minidom.ExpatError:
        logger.error('Malformed XML input from %s.' % host)
        return False
    return xmldoc

def main():
    # User friendly usage output
    parser = argparse.ArgumentParser()
    parser.add_argument('-C', nargs='?',
        help='Path to the configuration file.')
    parser.add_argument('-O', nargs='?',
        help='Path to output directory.')
    parser.add_argument('-N', action='store_true',
        help='Don\'t write output to disk.')
    args = parser.parse_args()
    # Load the configuration file
    if not args.C:
        logger.error('Please provide a configuration file with -C.')
        sys.exit(1)
    else:
        config = init_config(args.C)
    not_to_disk = False
    out_dir = './json/'
    if args.N:
        not_to_disk = True
    if args.O:
        out_dir = args.O
    jsonWriter = JsonWriter(not_to_disk, out_dir)
    # Process local files
    local_sources = config.get('sources', 'local').split()
    for f in local_sources:
        xmldoc = get_local_xml(f)
        if xmldoc:
            # Parse the xml document to create a Router object
            router = parse_router(xmldoc)
            jsonWriter.write(router)
    # Process remote hosts
    remote_sources = config.get('sources', 'remote').split()
    for host in remote_sources:
        show_command = 'show configuration | display xml | no-more'
        configuration = get_remote_xml(host, config.get('ssh', 'user'),
            config.get('ssh', 'password'), show_command)
        if configuration:
            show_command = 'show interfaces | display xml | no-more'
            interfaces = get_remote_xml(host, config.get('ssh', 'user'),
                config.get('ssh', 'password'), show_command)
            if interfaces:
                physical_interfaces = get_physical_interfaces(interfaces)
            else:
                physical_interfaces = None
            show_command = 'show chassis hardware | display xml | no-more'
            hardware = get_remote_xml(host, config.get('ssh', 'user'),
                config.get('ssh', 'password'), show_command)
            if hardware:
                chassis = ChassisParser().parse(hardware)
                router_model = chassis.description
            else:
                router_model = None
            # Parse the xml document to create a Router object
            router = parse_router(configuration, router_model, physical_interfaces)
            router.hardware = chassis
            # Write JSON
            jsonWriter(router)
    return 0

if __name__ == '__main__':
    main()

