#!/usr/bin/env python

import argparse
import os
import json

'''
dummy_python.py

Dummy producer written in python for the NERDS project
(http://github.com/fredrikt/nerds/).

If you have Python <2.7 you need to install argparse manually.
'''

# User friendly usage output
parser = argparse.ArgumentParser()
parser.add_argument('-O', nargs='?', help='Path to output directory.')
parser.add_argument('-N', action='store_true',
    help='Don\'t write output to disk.')
args = parser.parse_args()

# Output directory should be ./json/ if nothing else is specified
out_dir = './json/'

# Should be the hostname on most OS
hostn = os.uname()[1]

dummy_template = {'host':{'name': hostn, 'version': 1, 'dummy_python': {}}}
dummy_data = {'bar': 'baz', 'foo':10, 'foobaz':{'bazbar':'foo'}}
dummy_template['host']['dummy_python'] = dummy_data

out = json.dumps(dummy_template, sort_keys=True, indent=4)

if args.N is True:
    print out
else:
    if args.O:
        out_dir = args.O
    if out_dir[-1] != '/': # Pad with / if user provides a broken path
        out_dir += '/'
    try:
        try:
            f = open('%s%s' % (out_dir, hostn), 'w')
        except IOError:
            os.mkdir(out_dir) # The directory to write in must exist
            f = open('%s%s' % (out_dir, hostn), 'w')
        f.write(out)
        f.close()
    except IOError as (errno, strerror):
        print "I/O error({0}): {1}".format(errno, strerror)
