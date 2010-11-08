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

'''
Depends on pexpect for remote config gathering.
If you have Python <2.7 you need to install argparse manually.
'''

class Router:
    def __init__(self):
        self.name = ''
        self.interfaces = []

    def to_json(self):
        j = {'name':self.name}
        interfaces = []
        for interface in self.interfaces:
            interfaces.append(interface.to_json())
        j['interfaces'] = interfaces
        return j

class Interface:
    def __init__(self):
        self.name = ''
        self.bundle = ''
        self.desc = ''
        self.vlantagging = ''
        self.tunneldict = []
        # Unit dict is a list of dictionaries containing units to
        # interfaces, should be index like {'unit': 'name',
        # 'desc': 'foo', 'vlanid': 'bar', 'address': 'xyz'}
        self.unitdict = []

    def to_json(self):
        j = {'name':self.name, 'bundle':self.bundle, 'desc':self.desc,
            'vlantagging':self.vlantagging, 'tunnels':self.tunneldict,
            'units':self.unitdict}
        return j

def get_firstchild(element, arg):
    '''
    Helper function, takes xmlelement and a string.
    Returns a string.
    '''
    data = element.getElementsByTagName(arg).item(0).firstChild.data
    return data

def get_hostname(xmldoc):
    '''
    Finds and returns the hostname from a JunOS config.
    '''
    re = xmldoc.getElementsByTagName('host-name')
    try:
        hostname = re[0].firstChild.data
    except AttributeError:
        print 'No host-name element in config file, check the config.'
        sys.exit(1)

    if 're0' in hostname or 're1' in hostname:
        hostname = hostname.replace('-re0','').replace('-re1','')

    return hostname

def get_interfaces(xmldoc):
    '''
    Returns a list of Interface objects made out from all "interesting"
    interfaces in the JunOS config.

    Maybe this should be all interfaces and let a consumer care about
    interesting.

    Dive in to Python writes:
    "When you parse an XML document, you get a bunch of Python objects
    that represent all the pieces of the XML document, and some of these
    Python objects represent attributes of the XML elements. But the
    (Python) objects that represent the (XML) attributes also have
    (Python) attributes, which are used to access various parts of the
    (XML) attribute that the object represents." ARGH ;)
    '''

    interfaces = xmldoc.getElementsByTagName('interfaces')
    listofinterfaces = []

    for item in interfaces:
        try:
            interface = list(xmldoc.getElementsByTagName('interface'))
        except AttributeError:
            pass

    for elements in interface:
        tempInterface = Interface()
        try:
            tempInterface.name = get_firstchild(elements, 'name')
        except AttributeError:
            pass
        try:
            vlantag = elements.getElementsByTagName(
                'vlan-tagging').item(0)
            if vlantag != None:
                tempInterface.vlantagging = True
            else:
                tempInterface.vlantagging = False
        except AttributeError:
            pass
        try:
            tempInterface.bundle = get_firstchild(elements, 'bundle')
        except AttributeError:
            pass
        try:
            tempInterface.desc = get_firstchild(elements, 'description')
        except AttributeError:
            tempInterface.desc = 'No description set, fix me!'
        try:
            source = get_firstchild(elements, 'source')
            destination = get_firstchild(elements, 'destination')
            tempInterface.tunneldict.append({'source' : source,
                'destination': destination})
        except AttributeError:
            pass

        units = elements.getElementsByTagName('unit')
        unitemp = ''
        desctemp = ''
        vlanidtemp = ''
        nametemp = ''
        for unit in units:
            unittemp = get_firstchild(unit, 'name')
            try:
                desctemp = get_firstchild(unit, 'description')
            except AttributeError:
                pass
            try:
                vlanidtemp = get_firstchild(unit, 'vlan-id')
            except AttributeError:
                pass
            addresses = unit.getElementsByTagName('address')
            nametemp = []
            for address in addresses:
                nametemp.append(get_firstchild(address, 'name'))

            tempInterface.unitdict.append({'unit': unittemp, 'name': desctemp, 'vlanid': vlanidtemp, 'address': nametemp})
        listofinterfaces.append(tempInterface)

    return listofinterfaces

def parse_router(xmldoc):
    '''
    Takes a JunOS conf in XML format and returns a Router object.
    '''
    router = Router()
    router.name = get_hostname(xmldoc)
    router.interfaces = get_interfaces(xmldoc)

    return router

def init_config(path):
    '''
    Initializes the configuration file located in the path provided.
    '''
    try:
       config = ConfigParser.SafeConfigParser()
       config.read(path)
       return config
    except IOError as (errno, strerror):
        print "I/O error({0}): {1}".format(errno, strerror)

def get_local_xml(f):
    '''
    Parses the provided file to an XML document and returns it.

    Returns False if the XML is malformed.
    '''
    try:
        xmldoc = minidom.parse(f)
    except ExpatError:
        print 'Malformed XML input from %s.' % host
        return False

    return xmldoc

def get_remote_xml(host, username, password):
    '''
    Tries to ssh to the supplied JunOS machine and execute the command
    to show current configuration i XML format.

    Returns False if the configuration could not be retrived.
    '''
    try:
        import pexpect
    except ImportError:
        print 'Install module pexpect to be able to use remote sources.'
        return False

    ssh_newkey = 'Are you sure you want to continue connecting'
    login_choices = [ssh_newkey, 'Password:', 'password:', pexpect.EOF]

    try:
        s = pexpect.spawn('ssh %s@%s' % (username,host))
        print 'Trying to connect to %s@%s...' % (username, host)
        i = s.expect(login_choices)
        if i == 0:
            print "Storing SSH key."
            s.sendline('yes')
            i = s.expect(login_choices)
        if i == 1 or i == 2:
            s.sendline(password)
            print 'Connected to %s.' % host
        elif i == 3:
            print "I either got key problems or connection timeout."
            return False
        s.expect('>', timeout=60)
        # Send JunOS command for displaying the configuration in XML
        # format.
        s.sendline ('show configuration | display xml | no-more')
        s.expect('</rpc-reply>', timeout=120)   # expect end of the XML
                                                # blob
        xml = s.before # take everything printed before last expect()
        s.sendline('exit')
    except pexpect.ExceptionPexpect:
        print 'Timed out in %s.' % host
        return False

    xml += '</rpc-reply>' # Add the end element as pexpect steals it
    # Remove the first line in the output which is the command sent
    # to JunOS.
    xml = xml.lstrip('show configuration | display xml | no-more')
    try:
        xmldoc = minidom.parseString(xml)
    except ExpatError:
        print 'Malformed XML input from %s.' % host
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
    if args.C == None:
        print 'Please provide a configuration file with -C.'
        sys.exit(1)
    else:
        config = init_config(args.C)

    # List to collect configuration in XML document format for parsing
    xmldocs = []

    # Process local files
    local_sources = config.get('sources', 'local').split()
    for f in local_sources:
        xmldoc = get_local_xml(f)
        if xmldoc:
            xmldocs.append(xmldoc)

    # Process remote hosts
    remote_sources = config.get('sources', 'remote').split()
    for host in remote_sources:
        xmldoc = get_remote_xml(host, config.get('ssh', 'user'),
            config.get('ssh', 'password'))
        if xmldoc:
            xmldocs.append(xmldoc)

    # Parse the xml documents to create Router objects
    parsed_conf_xml = []
    for doc in xmldocs:
        parsed_conf_xml.append(parse_router(doc))

    # Call .tojson() for all Router objects and merge that with the
    # nerds template. Store the json in the dictionary out with the key
    # name.
    out = {}
    for c in parsed_conf_xml:
        template = {'host':{'name': c.name, 'version': 1,
            'juniper_conf': {}}}
        template['host']['juniper_conf'] = c.to_json()
        out[c.name] = json.dumps(template, indent=4)

    # Output directory should be ./json/ if nothing else is specified
    out_dir = './json/'

    # Depending on which arguments the user provided print to file or
    # to stdout.
    if args.N is True:
        for key in out:
            print out[key]
    else:
        if args.O:
            out_dir = args.O
        # Pad with / if user provides a broken path
        if out_dir[-1] != '/':
            out_dir += '/'
        for key in out:
            try:
                try:
                    f = open('%s%s.json' % (out_dir, key), 'w')
                except IOError:
                    # The directory to write in must exist
                    os.mkdir(out_dir)
                    f = open('%s%s.json' % (out_dir, key), 'w')
                f.write(out[key])
                f.close()
            except IOError as (errno, strerror):
                print "I/O error({0}): {1}".format(errno, strerror)

    return 0

if __name__ == '__main__':
    main()

