#!/bin/sh

dir=$(dirname $0)

exec $dir/alcatel_isis.py -C template.conf $* 
