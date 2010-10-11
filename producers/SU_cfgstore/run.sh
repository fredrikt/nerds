#!/bin/sh
#
# Fetch data about hosts in cfgstore.
#

DIR=`dirname $0`
NAME="SU_cfgstore"

# Parse arguments to find the output directroy. We create
# it if it does not exist before executing the real worker script.
args=$*

while test $# != 0
do
  case $1 in
      -O|--output-dir) REPO="$2" ; shift ;;
  esac
  shift
done

if [ -d "$REPO" ]; then
    JSONDIR="${REPO}/producers/${NAME}/json"
    mkdir -p $JSONDIR
fi

exec $DIR/fetch_from_cfgstore.pl $args
