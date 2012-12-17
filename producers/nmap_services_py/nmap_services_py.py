#!/usr/bin/env python2.7

import argparse
import os
import time
import json
import nmap

# nmap_services_py.py
#
# Rewrite of nmap_services producer in Python for the NERDS project
# (http://github.com/fredrikt/nerds/).
#
# Requires Python 2.7.

def scan(target, nmap_arguments, output_arguments):
    def callback_result(host, scan_result):
        d = nerds_format(host, scan_result)
        if d:

            output(d, output_arguments['out_dir'], output_arguments['no_write'])

    nma = nmap.PortScannerAsync()
    nma.scan(hosts=target, arguments=nmap_arguments, callback=callback_result)
    return nma

def nerds_format(host, data):
    """
    Transform the nmap output to the NERDS format.
    """
    if data['scan']:
        host_data = data['scan'][host]
        nerds_format = {
            'host':{
                'name': host_data['hostname'],
                'version': 1,
                'nmap_services_py': None
            }
        }
        nmap_services_py = {
            'addresses': [host],
            'hostnames':[host_data['hostname']],
            'os': {},
            'services':{
                host: {}
            }
        }
        if host_data.has_key('uptime'):
            nmap_services_py['uptime'] = host_data.uptime()
        if host_data.has_key('tcp'):
            nmap_services_py['services'][host]['tcp'] = host_data['tcp']
        if host_data.has_key('udp'):
            nmap_services_py['services'][host]['udp'] = host_data['udp']
        if host_data.has_key('ip'):
            nmap_services_py['services'][host]['ip'] = host_data['ip']
        if host_data.has_key('sctp'):
            nmap_services_py['services'][host]['sctp'] = host_data['sctp']
        if host_data.has_key('osclass'):
            nmap_services_py['os']['class'] = host_data['osclass'][0]
        if host_data.has_key('osmatch'):
            nmap_services_py['os']['match'] = host_data['osmatch'][0]
        nerds_format['host']['nmap_services_py'] = nmap_services_py
        return nerds_format
    else:
        return None

def merge_host(name):
    print 'Should have merged %s.' % name

def output(d, out_dir, no_write=False):
    out = json.dumps(d, sort_keys=True, indent=4)
    if no_write:
        print out
    else:
        if out_dir[-1] != '/': # Pad with / if user provides a broken path
            out_dir += '/'
        try:
            try:
                #TODO: check if file exists, if so combine results
                if os.path.exists('%s%s' % (out_dir, d['host']['name'])):
                    merge_host(d['host']['name'])
                f = open('%s%s' % (out_dir, d['host']['name']), 'w')
            except IOError:
                os.mkdir(out_dir) # The directory to write in must exist
                f = open('%s%s' % (out_dir, d['host']['name']), 'w')
            f.write(out)
            f.close()
        except IOError as (errno, strerror):
            print "I/O error({0}): {1}".format(errno, strerror)

def main():
    # User friendly usage output
    parser = argparse.ArgumentParser()
    parser.add_argument('-O', nargs='?', default='./json/', help='Path to output directory.')
    parser.add_argument('-N', action='store_true', default=False, help='Don\'t write output to disk.')
    parser.add_argument('--verbose', '-v', action='store_true', default=False)
    parser.add_argument(
        '--list',
        '-L',
        type=argparse.FileType('r'),
        help="File with addresses or networks."
    )
    parser.add_argument(
        'target',
        nargs='?',
        help="Target address or network to scan"
    )
    args = parser.parse_args()
    output_arguments = {
        'out_dir': args.O,
        'no_write': args.N
    }
    nmap_arguments = '-PE -sV -O --osscan-limit -F'
    scanners = []
    if args.target:
        scanners.append(scan(args.target, nmap_arguments, output_arguments))
    elif args.list:
        for target in args.list:
            target = target.strip()
            if target:
                scanners.append(scan(target, nmap_arguments, output_arguments))
    # Wait for the scanners to finish
    while scanners:
        if args.verbose:
            print("Scanning >>>")
            time.sleep(1)
        for scanner in scanners:
            if not scanner.still_scanning():
                scanners.remove(scanner)

if __name__ == '__main__':
    main()