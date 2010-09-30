#!/usr/bin/env perl
#

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;
use Hash::Merge;

my $debug = 0;
my $o_help = 0;
my $input_dir;
my $output_dir;

Getopt::Long::Configure ("bundling");
GetOptions(
    'd'		=> \$debug,		'debug'		=> \$debug,
    'h'		=> \$o_help,		'help'		=> \$o_help,
    'O:s'	=> \$output_dir,	'output-dir:s'	=> \$output_dir,
    'I:s'	=> \$input_dir,		'input-dir:s'	=> \$input_dir,
    );

if ($o_help or ! $output_dir) {
    die (<<EOT);

Syntax : $0 -O dir [options]

    Required options :

        -O	output directory

    Optional options :

        -I	input directory (default: output directory)

EOT
}

$input_dir = $output_dir unless ($input_dir);

die ("$0: Invalid output dir '$output_dir'\n") unless (-d $output_dir);
die ("$0: Invalid input dir '$input_dir'\n") unless (-d $input_dir);

my @producers = get_producers ($input_dir);

my %hostdata;

foreach my $producer (@producers) {
    next if ($producer eq 'merge_nerds');	# skip my own output
    warn ("Loading producer '$producer'...\n") if ($debug);

    my @files = get_nerds_data_files ($input_dir, $producer);

    my $pd = get_nerds_data_dir ($input_dir, $producer);

    foreach my $file (@files) {
	warn ("  file '$file'\n") if ($debug);
	process_file ("$pd/$file", \%hostdata, $debug);
    }
}

# break up the union of all scan files into an XML blob per host
foreach my $host (sort keys %hostdata) {
    my $thishost = $hostdata{$host};

    my $json = JSON->new->utf8->pretty (1)->canonical (1)->encode ($thishost);
    #warn ("JSON output for host '$host' :\n${json}\n\n") if ($debug);

    my $dir = get_nerds_data_dir ($output_dir, 'merge_nerds');
    my $fn = "${dir}/${host}..json";
    warn ("Outputting to '$fn'\n") if ($debug);
    open (OUT, "> $fn") or die ("$0: Could not open '$fn' for writing : $!\n");
    print (OUT $json);
    close (OUT);
}

exit (0);


sub get_producers
{
    my $input_dir = shift;

    my @producers;

    my $dir = "$input_dir/producers/";
    opendir (DIR, $dir) or die ("$0: Could not opendir '$dir' : $!\n");
    while (my $t = readdir (DIR)) {
	next if ($t eq '.');
	next if ($t eq '..');
	next unless (-d "$input_dir/producers/$t");

	push (@producers, $t);
    }

    closedir (DIR);

    return @producers;
}

sub get_nerds_data_files
{
    my $input_dir = shift;
    my $producer = shift;

    my @files;

    my $dir = get_nerds_data_dir ($input_dir, $producer);
    opendir (DIR, $dir) or die ("$0: Could not opendir '$dir' : $!\n");
    while (my $t = readdir (DIR)) {
	next unless ($t =~ /.+\.\.json$/oi);
	next unless (-f "$dir/$t");

	push (@files, $t);
    }

    closedir (DIR);

    return @files;
}

sub get_nerds_data_dir
{
    my $repo = shift;
    my $producer = shift;

    return "$repo/producers/$producer/json";
}

sub process_file
{
    my $file = shift;
    my $href = shift;
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

    # perform a deep merge of two hashes (basically two JSON documents)
    if ($$href{$hostname}) {
	warn ("    Merging data for host '$hostname'\n") if ($debug);
	my $merged = Hash::Merge::merge ($$href{$hostname}, $t);
	$t = $merged;
    }

    $$href{$hostname} = $t;
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
