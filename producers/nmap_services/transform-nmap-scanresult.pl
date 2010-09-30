#!/usr/bin/env perl
#
# $Id$
# $HeadURL$
#
# Read one or more Nmap XML output files and produce NERDS data files
# for all hosts scanned. 
#
# We only pick out data that is 'stable', meaning
# that a subsequent run of the scan is at least very likely to produce
# the same NERDS data files.
#
# For now, the MAC address information is not brought along because
# the availability of the MAC address depends on from what host the
# scan is performed.
#

use strict;
use Getopt::Long;
use Nmap::Parser;
use Data::Dumper;
use JSON;

my $debug = 0;
my $o_help = 0;
my $output_dir;

Getopt::Long::Configure ("bundling");
GetOptions(
    'd'		=> \$debug,		'debug'		=> \$debug,
    'h'		=> \$o_help,		'help'		=> \$o_help,
    'O:s'	=> \$output_dir,	'output-dir:s'	=> \$output_dir,
    );

if ($o_help or ! @ARGV) {
    die (<<EOT);

Syntax : $0 [options] file1 ...

    Options :

        -O	output directory

EOT
}

my %hostdata;

foreach my $file (@ARGV) {
    process_file ($file, \%hostdata, $debug);
}

# break up the union of all scan files into an XML blob per host
foreach my $host (sort keys %hostdata) {
    my $thishost = $hostdata{$host};

    warn ("DUMP of host '$host' :\n" . Dumper ($thishost) . "\n\n") if ($debug);

    my $json = JSON->new->utf8->pretty (1)->canonical (1)->encode ($thishost);
    warn ("JSON output for host '$host' :\n${json}\n\n") if ($debug);

    if ($output_dir) {
	my $fn = "$output_dir/${host}..SCAN";
	open (OUT, "> $fn") or die ("$0: Could not open '$fn' for writing : $!\n");
	print (OUT $json);
	close (OUT);
    }

    my $decoded = JSON->new->utf8->decode ($json);
    warn ("DUMP of DECODE : " . Dumper ($decoded) . "\n\n") if ($debug);
}

exit (0);


sub process_file
{
    my $file = shift;
    my $href = shift;
    my $debug = shift;

    my $np = new Nmap::Parser;

    warn ("Parsing file '$file'\n") if ($debug);

    $np->parsefile ($file) or die ("$0: Failed parsing file '$file'\n");

    foreach my $host ($np->all_hosts ('up')) {
	my $hostname = $host->hostname ();

	warn ("Processing $hostname\n") if ($debug);

	# NERDS data format version
	$$href{$hostname}{'host'}{'version'} = 1;

	$$href{$hostname}{'host'}{'name'} = $hostname;
	$$href{$hostname}{'host'}{'status'} = $host->status ();
	@{$$href{$hostname}{'host'}{'addrs'}} = $host->addr ();
	@{$$href{$hostname}{'host'}{'hostnames'}} = $host->all_hostnames ();

	# OS signature
	my $os = $host->os_sig ();
	$$href{$hostname}{'host'}{'os'}{'name'} = $os->name ();
	$$href{$hostname}{'host'}{'os'}{'family'} = $os->family ();

	# now, record open ports under a host+addr key to later be able to extend
	# this to actually know that a service could be listening on a specific IP
	# and not all IPs
	my $this_addrtype = $host->addrtype ();
	my $this_addr = $host->addr ();

	foreach my $proto ('tcp', 'udp') {
	    my @open_ports = get_open_ports ($host, $proto);

	    foreach my $port (@open_ports) {
		my $svc = get_service ($host, $proto, $port);

		next unless ($svc);

		# all available data in an Nmap::Parser::Host::Service object (from Nmap::Parser(3pm))
		foreach my $key ('name', 'proto', 'confidence', 'extrainfo',
				 'owner', 'product', 'rpcnum', 'tunnel', 'version') {
		    my $val = $svc->$key ();

		    next unless ($val);

		    $$href{$hostname}{'host'}{'services'}{$this_addrtype}{$this_addr}{$proto}{$port}{$key} = $val;
		}
	    }
	}
    }
}

sub get_open_ports
{
    my $host = shift;
    my $proto = shift;

    return $host->tcp_open_ports () if ($proto eq 'tcp');
    return $host->udp_open_ports () if ($proto eq 'udp');

    die ("$0: Unknown protocol '$proto'");
}

sub get_service
{
    my $host = shift;
    my $proto = shift;
    my $port = shift;

    return $host->tcp_service ($port) if ($proto eq 'tcp');
    return $host->udp_service ($port) if ($proto eq 'udp');

    die ("$0: Unknown protocol '$proto'");
}
