#!/usr/bin/env perl
#
# Remove a service from one or more NERDS data files. Typically used
# after you turn of a service on a host.
#
# Copyright (c) 2010, Avdelningen för IT och media, Stockholm university
# See the file LICENSE for full license.
#

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;

my $debug = 0;
my $o_help = 0;
my @input_files;

Getopt::Long::Configure ("bundling");
GetOptions(
    'd'		=> \$debug,		'debug'		=> \$debug,
    'h'		=> \$o_help,		'help'		=> \$o_help
    );

my $remove_spec = shift;
@input_files = @ARGV;

my $remove_proto;
my $remove_port;
if ($remove_spec =~ /^([a-z]+):(\d+)$/o) {
    $remove_proto = $1;
    $remove_port  = $2;
} else {
    warn ("Bad proto:port spec '$remove_spec'\n\n");
}

if ($o_help or ! $remove_proto or ! $remove_port or ! @input_files) {
    die (<<EOT);

Syntax : $0 [options] proto:port [file ...]

   Proto is tcp, udp or similar.
   Port is an integer.

EOT
}

foreach my $input_file (@input_files) {
    warn ("  file '$input_file'\n") if ($debug);
    process_file ("$input_file", $remove_proto, $remove_port, $debug);
}


exit (0);

# Read and parse a potential NERDS data file. If it was a valid NERDS data file,
# we remove the service in question.
sub process_file
{
    my $file = shift;
    my $remove_proto = shift;
    my $remove_port = shift;
    my $debug = shift;

    open (IN, "< $file") or die ("$0: Could not open '$file' for reading : $!\n");
    my $json = join ("", <IN>);
    close (IN);

    my $t;

    $t = JSON->new->utf8->decode ($json);

    #warn ("DECODED : " . Dumper ($t) . "\n") if ($debug);

    my $hostname = $$t{'host'}{'name'};
    my $nerds_version = $$t{'host'}{'version'};

    if ($nerds_version != 1) {
	die ("$0: Can't interpret NERDS data of version '$nerds_version' in file '$file'\n");
    }

    my $changed = 0;

    foreach my $family (keys %{$$t{'host'}{'services'}}) {
	foreach my $addr (keys %{$$t{'host'}{'services'}{$family}}) {
	    if ($$t{'host'}{'services'}{$family}{$addr}{$remove_proto}{$remove_port}) {
		warn ("Removing $family:$addr:$remove_proto:$remove_port\n");
		delete ($t->{'host'}{'services'}{$family}{$addr}{$remove_proto}{$remove_port});
		$changed = 1;
	    } else {
		warn ("Remove-spec $remove_proto:$remove_port NOT FOUND on $family:$addr\n");
	    }
	}
    }

    if ($changed) {
	my $new_json = JSON->new->utf8->pretty (1)->canonical (1)->encode ($t);
	warn ("JSON output for host '$hostname' :\n${new_json}\n\n") if ($debug);
	open (OUT, "> $file") or die ("$0: Could not open '$file' for writing : $!\n");
	print (OUT $new_json);
	close (OUT);
    }
}
