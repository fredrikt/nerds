#!/usr/bin/env python

import argparse
import sys
import os
import json
import socket
import logging


logger = logging.getLogger('checkmk_livestatus')
logger.setLevel(logging.DEBUG)
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)

# checkmk_livestatus.py

# Producer for the NERDS project to be used with Nagios and checkmk_livestatus.
# (http://github.com/fredrikt/nerds/)
# (http://mathias-kettner.de/checkmk_livestatus.html)

# If you have Python <2.7 you need to install argparse manually.

VERBOSE = False

def checkmk_livestatus(socket_path="/var/nagios/var/rw/live"):
    columns = [
        'host_name', # Needed for NERDS formatting
        'host_address', # Needed for NERDS formatting
        'host_alias',
        'check_command',
        'description',
        'display_name',
        'last_check',
        'perf_data',
        'plugin_output'
    ]
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(socket_path)
    except socket.error as e:
        logger.error('Socket error: %s' % e)
        logger.error('Could not open socket: "%s". Exiting...' % socket_path)
        sys.exit(1)
    # Write command to socket
    # See http://mathias-kettner.de/checkmk_livestatus.html#H1:Using%20Livestatus for query format
    #s.send("GET hosts\n")
    #s.send("GET services\nFilter: description ~ check_uptime\nColumns: host_name plugin_output perf_data\nOutputFormat: python\nColumnHeaders: on\n")
    if VERBOSE:
        logger.info('Sending query...')
    s.send("GET services\nColumns:%s\nOutputFormat:json\nColumnHeaders:off\n" % ' '.join(columns))
    # Important: Close sending direction. That way
    # the other side knows, we are finished.
    s.shutdown(socket.SHUT_WR)
    # Now read the answer
    data = json.loads(s.recv(100000000))
    return columns, data

def nerds_format(columns, data):
    """
    Transform the checkmk_livestatus output to the NERDS format.
    """
    if VERBOSE:
        logger.info('Processing data...',)
    processing_dict = {}
    for item in data:
        z = dict(zip(columns, item))
        d = processing_dict.setdefault(z['host_name'],
            {
                'host':{
                    'name': z['host_name'],
                    'version': 1,
                    'checkmk_livestatus': {
                        'host_name': z['host_name'],
                        'host_alias': z['host_alias'],
                        'host_address': z['host_address'],
                        'checks': []
                    }
                }
            }
        )
        del z['host_name']
        del z['host_alias']
        del z['host_address']
        d['host']['checkmk_livestatus']['checks'].append(z)
    return processing_dict.values()

def write_output(nerds_list, not_to_disk=False, out_dir='./json/'):
    for item in nerds_list:
        out = json.dumps(item, sort_keys=True, indent=4)
        if not_to_disk:
            print out
        else:
            if out_dir[-1] != '/': # Pad with / if user provides a broken path
                out_dir += '/'
            try:
                try:
                    f = open('%s%s.json' % (out_dir, item['host']['name']), 'w')
                except IOError:
                    os.mkdir(out_dir) # The directory to write in must exist
                    f = open('%s%s.json' % (out_dir, item['host']['name']), 'w')
                if VERBOSE:
                    logger.info('Writing %s to disk.' % f.name)
                f.write(out)
                f.close()
            except IOError as (errno, strerror):
                logger.error("I/O error({0}): {1}".format(errno, strerror))

def main():
    # User friendly usage output
    parser = argparse.ArgumentParser()
    parser.add_argument('-o', default='./json/', nargs='?', help='Path to output directory.')
    parser.add_argument('-n', action='store_true',
        help='Don\'t write output to disk.')
    parser.add_argument('--verbose', '-v', action='store_true', default=False)
    args = parser.parse_args()
    if args.verbose:
        global VERBOSE
        VERBOSE = True
    columns, data = checkmk_livestatus()
    nerds_list = nerds_format(columns, data)
    write_output(nerds_list, args.N, args.O)

if __name__ == '__main__':
    main()