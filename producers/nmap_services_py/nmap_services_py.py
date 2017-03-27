#!/usr/bin/env python2.7

import argparse
import os
import json
import nmap
import logging
import time
import gc

logger = logging.getLogger('nmap_services_py')
logger.setLevel(logging.INFO)
ch = logging.StreamHandler()
ch.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
logger.addHandler(ch)

# nmap_services_py.py
#
# Rewrite of nmap_services producer in Python for the NERDS project
# (http://github.com/fredrikt/nerds/).
#
# Requires Python 2.7.

VERBOSE = False


def scan(target, nmap_arguments, ports, output_arguments):
    def callback_result(host, scan_result):
        if VERBOSE:
            logger.info('Finished scanning %s.' % host)
        d = nerds_format(host, scan_result)
        if d:
            output(d, output_arguments['out_dir'], output_arguments['no_write'])

    nma = nmap.PortScannerAsync()
    nma.scan(hosts=target, ports=ports, arguments=nmap_arguments, callback=callback_result)
    return nma


def nerds_format(host, data):
    """
    Transform the nmap output to the NERDS format.
    """
    if data['scan']:
        host_data = data['scan'][host]
        nerds_format = {
            'host': {
                'name': host_data['hostname'],
                'version': 1,
                'nmap_services_py': None
            }
        }
        nmap_services_py = {
            'addresses': [host],
            'hostnames': [host_data['hostname']],
            'os': {},
            'services': {
                host: {}
            }
        }
        # name
        if not nerds_format['host']['name']:
            if 'osmatch' in host_data:
                os_match = host_data['osmatch'][0].get('name', 'Unknown')
            else:
                os_match = 'Unknown'
            logger.warn('Host %s not in DNS. OS match: %s' % (host, os_match))
            return None
        # uptime
        if 'uptime' in host_data:
            nmap_services_py['uptime'] = host_data.uptime()
        # services
        if 'tcp' in host_data:
            nmap_services_py['services'][host]['tcp'] = host_data['tcp']
        if 'udp' in host_data:
            nmap_services_py['services'][host]['udp'] = host_data['udp']
        if 'ip' in host_data:
            nmap_services_py['services'][host]['ip'] = host_data['ip']
        if 'sctp' in host_data:
            nmap_services_py['services'][host]['sctp'] = host_data['sctp']
        # os
        if 'osclass' in host_data:
            nmap_services_py['os']['class'] = host_data['osclass'][0]
        if 'osmatch' in host_data:
            nmap_services_py['os']['match'] = host_data['osmatch'][0]
        nerds_format['host']['nmap_services_py'] = nmap_services_py
        if VERBOSE:
            logger.info('Finished processing %s (%s).' % (nerds_format['host']['name'], host))
        return nerds_format
    else:
        return None


def merge_nmap_services(d1, d2):
    """
    Combines two dictionaries of nerds format.
    """
    new = d1['host']['nmap_services_py']
    old = d2['host']['nmap_services_py']
    new_address = new['addresses'][0]
    old['hostnames'].extend(new['hostnames'])
    old['hostnames'] = list(set(old['hostnames']))
    old['addresses'].append(new_address)
    old['addresses'] = list(set(old['addresses']))
    old['services'][new_address] = new['services'][new_address]
    # Ignoring os and uptime as they should not diff.
    if VERBOSE:
        logger.info('Host %s merged in to %s.' % (new_address, d2['host']['name']))
    d2['host']['nmap_services_py'] = old
    return d2


def output(d, out_dir, no_write=False):
    if no_write:
        print json.dumps(d, sort_keys=True, indent=4)
    else:
        if out_dir[-1] != '/':  # Pad with / if user provides a broken path
            out_dir += '/'
        try:
            try:
                #TODO: check if the merge will collide with writing host files...
                if os.path.exists('%s%s.json' % (out_dir, d['host']['name'])):
                    f = open('%s%s.json' % (out_dir, d['host']['name']))
                    try:
                        d = merge_nmap_services(d, json.load(f))
                    except ValueError:
                        # Previous file was damaged on some way, ignore it.
                        pass
                    f.close()
                f = open('%s%s.json' % (out_dir, d['host']['name']), 'w')
            except IOError:
                os.mkdir(out_dir)  # The directory to write in might not exist
                f = open('%s%s.json' % (out_dir, d['host']['name']), 'w')
            f.write(json.dumps(d, sort_keys=True, indent=4))
            f.close()
            if VERBOSE:
                logger.info('%s written.' % f.name)
        except IOError as (errno, strerror):
            print "I/O error({0}): {1}".format(errno, strerror)


def main():
    # User friendly usage output
    parser = argparse.ArgumentParser()
    parser.add_argument('-O', nargs='?', default='./json/', help='Path to output directory.')
    parser.add_argument('-N', action='store_true', default=False, help='Don\'t write output to disk.')
    parser.add_argument('--verbose', '-v', action='store_true', default=False)
    parser.add_argument('--known', '-k', action='store_true', default=False,
                        help='Takes a list of known hosts with specified ports.')
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
    if args.verbose:
        global VERBOSE
        VERBOSE = True
    output_arguments = {
        'out_dir': args.O,
        'no_write': args.N
    }
    nmap_arguments = '-PE -sV -O --osscan-guess'
    scanners = []
    if args.target:
        ports = None
        scanners.append(scan(args.target, nmap_arguments, ports, output_arguments))
    elif args.list:
        for target in args.list:
            if not args.known:
                ports = None
                target = target.strip()
            else:
                try:
                    # Line should match "address U:X,X,T:X-X,X"
                    # http://nmap.org/book/man-port-specification.html
                    target, ports = target.strip().split()
                    nmap_arguments = '-PE -sV -sS -sU -O --osscan-guess'
                except ValueError:
                    logger.error('Could not make sense of "%s".' % target)
                    logger.info('Line should match "address U:X,X,T:X-X,X"')
                    logger.info('http://nmap.org/book/man-port-specification.html')
                    continue
            if target and not target.startswith('#'):
                scanners.append(scan(target, nmap_arguments, ports, output_arguments))
                time.sleep(20)  # Wait 20 seconds for a scanner to start
    gc.collect()
    # Wait for the scanners to finish
    while scanners:
        time.sleep(60)  # Check if scanners are done every minute
        for scanner in scanners:
            if not scanner.still_scanning():
                scanners.remove(scanner)
                logger.info('%d scanners still scanning.' % len(scanners))
            time.sleep(5)  # Check a scanner every 5 seconds
        gc.collect()


if __name__ == '__main__':
    main()
