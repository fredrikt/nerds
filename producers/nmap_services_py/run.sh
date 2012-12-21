#!/bin/sh

dir=$(dirname $0)

exec $dir/nmap_services_py.py -O $*
