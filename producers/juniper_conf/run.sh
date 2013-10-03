#!/bin/sh

dir=$(dirname $0)

# You need to provide a path to a config file with -C like
# ./run.sh -C config.conf.
# A template config file should have been provided.
# Use ./run.sh -h for help.
exec $dir/juniper_conf.py $*
#exec /usr/local/sbin/ni-push.sh -r /var/nistore/
