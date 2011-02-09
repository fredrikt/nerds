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
'''

import sys
import os
import json
import argparse

class Node:
    '''
    Class to contain the node name and its neighbours.
    '''
    def __init__(self, name):
        self.name = name
        self.neighbours = []

    def __unicode__(self):
        return self.name

    def __cmp__(self, other):
        if self.name > other.name:
            return 1
        elif self.name < other.name:
            return -1
        return 0

    def to_json(self):
        j = {'name': self.name, 'neighbours': []}
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

    def to_json(self):
        return {'name': self.name, 'metric': self.metric}


def normalize_whitespace(text):
    '''
    Remove redundant whitespace from a string.
    '''
    return ' '.join(text.split())

def process_isis_output(f):
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
        if line_list[0] not in not_interesting_lines:
            if line_list[0] == 'Metric:':
                metric = line_list[1]
                name = line_list[3]
                if metric != '0':
                    # Remove the last dot and everything after that
                    # in name
                    name = '.'.join(name.split('.')[:-1])
                node.neighbours.append(Neighbour(name, metric))
            elif line_list[0] == 'Hostname:':
                node.name = line_list[1]
            else:
                if node:
                    nodes.append(node)
                # Remove the last dot and everything after that in name
                name = '.'.join(line_list[0].split('.')[:-1])
                node = Node(name)
    return nodes

def main():
    # User friendly usage output
    parser = argparse.ArgumentParser()
    parser.add_argument('-F', nargs='?',
        help='Path to the Cisco IS-IS output file.')
    parser.add_argument('-O', nargs='?',
        help='Path to output directory.')
    parser.add_argument('-N', action='store_true',
        help='Don\'t write output to disk (JSON format).')
    parser.add_argument('-T', action='store_true',
        help='Don\'t write output to disk (text format).')
    args = parser.parse_args()

    # Load the input file
    if args.F == None:
        print 'Please provide an input file with -F.'
        sys.exit(1)
    else:
        try:
            f = open(args.F)
        except IOError as (errno, strerror):
            print "I/O error({0}): {1}".format(errno, strerror)

    # Collect the data from the input file
    nodes = process_isis_output(f)

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
                    f = open('%s%s' % (out_dir, hostn), 'w')
                except IOError:
                    # The directory to write in must exist
                    os.mkdir(out_dir)
                    f = open('%s%s' % (out_dir, hostn), 'w')
                f.write(json.dumps(host, sort_keys=True, indent=4))
                f.close()
        except IOError as (errno, strerror):
            print "I/O error({0}): {1}".format(errno, strerror)

    return 0

if __name__ == '__main__':
    main()
