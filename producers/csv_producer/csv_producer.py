#!/usr/bin/env python
# -*- coding: utf-8 -*-
#
#       csv_producer.py
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
CSV producer is written for the NERDS project.
(http://github.com/fredrikt/nerds/).

The script produces JSON output in the NERDS format from the provided CSV file.

The csv file needs to start with the name of the node and then the node type. 
After those two columns any other node property may follow.

Start your csv file with a line similar to the one below.
name;node_type;node_property1,node_property2;...;node_property15
'''
import sys
import os
import json
import argparse
import csv

def normalize_whitespace(text):
    '''
    Remove redundant whitespace from a string.
    '''
    text = text.replace('"', '').replace("'", '')
    return ' '.join(text.split())
    
def read_csv(f, delim=';', empty_keys=True):
    node_list = []
    key_list = normalize_whitespace(f.readline()).split(delim)
    line = normalize_whitespace(f.readline())
    while line:
        value_list = line.split(delim)
        tmp = {}
        for i in range(0, len(key_list)):
            key = normalize_whitespace(key_list[i].replace(' ','_').lower())
            value = normalize_whitespace(value_list[i])
            if value or empty_keys:
                tmp[key] = value
        node_list.append(tmp)
        line = normalize_whitespace(f.readline())
    return node_list

def main():
    # User friendly usage output
    parser = argparse.ArgumentParser()
    parser.add_argument('files', nargs='+', type=str,
                        help='Files to process.')
    parser.add_argument('-M', default='None', nargs='?',
            help='Node meta type. [Physical, Logical, Relation or Location]')
    parser.add_argument('-O', nargs='?',
                        help='Path to output directory.')
    parser.add_argument('-D', nargs='?', default=';',
                        help='Delimiter to use use. Default ";".')
    parser.add_argument('-NE', action='store_false', default=True,
                        help='No empty keys in the output.')
    parser.add_argument('-N', action='store_true',
                        help='Don\'t write output to disk (JSON format).')
    args = parser.parse_args()
    
    if args.M in ['Physical', 'Logical', 'Relation', 'Location']:
        meta_type = args.M
        nodes = []
        try:
            for f in args.files:
                nodes.extend(read_csv(open(f), args.D, args.NE))
        except IOError as (errno, strerror):
            print 'When trying to open csv file.'
            print "I/O error({0}): {1}".format(errno, strerror)
    else:
        print 'Node meta type %s is not supported.' % args.M.lower()
        print 'Please use Physical, Logical, Relation or Location.'
        sys.exit(1)
    # Create the json output
    out = []
    try:
        for node in nodes:
            # Put the nodes json into the nerds format
            node['meta_type'] = meta_type
            out.append({'host':
                        {'name': node['name'],
                        'version': 1,
                        'csv_producer': node
                        }})
    except KeyError as e:
        print 'Could not parse the csv file in a sensible way.'
        print 'Column %s is missing.' % e
        sys.exit(1)
    if args.N:
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