#!/bin/sh

dir=$(dirname $0)

exec $dir/dummy_python.py -O $*
