#!/usr/bin/env perl
#
# $Id$
# $HeadURL$
#

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;

my $debug = 0;
my $o_help = 0;
my $output_dir;

Getopt::Long::Configure ("bundling");
GetOptions(
    'h'		=> \$o_help,		'help'		=> \$o_help,
    'O:s'	=> \$output_dir,	'output-dir:s'	=> \$output_dir,
    );

if ($o_help) {
    die (<<EOT);

Syntax : $0 [options]

    Options :

        -O	output directory

EOT
}

my %produced_data;
my $hostname = 'server.example.org';

$produced_data{'host'}{'version'} = 1;
$produced_data{'host'}{'name'} = $hostname;

$produced_data{'host'}{'dummy_perl'} = {foo => 'bar',
					creators => ('ft', 'leifj')
				};

my $json = JSON->new->utf8->pretty (1)->canonical (1)->encode (\%produced_data);

warn ("JSON reference output :\n\n${json}\n\n");

if ($output_dir) {
    my $fn = "$output_dir/producers/dummy_perl/json/$hostname";

    open (OUT, "> $fn") or die ("$0: Could not open output file '$fn' for writing : $!\n");
    print (OUT $json);
    close (OUT);
}

exit (0);
