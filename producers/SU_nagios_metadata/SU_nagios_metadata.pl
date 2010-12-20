#!/usr/bin/env perl
#
# This producer creates Nagios metadata for hosts. Such metadata
# could be information about auxillary host groups we want a host
# to be a member of, for example.
#
# Copyright (c) 2010, Avdelningen för IT och media, Stockholm university
# See the file LICENSE for full license.
#

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;

my $MYNAME = 'SU_nagios_metadata';
my $debug = 0;
my $o_help = 0;
my @input_dirs;
my $output_dir;
my $groups_file;

Getopt::Long::Configure ("bundling");
GetOptions(
    'd'		=> \$debug,		'debug'			=> \$debug,
    'h'		=> \$o_help,		'help'			=> \$o_help,
    'O:s'	=> \$output_dir,	'output-dir:s'		=> \$output_dir,
					'groups-file:s'		=> \$groups_file
    );

if ($o_help or ! $output_dir) {
    die (<<EOT);

Syntax : $0 -O dir [options] [input-dir ...]

    Required options :

        -O	output directory

    Options :

        --groups-file <file>	File with host group information in it.
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

my %hostgroups_data;
my %servicegroups_data;
if ($groups_file) {
    load_groups ($groups_file, \%hostgroups_data, \%servicegroups_data);
}

my %hostdata;

foreach my $file (sort @files) {
    warn ("  file '$file'\n") if ($debug);
    process_file ($file, \%hostdata, $debug, \%hostgroups_data, \%servicegroups_data);
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
    my $hostgroups_ref = shift;
    my $servicegroups_ref = shift;

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

    add_groups ($hostname, $hostgroups_ref, $servicegroups_ref, $href, $debug);
}

sub add_groups
{
    my $hostname = shift;
    my $hostgroups_ref = shift;
    my $servicegroups_ref = shift;
    my $href = shift;
    my $debug = shift;

    my %res;

    # mandatory basic NERDS data for a host
    $res{'host'}{'version'} = 1;
    $res{'host'}{'name'} = $hostname;

    my $g_count = 0;

    foreach my $id (sort keys %{$hostgroups_ref}) {
	my @regexps = @{$$hostgroups_ref{$id}{'host-regexps'}};
	my $group = $$hostgroups_ref{$id}{'group'};
	my $desc =  $$hostgroups_ref{$id}{'desc'};

	foreach my $regexp (@regexps) {
	    if (defined ($regexp) and $hostname =~ /$regexp/) {
		$g_count++;
		warn ("Add $hostname to group $group ($desc, RE $regexp)\n") if ($debug);

		if ($$hostgroups_ref{$id}{'type'} eq 'aux') {
		    # add to list of auxillary groups for this host
		    push (@{$res{'host'}{$MYNAME}{'aux_hostgroups'}}, $group);
		} else {
		    # set as primary hostgroup
		    $res{'host'}{$MYNAME}{'hostgroup'} = $group;
		}
	    }
	}
    }

    foreach my $id (sort keys %{$servicegroups_ref}) {
	my @regexps = @{$$servicegroups_ref{$id}{'host-service-regexps'}};
	my $group = $$servicegroups_ref{$id}{'group'};

	foreach my $regexp (@regexps) {
	    next unless defined ($regexp);

	    my $host_regexp = '';
	    my $service_regexp = '';
	    if ($regexp =~ /^(.+?)\/(.+)$/o) {
		$host_regexp = $1;
		$service_regexp = $2;
	    } else {
		$host_regexp = $regexp;
		$service_regexp = '.*';
	    }

	    if ($hostname =~ /$host_regexp/) {
		$g_count++;
		warn ("Add $hostname to service group $group (RE $service_regexp)\n") if ($debug);

		push (@{$res{'host'}{$MYNAME}{'service_groups'}{$service_regexp}}, $group);
	    }
	}
    }

    if ($g_count) {
	$$href{$hostname} = \%res;
    }

    return $g_count;
}

sub load_groups
{
    my $fn = shift;
    my $hostgroups_ref = shift;
    my $servicegroups_ref = shift;

    my $hostgroup_id = 0;
    my $servicegroup_id = 0;

    open (IN, "< $fn") or die ("$0: Could not open hostgroup file '$fn' for reading : $!\n");
    while (my $t = <IN>) {
	chomp ($t);
	next if ($t =~ /^\s*#/o);	# skip comments
	next if ($t =~ /^\s*$/o);	# skip blank lines

	if ($t =~ /^aux-hostgroup\s+(\S+)\s+(\S+)\s+(.+)$/o) {
	    my $group = $1;
	    my $desc = $2;
	    my $match = $3;

	    if ($match =~ /^host-regexp:(.+)$/o) {
		$match = $1;
	    } else {
		die ("$0: Unknown match-type in '$match' (line $. of $fn)\n");
	    }
	    $$hostgroups_ref{$hostgroup_id}{'group'} = $group;
	    $$hostgroups_ref{$hostgroup_id}{'type'} = 'aux';
	    $$hostgroups_ref{$hostgroup_id}{'desc'} = $desc;
	    push (@{$$hostgroups_ref{$hostgroup_id}{'host-regexps'}}, $match);
	    #warn ("GROUP $group REGEXPS NOW : " . join (' ', @{$$hostgroups_ref{$hostgroup_id}{'host-regexps'}}) . "\n");
	    $hostgroup_id++;
	} elsif ($t =~ /^servicegroup\s+(\S+)\s+(\S+)\s+(.+)$/o) {
	    my $groups = $1;
	    my $desc = $2;
	    my $match = $3;

	    if ($match =~ /^host-service-regexp:(.+)$/o) {
		$match = $1;
	    } else {
		die ("$0: Unknown match-type in '$match' (line $. of $fn)\n");
	    }

	    foreach my $group (split (',', $groups)) {
		$$servicegroups_ref{$servicegroup_id}{'group'} = $group;
		$$servicegroups_ref{$servicegroup_id}{'desc'} = $desc;
		push (@{$$servicegroups_ref{$servicegroup_id}{'host-service-regexps'}}, $match);
		#warn ("GROUP $group REGEXPS NOW : " . join (' ', @{$$servicegroups_ref{$servicegroup_id}{'service-regexps'}}) . "\n");
		$servicegroup_id++;
	    }
	} else {
	    die ("$0: Bad input on line $. of file $fn\n");
	}
    }

    close (IN);
}
