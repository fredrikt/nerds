#!/bin/sh
#
# Merge output of other NERDS producers.
#

DIR=`dirname $0`

exec $DIR/merge_nerds.pl $*
