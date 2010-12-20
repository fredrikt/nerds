#!/usr/bin/env perl
#
# This producer fetches info about hosts we have JSON data for from cfgstore,
# which is data collected on most UNIX servers we administer.
#
# Copyright (c) 2010, Avdelningen för IT och media, Stockholm university
# See the file LICENSE for full license.
#

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;

my $MYNAME = 'SU_cfgstore';
my $debug = 0;
my $o_help = 0;
my @input_dirs;
my $output_dir;

my $cfgstore_dir = '/afs/su.se/services/cfgstore/hosts';

Getopt::Long::Configure ("bundling");
GetOptions(
    'd'		=> \$debug,		'debug'		=> \$debug,
    'h'		=> \$o_help,		'help'		=> \$o_help,
    'O:s'	=> \$output_dir,	'output-dir:s'	=> \$output_dir
    );

if ($o_help or ! $output_dir) {
    die (<<EOT);

Syntax : $0 -O dir [options] [input-dir ...]

    Required options :

        -O	output directory

EOT
}

@input_dirs = @ARGV;
push (@input_dirs, $output_dir) unless (@input_dirs);

die ("$0: Invalid output dir '$output_dir'\n") unless ($output_dir and -d $output_dir);

my @files;

foreach my $input_dir (@input_dirs) {
    die ("$0: Invalid input dir '$input_dir'\n") unless (-d $input_dir);

    @files = get_producers_files ($input_dir);
    if (! @files) {
	# no producers under $input_dir, see if it points directly at some NERDS data files

	@files = get_nerds_data_files ($input_dir);

	if (@files) {
	    warn ("Loading files in directory '$input_dir'...\n") if ($debug);
	}
    }
}

my %hostdata;

foreach my $file (@files) {
    warn ("  file '$file'\n") if ($debug);
    process_file ($file, \%hostdata, $debug, $cfgstore_dir);
}

# output a JSON document for every host in %hostdata
foreach my $host (sort keys %hostdata) {
    my $thishost = $hostdata{$host};

    my $json = JSON->new->utf8->pretty (1)->canonical (1)->encode ($thishost);
    #die ("JSON output for host '$host' :\n${json}\n\n");

    my $dir = get_nerds_data_dir ($output_dir, $MYNAME);
    my $fn = "${dir}/${host}..json";
    warn ("Outputting to '$fn'\n") if ($debug);
    open (OUT, "> $fn") or die ("$0: Could not open '$fn' for writing : $!\n");
    print (OUT $json);
    close (OUT);
}

exit (0);


# Recurse into $input_dir, collecting all NERDS data files for each
# producer found therein.
sub get_producers_files
{
    my $input_dir = shift;

    my @producers = get_producers ($input_dir);

    my @res;

    foreach my $producer (sort @producers) {
	warn ("Loading producer '$producer'...\n") if ($debug);

	my $pd = get_nerds_data_dir ($input_dir, $producer);

	foreach my $file (get_nerds_data_files ($pd)) {
	    push (@res, "$pd/$file");
	}
    }

    return @res;
}

# Get a list of all producers under $input_dir/producers/
sub get_producers
{
    my $input_dir = shift;

    my @producers;

    my $dir = "$input_dir/producers/";
    opendir (DIR, $dir) or return ();
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
    my $dir = shift;

    my @files;

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

# Read and parse a potential NERDS data file. If it was a valid NERDS data file,
# we fetch info from cfgstore for the host in question, and store all that info in $href.
sub process_file
{
    my $file = shift;
    my $href = shift;
    my $debug = shift;
    my $cfgstore_dir = shift;

    open (IN, "< $file") or die ("$0: Could not open '$file' for reading : $!\n");
    my $json = join ('', <IN>);
    close (IN);

    my $t;

    $t = JSON->new->utf8->decode ($json);

    #warn ("DECODED : " . Dumper ($t) . "\n") if ($debug);

    my $hostname = $$t{'host'}{'name'};
    my $nerds_version = $$t{'host'}{'version'};

    if ($nerds_version != 1) {
	die ("$0: Can't interpret NERDS data of version '$nerds_version' in file '$file'\n");
    }

    my $cfgstore_file = get_most_recent_hostinfo_file ("${cfgstore_dir}/${hostname}", $hostname);

    if ($cfgstore_file) {
	my %res;

	# mandatory basic NERDS data for a host
	$res{'host'}{'version'} = 1;
	$res{'host'}{'name'} = $hostname;

	my %info;

	open (CFG, " < $cfgstore_file") or die ("$0: Could not open '$cfgstore_file' for reading : $!\n");
	while (my $line = <CFG>) {
	    last if ($line =~ /^CFGSTORE: DIFF START/o);

	    $info{'goldenname'} = $1 if ($line =~ /^CFGSTORE: GOLDENNAME: (.+)$/o);

	    if ($line =~ /^CFGSTORE: VIRTUAL-MACHINE: (.+)/o) {
		my $t = $1;

		if ($t =~ /^\s*Yes/io) {
		    $info{'is_virtual'} = JSON::true ();
		} elsif ($t =~ /^\s*No/io) {
		    $info{'is_virtual'} = JSON::false ();
		} elsif ($t =~ /^\s*Probably not/o) {
		    # this could be made "unknown" in the future by not setting $is_virtual but providing $virtual_info
		    $info{'is_virtual'} = JSON::false ();
		}

		if ($t =~ /\((.+)\)/o) {
		    $info{'virtual_info'} = $1;
		}
	    }

	    foreach my $key (sort keys %info) {
		my $value = $info{$key};
		next unless (defined ($value));

		$res{'host'}{$MYNAME}{$key} = $value;
	    }
	}

	close (CFG);

	$$href{$hostname} = \%res;
    } else {
	warn ("Found no cfgstore data for host '$hostname' in '$cfgstore_dir'\n") if ($debug);
    }
}

sub get_most_recent_hostinfo_file {
    my $dir = shift;
    my $hostname = shift;

    opendir (DIR, $dir) or return undef;
    # get all files of format hostname_2009-04-03_15h55m
    my @candidates = grep { /^${hostname}_\d\d\d\d-\d\d-\d\d_\d\dh\d\dm$/ && -f "$dir/$_" } readdir(DIR);
    closedir (DIR);

    return undef unless (@candidates);

    # XXX do proper mtime checking instead of using plain 'sort' to find most recent file?
    my @t = sort (@candidates);
    my $most_recent = pop (@t);

    return ("${dir}/${most_recent}");
}

