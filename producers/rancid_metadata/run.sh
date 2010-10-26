#!/bin/sh
#
# Fetch data about switches/routers in Rancid.
#

DIR=`dirname $0`
NAME="rancid_metadata"

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

exec $DIR/fetch_from_rancid.pl $args
