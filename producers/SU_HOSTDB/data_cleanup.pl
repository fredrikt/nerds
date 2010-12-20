#!/usr/bin/env perl
#
# Various clean up operations for SU_HOSTDB data. For example, merge_nerds
# make us end up with lists of aliases containing duplicates.
#
# Copyright (c) 2010, Avdelningen för IT och media, Stockholm university
# See the file LICENSE for full license.
#

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;

my $MYNAME = 'SU_HOSTDB';
my $debug = 0;
my $o_help = 0;
my @input_dirs;

Getopt::Long::Configure ("bundling");
GetOptions(
    'd'		=> \$debug,		'debug'		=> \$debug,
    'h'		=> \$o_help,		'help'		=> \$o_help
    );

@input_dirs = @ARGV;

if ($o_help or ! @input_dirs) {
    die (<<EOT);

Syntax : $0 [options] [dir ...]

EOT
}

foreach my $input_dir (@input_dirs) {
    my %hostdata;

    die ("$0: Invalid input dir '$input_dir'\n") unless (-d $input_dir);

    my @files = get_nerds_data_files ($input_dir);

    if (@files) {
	warn ("Loading files in directory '$input_dir'...\n") if ($debug);
    }

    foreach my $file (@files) {
	warn ("  file '$file'\n") if ($debug);
	process_file ("$input_dir/$file", \%hostdata, $debug);
    }

    # output a JSON document for every host in %hostdata
    foreach my $host (sort keys %hostdata) {
	my $thishost = $hostdata{$host};

	my $json = JSON->new->utf8->pretty (1)->canonical (1)->encode ($thishost);
	#die ("JSON output for host '$host' :\n${json}\n\n");

	my $fn = "$input_dir/${host}..json";
	warn ("Outputting to '$fn'\n") if ($debug);
	open (OUT, "> $fn") or die ("$0: Could not open '$fn' for writing : $!\n");
	print (OUT $json);
	close (OUT);
    }
}


exit (0);


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

# Get a list of all potential NERDS data files in a directory. Does not
# actually parse them to verify they are NERDS data files.
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
# we do some data cleanup on it.
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

    if (! $$t{'host'}{$MYNAME}) {
	warn ("Skipping $file (no {'host'}{$MYNAME})\n") if ($debug);
	return;
    }

    foreach my $id (keys %{$$t{'host'}{$MYNAME}{'host'}}) {
	if ($$t{'host'}{$MYNAME}{'host'}{$id}{'aliases'}) {
	    #warn ("UNIQ : " . Dumper ($$t{'host'}{$MYNAME}{'host'}{$id}) . "\n");
	    make_uniq ($$t{'host'}{$MYNAME}{'host'}{$id}{'aliases'});
	    #warn ("AFTER : " . Dumper ($$t{'host'}{$MYNAME}{'host'}{$id}) . "\n");
	}

	# subnet->id changed to subnet_id
	delete ($t->{'host'}{$MYNAME}{'host'}{$id}{'subnet'});
    }

    # cruft from early development of nmap_services
    delete ($t->{'host'}{'os'});
    delete ($t->{'host'}{'status'});

    # don't want msrpc ports in my NERDS data repository
    foreach my $family (keys %{$$t{'host'}{'services'}}) {
	foreach my $addr (keys %{$$t{'host'}{'services'}{$family}}) {
	    foreach my $proto (keys %{$$t{'host'}{'services'}{$family}{$addr}}) {
		foreach my $port (sort keys %{$$t{'host'}{'services'}{$family}{$addr}{$proto}}) {
		    next if int ($port) < 1024;

		    my $nmap_name = $$t{'host'}{'services'}{$family}{$addr}{$proto}{$port}{'name'};
		    my $nmap_proto = $$t{'host'}{'services'}{$family}{$addr}{$proto}{$port}{'proto'};
		    if ($nmap_name eq 'msrpc' and $nmap_proto eq 'unknown') {
			delete ($t->{'host'}{'services'}{$family}{$addr}{$proto}{$port});
		    }
		}
	    }
	}
    }

    # sort | uniq lists of Nagios groups
    make_uniq ($$t{'host'}{'SU_nagios_metadata'}{'aux_hostgroups'});
    if ($$t{'host'}{'SU_nagios_metadata'}{'service_groups'}) {
	foreach my $check (keys %{$$t{'host'}{'SU_nagios_metadata'}{'service_groups'}}) {
	    make_uniq ($$t{'host'}{'SU_nagios_metadata'}{'service_groups'}{$check});
	}
    }

    $$href{$hostname} = $t;
}

# `sort | uniq` of a list reference
sub make_uniq
{
    my $lref = shift;

    return undef unless defined ($lref);

    eval { my $a = @{$lref}; };
    if ($@) {
	warn ("$0: make_uniq called with bad input ($@) :\n" . Dumper ($lref) . "\n");
	return undef;
    }

    my %hash;
    foreach my $t (@{$lref}) {
	$hash{$t} = 1;
    }

    @{$lref} = sort keys (%hash);
}
