#!/bin/sh
#
# $Id$
# $HeadURL$
#
# Nmap scan, and then transform result to NERDS data.
#

DIR=`dirname $0`
NAME=`echo $DIR | awk -F/ '{print $NF}'`

if [ "x$NERDS_NMAP_OPTIONS" = "x" ]; then
    NERDS_NMAP_OPTIONS="-PE -sV --version-light -O --osscan-limit"
fi

usage() {
   echo "Usage: $0 [options] nmap-target ..."
   echo "  [-O <output dir>]"
   echo "  [--help  <show this info>]"
   exit 1
}

NMAP_TARGETS=""

while test $# != 0; do
    case $1 in
	-O) REPO="$2" ; shift ;;
	--help|-h) usage ;; 
	--*) usage ;;
	*)
	    NMAP_TARGETS="$NMAP_TARGETS $1"
	    ;;
    esac
    shift
done

if [ ! -d "$REPO" ]; then
    echo "Invalid output dir"
    echo ""
    usage
fi

export JSONDIR="${REPO}/${NAME}/json"
mkdir -p $JSONDIR

TMPFILE=$(mktemp /tmp/nerds_${NAME}.XXXXXX)
if [ ! -f $TMPFILE ]; then
    echo "$0: Failed creating temporary file"
fi

trap "rm $TMPFILE 2>/dev/null" 0

nmap $NERDS_NMAP_OPTIONS -oX $TMPFILE $NMAP_TARGETS

if [ $? -ne 0 ]; then
    echo ""
    echo "$0: nmap failed"
    exit 1
fi

$DIR/transform-nmap-scanresult.pl -O "$JSONDIR" $TMPFILE
