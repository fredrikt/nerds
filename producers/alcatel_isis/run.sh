#!/bin/sh

dir=$(dirname $0)

$dir/alcatel_isis.py -C ndn.conf -M NE_Address_list_NORDUnet.csv $*
