#!/bin/bash
tmpfile=$(mktemp /tmp/nerds-nmap-docker.XXXXXX)
echo "109.105.110.116 T:443,80,U:123" >> $tmpfile
echo "109.105.111.42 T:443,80,22" >> $tmpfile

docker run --rm -ti -v $tmpfile:/app/knownhosts.txt:ro nerds-nmap-producer -N -k -L /app/knownhosts.txt

rm $tmpfile
