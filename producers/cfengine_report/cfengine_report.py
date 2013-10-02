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

"""
cfengine_report is written for the NERDS project.
(http://github.com/fredrikt/nerds/).

The script produces JSON output in the NERDS format from the provided cfengine report CSV file.
"""

import sys
import os
import json
import argparse
from collections import defaultdict


def normalize_whitespace(text):
    """
    Remove redundant whitespace from a string.
    """
    text = text.replace('"', '').replace("'", '')
    return ' '.join(text.split())


def read_csv(f, delim=','):
    key_list = normalize_whitespace(f.readline()).split(delim)
    key_list[0] = 'name'  # Changing HostName to name.
    line = normalize_whitespace(f.readline())
    hosts = defaultdict(list)
    while line:
        value_list = line.split(delim)
        tmp = {}
        for i in range(1, len(key_list)):
            key = normalize_whitespace(key_list[i].replace(' ', '_').lower())
            value = normalize_whitespace(value_list[i])
            if value:
                tmp[key] = value
        hosts[value_list[0]].append(tmp)
        line = normalize_whitespace(f.readline())
    return hosts


def main():
    # User friendly usage output
    parser = argparse.ArgumentParser()
    parser.add_argument('files', nargs='+', type=argparse.FileType('r'), default=sys.stdin, help='Files to process.')
    parser.add_argument('-O', nargs='?',
                        help='Path to output directory.')
    parser.add_argument('-D', nargs='?', default=',',
                        help='Delimiter to use use. Default ",".')
    parser.add_argument('-N', action='store_true',
                        help='Don\'t write output to disk (JSON format).')
    args = parser.parse_args()

    csvs = []
    try:
        for f in args.files:
            csvs.append(read_csv(f, args.D))
    except IOError as (errno, strerror):
        print 'When trying to open csv file.'
        print "I/O error({0}): {1}".format(errno, strerror)
        sys.exit(1)

    # Create the json output
    out = []
    try:
        for csv in csvs:
            for host in csv.keys():
                # Put the nodes json into the nerds format
                out.append({
                    'host': {
                        'name': host,
                        'version': 1,
                        'cfengine_report': csv[host]
                    }
                })
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