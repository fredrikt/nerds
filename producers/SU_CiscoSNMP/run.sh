#!/bin/sh
#
# Try to find NRPE checks of remote hosts found having an NRPE service running.
#

DIR=`dirname $0`

exec $DIR/SU_CiscoSNMP.pl $*
