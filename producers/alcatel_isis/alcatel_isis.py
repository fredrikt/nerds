#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
#       alcatel_isis.py
#
#       Copyright 2011 Johan Lundberg <lundberg@nordu.net>
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#       MA 02110-1301, USA.

'''
Alcatel-Lucent DCN IS-IS producer written for the NERDS project
(http://github.com/fredrikt/nerds/).

Using the output from the "show isis database detail" on a Cisco router
connected to the Alcatel-Lucent DCN network, nodes and their neighbors
will be grouped.

To get a more human readable result use the IOS command "clns" to map
the NSAP address to a hostname. eg. clns host hostname NSAP_address.

You can also provide a mapping CSV file. The mandatory columns are
osi_address and name. All following columns will be added to the JSON
output.
'''

import sys
import os
import json
import argparse
import ConfigParser

class Node:
    '''
    Class to contain the node name and its neighbours.
    '''
    def __init__(self, name):
        self.name = name
        self.neighbours = []
        self.data = {}

    def __unicode__(self):
        return self.name

    def __cmp__(self, other):
        if self.name > other.name:
            return 1
        elif self.name < other.name:
            return -1
        return 0

    def to_json(self):
        if self.data:
            name = self.data['name']
        else:
            name = self.name
        j = {'name': name, 'neighbours': [], 'data': self.data}
        for neighbour in self.neighbours:
            j['neighbours'].append(neighbour.to_json())
        return j


class Neighbour:
    '''
    Class to contain a neighbor name and the metric.
    '''
    def __init__(self, name, metric):
        self.name = name
        self.metric = metric

    def __unicode__(self):
        return self.name

    def __cmp__(self, other):
        if self.name > other.name:
            return 1
        elif self.name < other.name:
            return -1
        # The neighbour name is equal but dont match them is the metric is
        # different
        if self.metric > other.metric:
            return 1
        elif self.metric < other.metric:
            return -1
        else:
            return 0

    def to_json(self):
        return {'name': self.name, 'metric': self.metric}


def normalize_whitespace(text):
    '''
    Remove redundant whitespace from a string.
    '''
    return ' '.join(text.split())

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

def lookup_osi(osi_system_id, nsap_mapping):
    '''
    Takes the system id part from the NSAP address and matches against
    a list of full NSAP addresses.
    The nsap_mapping dictionary looks like this:
    [{'osi_address': Full OSI address, 'name': Host name, 'x': y},]
    '''
    area_id = '47002300000001000100010001' # Alcatel area id
    selector_id = '1D' # Alcatel selector id
    full_iso_address = '%s%s%s' % (area_id, osi_system_id, selector_id)
    for item in nsap_mapping:
        if item['osi_address'] == full_iso_address.replace('.',''):
            return item
    return None

def merge_nodes(new_node, node_list):
    '''
    Takes the new node and matches it to an existing node in the node_list
    and merges them.
    '''
    for node in node_list:
        if node == new_node:
            for neighbour in new_node.neighbours:
                if neighbour not in node.neighbours:
                    node.neighbours.append(neighbour)

def get_remote_input(host, username, password):
    '''
    Tries to ssh to the supplied Cisco machine and execute the command
    'show isis database detail' to get the isis output.

    Returns False if the output could not be retrived.
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
        i = s.expect(login_choices)
        if i == 0:
            s.sendline('yes')
            i = s.expect(login_choices)
        if i == 1 or i == 2:
            s.sendline(password)
        elif i == 3:
            print "I either got key problems or connection timeout."
            return False
        s.expect('>', timeout=60)
        # Send command for displaying the output
        s.sendline('terminal length 0') # equal to 'no-more'
        s.expect('>')
        s.sendline ('show isis database detail')
        s.expect('>', timeout=120)
        output = s.before # take everything printed before last expect()
        s.sendline('exit')
    except pexpect.ExceptionPexpect:
        print 'Timed out in %s.' % host
        return False

    return output

def process_isis_output(f, nsap_mapping=None):
    '''
    Takes a file with output from the IOS command "show isis database
    detail".
    Returns a list of nodes.
    '''
    # Lines disregarded in the input file
    not_interesting_lines = ['IS-IS', 'LSPID', 'Area', 'NLPID:', 'IP']

    nodes = []
    node = None

    for line in f:
        line = normalize_whitespace(line)
        line_list = line.split()
        if line and line_list[0] not in not_interesting_lines:
            if line_list[0] == 'Metric:':
                metric = line_list[1]
                name = line_list[3]
                if node and metric != '0':
                    # Remove the last dot and everything after that
                    # in name
                    name = '.'.join(name.split('.')[:-1])
                    if nsap_mapping:
                        data = lookup_osi(name, nsap_mapping)
                        if data:
                            node.neighbours.append(Neighbour(
                                                data['name'], metric))
                    else:
                        node.neighbours.append(Neighbour(name, metric))
            elif line_list[0] == 'Hostname:':
                if node:
                    node.name = line_list[1]
            else:
                if node:
                    if nsap_mapping:
                        data = lookup_osi(name, nsap_mapping)
                        if data:
                            node.data.update(data)
                        data = None
                    if node in nodes:
                        merge_nodes(node, nodes)
                    else:
                        nodes.append(node)
                    node = None
                # Remove the last dot and everything after that in name
                name = '.'.join(line_list[0].split('.')[:-1])
                if name and not node:
                    node = Node(name)
    return nodes

def main():
    # User friendly usage output
    parser = argparse.ArgumentParser()
    parser.add_argument('-C', nargs='?',
        help='Configuration file.')
    parser.add_argument('-M', nargs='?',
        help='Path to optional OSI address <-> host name mapping file.')
    parser.add_argument('-O', nargs='?',
        help='Path to output directory.')
    parser.add_argument('-N', action='store_true',
        help='Don\'t write output to disk (JSON format).')
    parser.add_argument('-T', action='store_true',
        help='Don\'t write output to disk (text format).')
    args = parser.parse_args()

    # Load the configuration file
    if args.C == None:
        print 'Please provide a configuration file with -C.'
        sys.exit(1)
    else:
        config = init_config(args.C)

    # Load the optional mapping file
    nsap_mapping = []
    if args.M:
        try:
            m = open(args.M)
        except IOError as (errno, strerror):
            print 'When trying to open mapping file.'
            print "I/O error({0}): {1}".format(errno, strerror)

        key_list = normalize_whitespace(m.readline()).split(';')
        line = normalize_whitespace(m.readline())
        while line:
            value_list = line.split(';')
            tmp = {}
            for i in range(0, len(key_list)):
                tmp[key_list[i]] = value_list[i]
            nsap_mapping.append(tmp)
            line = normalize_whitespace(m.readline())

    # Node collection
    nodes = []

    # Process local files
    local_sources = config.get('sources', 'local').split()
    for f in local_sources:
        nodes.extend(process_isis_output(open(f), nsap_mapping))

    # Process remote hosts
    remote_sources = config.get('sources', 'remote').split()
    for host in remote_sources:
        remote_output = get_remote_input(host, config.get('ssh', 'user'),
                                                 config.get('ssh', 'password'))
        if remote_output:
            remote_output = remote_output.split('\n')
            nodes.extend(process_isis_output(remote_output, nsap_mapping))

    # Create the json output
    out = []
    for node in nodes:
        # Put the nodes json into the nerds format
        out.append({'host':
                    {'name': node.name,
                    'version': 1,
                    'alcatel_isis': node.to_json()
                    }})

    # Print or write the result to disk
    if args.T:
        nodes.sort()
        for node in nodes:
            if node.data:
                print 'Node: %s' % node.data['name']
                print 'OSI address: %s' % node.data['osi_address']
            else:
                print 'Node: %s' % node.name
            for neighbour in node.neighbours:
                print '\tNeighbour: %s, metric: %s' % (neighbour.name,
                                                    neighbour.metric)
    elif args.N:
        print json.dumps(out, sort_keys=True, indent=4)
    else:
        # Output directory should be ./json/ if nothing else is
        # specified
        out_dir = './json/'
        if args.O:
            out_dir = args.O
        # Pad with / if user provides a broken path
        if out_dir[-1] != '/':
            out_dir += '/'
        try:
            for host in out:
                hostn = host['host']['name']
                try:
                    f = open('%s%s.json' % (out_dir, hostn), 'w')
                except IOError as (errno, strerror):
                    print "I/O error({0}): {1}".format(errno, strerror)
                    # The directory to write in must exist
                    os.mkdir(out_dir)
                    f = open('%s%s.json' % (out_dir, hostn), 'w')
                f.write(json.dumps(host, sort_keys=True, indent=4))
                f.close()
        except IOError as (errno, strerror):
            print 'When trying to open output file.'
            print "I/O error({0}): {1}".format(errno, strerror)

    return 0

if __name__ == '__main__':
    main()
