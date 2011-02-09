#!/bin/sh

dir=$(dirname $0)

exec $dir/alcatel_isis.py -O $dir/json/ -F $*
