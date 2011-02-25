#!/bin/sh

dir=$(dirname $0)

exec $dir/alcatel_isis.py -C ndn.conf -O $dir/json/
