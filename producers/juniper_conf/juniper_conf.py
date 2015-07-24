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
import os
import sys
import json
import ConfigParser
import argparse
import logging
from models import *

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

def get_firstchild_data(element, tag):
    """
    Takes xml element and a name of a tag.
    Returns the data from a tag when looping over a parent.
    """
    try:
        data = element.getElementsByTagName(tag).item(0).firstChild.data
    except AttributeError:
        data = None
    return data

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

def get_version(xmldoc):
    """
    Take the output from "show configuration" and fetches JUNOS version.
    """
    version = xmldoc.getElementsByTagName('version')[0].firstChild.data
    return version

def get_model(xmldoc):
    """
    Take the output of "show chassis hardware" and fetches the router model.
    """
    model = xmldoc.getElementsByTagName('description')[0].firstChild.data
    return model

def get_interfaces(xmldoc, physical_interfaces=None):
    """
    Returns a list of Interface objects made out from all interfaces in
    the JunOS config.

    Dive in to Python writes:
    "When you parse an XML document, you get a bunch of Python objects
    that represent all the pieces of the XML document, and some of these
    Python objects represent attributes of the XML elements. But the
    (Python) objects that represent the (XML) attributes also have
    (Python) attributes, which are used to access various parts of the
    (XML) attribute that the object represents." ARGH ;)
    """
    interfaces_elements = xmldoc.getElementsByTagName('interfaces') # This will get _all_ interfaces elements...
    interface_elements = []
    interface_parents = ['configuration']
    for i in interfaces_elements:
        # We just want the interfaces element that is directly under configuration
        if i.parentNode.tagName in interface_parents:
            interface_elements.extend(list(i.getElementsByTagName('interface')))
    interfaces = []
    for interface in interface_elements:
        tempInterface = Interface()
        # Interface name, ge-0/1/0 or similar
        tempInterface.name = get_firstchild_data(interface, 'name')
        # If we have a list of physical interfaces in the router match against it
        if physical_interfaces and not tempInterface.name in physical_interfaces:
            logger.warn('Interface %s is configured but not found in %s.' % (tempInterface.name, get_hostname(xmldoc)))
            continue
        elif physical_interfaces:
            physical_interfaces.remove(tempInterface.name)
        # Is the interface vlan-tagging?
        vlantag = interface.getElementsByTagName('vlan-tagging').item(0)
        if vlantag:
            tempInterface.vlantagging = True
        else:
            tempInterface.vlantagging = False
        # Is it a bundled interface?
        tempInterface.bundle = get_firstchild_data(interface, 'bundle')
        # Get the interface description
        tempInterface.description = get_firstchild_data(interface, 'description')
        # Get tunnel information if any
        source = get_firstchild_data(interface, 'source')
        destination = get_firstchild_data(interface, 'destination')
        tempInterface.tunneldict.append({'source' : source,
            'destination': destination})
        # Get all information per interface unit
        units = interface.getElementsByTagName('unit')
        desctemp = ''
        vlanidtemp = ''
        nametemp = ''
        for unit in units:
            unittemp = get_firstchild_data(unit, 'name')
            desctemp = get_firstchild_data(unit, 'description')
            vlanidtemp = get_firstchild_data(unit, 'vlan-id')
            addresses = unit.getElementsByTagName('address')
            nametemp = []
            for address in addresses:
                nametemp.append(get_firstchild_data(address, 'name'))
            tempInterface.unitdict.append({'unit': unittemp,
                'description': desctemp, 'vlanid': vlanidtemp,
                'address': nametemp})
        # Add interface to the collection of interfaces
        interfaces.append(tempInterface)
    if physical_interfaces: # Physical interfaces that are not configured
        for interface in physical_interfaces:
            tempInterface = Interface()
            tempInterface.name = interface
            interfaces.append(tempInterface)
    return interfaces

def get_bgp_peerings(xmldoc):
    """
    Returns a list of all BGP peerings in the JunOS configuration.
    """
    bgp = xmldoc.getElementsByTagName('bgp')
    list_of_peerings = []
    for element in bgp:
        for group in element.getElementsByTagName('group'):
            group_name = get_firstchild_data(group, 'name')
            group_type = get_firstchild_data(group, 'type')
            local_address = get_firstchild_data(group, 'local-address')
            neighbors = group.getElementsByTagName('neighbor')
            for neighbor in neighbors:
                #if not neighbor.hasAttribute('inactive')
                peering = BgpPeering()
                peering.type = group_type
                peering.remote_address = get_firstchild_data(neighbor, 'name')
                peering.description = get_firstchild_data(neighbor, 'description')
                peering.local_address = local_address
                peering.group = group_name
                peering.as_number = get_firstchild_data(neighbor, 'peer-as')
                list_of_peerings.append(peering)
    return list_of_peerings

def parse_router(xmldoc, router_model=None, physical_interfaces=None):
    """
    Takes a JunOS conf in XML format and returns a Router object.
    """
    # Until we decide how we will handle logical-systems we remove them from
    # the configuration.
    logical_systems = xmldoc.getElementsByTagName('logical-systems')
    for item in logical_systems:
        item.parentNode.removeChild(item).unlink()
    router = Router()
    router.name = get_hostname(xmldoc)
    router.version = get_version(xmldoc)
    router.model = router_model
    router.interfaces = get_interfaces(xmldoc, physical_interfaces)
    router.bgp_peerings = get_bgp_peerings(xmldoc)
    return router

def get_physical_interfaces(xmldoc):
    """
    Takes the output of "show interfaces" and creates a list of interface names that
    are physically in the router.
    """
    physical_interfaces_elements = xmldoc.getElementsByTagName('physical-interface')
    physical_interface_names = []
    for i in physical_interfaces_elements:
        physical_interface_names.append(get_firstchild_data(i, 'name'))
    return physical_interface_names

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

def write_output(router, not_to_disk=False, out_dir='./json/'):

    # Call .tojson() for all Router objects and merge that with the
    # nerds template. Store the json in the dictionary out with the key
    # name.
    template = {'host':
                    {'name': router.name,
                     'version': 1,
                     'juniper_conf': {}
                    }
                }
    template['host']['juniper_conf'] = router.to_json()
    out = json.dumps(template, indent=4)
    # Depending on which arguments the user provided print to file or
    # to stdout.
    if not_to_disk:
        print out
    else:
        # Pad with / if user provides a broken path
        if out_dir[-1] != '/':
            out_dir += '/'
        try:
            try:
                f = open('%s%s.json' % (out_dir, router.name), 'w')
            except IOError:
                # The directory to write in must exist
                os.mkdir(out_dir)
                f = open('%s%s.json' % (out_dir, router.name), 'w')
            f.write(out)
            f.close()
        except IOError as (errno, strerror):
            logger.error("I/O error({0}): {1}".format(errno, strerror))

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
    # Process local files
    local_sources = config.get('sources', 'local').split()
    for f in local_sources:
        xmldoc = get_local_xml(f)
        if xmldoc:
            # Parse the xml document to create a Router object
            router = parse_router(xmldoc)
            write_output(router, not_to_disk, out_dir)
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
                router_model = get_model(hardware)
            else:
                router_model = None
            # Parse the xml document to create a Router object
            router = parse_router(configuration, router_model, physical_interfaces)
            # Write JSON
            write_output(router, not_to_disk, out_dir)
    return 0

if __name__ == '__main__':
    main()

