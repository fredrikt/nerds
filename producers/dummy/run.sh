#!/bin/bash

DIR=`dirname $0`
NAME=`echo $DIR | awk -F/ '{print $NF}'`
HOSTNAME=`hostname`

usage() {
   echo "Usage: $0"
   echo "  [-O <output dir>]"
   echo "  [--help  <show this info>]"
   exit 1
}

while test $# != 0
do
  case $1 in
      -O) REPO="$2" ; shift ;;
      --help|-h) usage ;; 
      --*) usage ;;
  esac
  shift
done

export JSONDIR="${REPO}/${NAME}/json"
mkdir -p $JSONDIR

cat<<EOJ>"${JSONDIR}/${HOSTNAME}..JSON"
{   
   "host": {
      "name": "$HOSTNAME",
      "version": 1,
      "${NAME}": { "about": "I am a dummy" }
   }
}
EOJ
