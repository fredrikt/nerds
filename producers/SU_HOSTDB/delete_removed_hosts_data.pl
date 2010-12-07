#!/usr/bin/env perl
#
# Check all NERDS JSON data files and remove the ones for hosts not (any longer)
# found in HOSTDB.
#

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;
use HOSTDB;

my $debug = 0;
my $o_help = 0;
my @input_dirs;
my $output_dir;
my $devicenets_fn;
my $dryrun = 0;

Getopt::Long::Configure ("bundling");
GetOptions(
    'd'		=> \$debug,		'debug'			=> \$debug,
    'h'		=> \$o_help,		'help'			=> \$o_help,
    'n'		=> \$dryrun,		'dry-run'	       	=> \$dryrun
    );

if ($o_help) {
    die (<<EOT);

Syntax : $0 [options] dir [...]

    Required options :

        -n|--dry-run	Only show missing hosts.

EOT
}

@input_dirs = @ARGV;

my @files;

foreach my $input_dir (@input_dirs) {
    die ("$0: Invalid input dir '$input_dir'\n") unless (-d $input_dir);
    warn ("Looking for producers in directory '$input_dir'...\n") if ($debug);

    my @t_files;

    @t_files = get_producers_files ($input_dir);
    if (! @t_files) {
	# no producers under $input_dir, see if it points directly at some NERDS data files

	@t_files = get_nerds_data_files ($input_dir);

	if (@t_files) {
	    warn ("Loading files in directory '$input_dir'...\n") if ($debug);

	    foreach my $file (@t_files) {
		push (@files, "$input_dir/$file");
	    }
	} else {
	    die ("$0: Bad input directory : '$input_dir'\n");
	}
    } else {
	push (@files, @t_files);
    }
}

my $hostdb;
if (@files) {
    $hostdb = HOSTDB::DB->new (	inifile => HOSTDB::get_inifile (),
		#		debug => $debug
	);
}

my %hostdata;

foreach my $file (@files) {
    warn ("  file '$file'\n") if ($debug);
    process_file ("$file", $hostdb, $dryrun, \%hostdata, $debug);
}

foreach my $hostname (sort keys %hostdata) {
    if ($hostdata{$hostname}{'status'} eq 'REMOVED') {
	my @f = @{$hostdata{$hostname}{'files'}};

	if ($dryrun) {
	    warn ("$hostname not found, keeping " . scalar (@f) . " file(s)\n");
	} else {
	    warn ("$hostname not found, removing " . scalar (@f) . " file(s) :\n");
	}

	foreach my $t (@f) {
	    warn ("   $t\n");
	    unlink ($t) unless ($dryrun);
	}
    }
}

exit (0);

#
# SUBROUTINES
#


# Recurse into $input_dir, collecting all NERDS data files for each
# producer found therein.
sub get_producers_files
{
    my $input_dir = shift;

    my @producers = get_producers ($input_dir);

    my @res;

    foreach my $producer (sort @producers) {
	my $pd = get_nerds_data_dir ($input_dir, $producer);

	warn ("Loading producer '$producer' ($pd)...\n") if ($debug);

	my $count = 0;
	foreach my $file (get_nerds_data_files ($pd)) {
	    push (@res, "$pd/$file");
	    $count++;
	}

	warn ("Loaded $count data files from $pd\n") if ($debug);
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
	next if ($t =~ /^\./o);
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

sub process_file
{
    my $file = shift;
    my $hostdb = shift;
    my $dryrun = shift;
    my $hostdata_ref = shift;
    my $debug = shift;

    open (IN, "< $file") or die ("$0: Could not open '$file' for reading : $!\n");
    my $json = join ('', <IN>);
    close (IN);

    my $t;

    $t = JSON->new->utf8->decode ($json);

    #warn ("DECODED : " . Dumper ($t) . "\n") if ($debug);

    my $nerds_version = $$t{'host'}{'version'};

    if ($nerds_version != 1) {
	die ("$0: Can't interpret NERDS data of version '$nerds_version' in file '$file'\n");
    }

    my $hostname = $$t{'host'}{'name'};

    # list all files for a host in an array
    push (@{$$hostdata_ref{$hostname}{'files'}}, $file);

    my $host = $hostdb->findhostbyname ($hostname);

    if ($$t{'host'}{'SU_HOSTDB'} and $host) {
	# This file has SU_HOSTDB data in it, check if host still exists in HOSTDB.

	# Check that hostdb ID still matches, and warn if it does not
	my $id = $host->id ();
	my $nerds_id = get_host_id ($t, $hostname);
	
	if ($id != $nerds_id) {
	    warn ("WARNING: Host $hostname has ID $id in HOSTDB, but $nerds_id in $file\n");
	} else {
	    warn ("OK: $file\n") if ($debug);
	}
    }

    if (! $host) {
	warn ("HOST $hostname REMOVED\n") if ($debug);
	$$hostdata_ref{$hostname}{'status'} = 'REMOVED';
    }
}

sub get_host_id
{
    my $h = shift;
    my $hostname = shift;

    foreach my $id (keys %{$$h{'host'}{'SU_HOSTDB'}{'host'}}) {
	if ($$h{'host'}{'SU_HOSTDB'}{'host'}{$id}{'hostname'} eq $hostname) {
	    return int ($id);
	}
    }

    return undef;
}

