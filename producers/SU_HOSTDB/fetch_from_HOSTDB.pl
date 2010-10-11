#!/usr/bin/env perl
#
# This producer fetches info about hosts we have JSON data for from HOSTDB,
# which is the host management system in use at Stockholm university.
#

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;
use HOSTDB;

my $MYNAME = 'SU_HOSTDB';
my $debug = 0;
my $o_help = 0;
my @input_dirs;
my $output_dir;

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

my $hostdb = HOSTDB::DB->new (	inifile => HOSTDB::get_inifile (),
				debug => $debug
    );


my %hostdata;

foreach my $input_dir (@input_dirs) {
    die ("$0: Invalid input dir '$input_dir'\n") unless (-d $input_dir);

    my @producers = get_producers ($input_dir);

    if (! @producers) {
	# no producers under $input_dir, see if it points directly at some NERDS data files

	my @files = get_nerds_data_files ($input_dir);

	if (@files) {
	    warn ("Loading files in directory '$input_dir'...\n") if ($debug);
	}

	foreach my $file (@files) {
	    warn ("  file '$file'\n") if ($debug);
	    process_file ("$input_dir/$file", \%hostdata, $debug, $hostdb);
	}
    }

    foreach my $producer (sort @producers) {
	warn ("Loading producer '$producer'...\n") if ($debug);

	my $pd = get_nerds_data_dir ($input_dir, $producer);
	my @files = get_nerds_data_files ($pd);

	foreach my $file (@files) {
	    warn ("  file '$file'\n") if ($debug);
	    process_file ("$pd/$file", \%hostdata, $debug, $hostdb);
	}
    }
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
# we fetch info from HOSTDB for the host in question, and store all that info in $href.
sub process_file
{
    my $file = shift;
    my $href = shift;
    my $debug = shift;
    my $hostdb = shift;

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

    my @hosts = $hostdb->findhostbyname ($hostname);

    if (@hosts) {
	my %res;

	# mandatory basic NERDS data for a host
	$res{'host'}{'version'} = 1;
	$res{'host'}{'name'} = $hostname;

	foreach my $host (@hosts) {
	    if (! $host) {
		warn ("HOSTDB findhostbyname '$hostname' returned non-host result : " . Dumper (\@hosts) . "\n");
	    }
	    push (@{$res{'host'}{'hostnames'}}, $host->hostname ());
	    push (@{$res{'host'}{'addrs'}}, $host->ip ());

	    my %hostinfo;
	    my $id = $host->id ();

	    $hostinfo{'parent'}		= $host->partof ();
	    $hostinfo{'ip'}		= $host->ip ();
	    $hostinfo{'mac'}		= $host->mac_address ();
	    $hostinfo{'hostname'}	= $host->hostname ();
	    $hostinfo{'comment'}	= $host->comment ();
	    $hostinfo{'owner'}		= $host->owner ();
	    $hostinfo{'dhcpstatus'}	= $host->dhcpstatus ();
	    $hostinfo{'dhcpmode'}	= $host->dhcpmode ();
	    $hostinfo{'dnsstatus'}	= $host->dnsstatus ();
	    $hostinfo{'dnsmode'}	= $host->dnsmode ();
	    $hostinfo{'ttl'}		= $host->ttl ();
	    $hostinfo{'profile'}	= $host->profile ();
	    $hostinfo{'zone'}		= $host->dnszone ();
	    $hostinfo{'manual_zone'}	= $host->manual_dnszone ();
	    # not included because it changes
	    #$hostinfo{'mac_ts'}		= $host->mac_address_ts ();

	    foreach my $key (sort keys %hostinfo) {
		my $value = $hostinfo{$key};
		next unless (defined ($value));

		$res{'host'}{$MYNAME}{'host'}{$id}{$key} = $value;
	    }

	    my $comment = $host->comment ();

	    # Store first found comment as commend on the NERD host level.
	    # Comment is probably not SU-specific information about hosts.
	    $res{'host'}{'comment'} = $comment if ($comment and ! $res{'host'}{'comment'});

	    # Get any host aliases
	    my @aliases = $host->init_aliases ();
	    if (@aliases) {
		my @alias_ids;
		foreach my $alias (@aliases) {
		    my %aliasinfo;

		    my $aid = $alias->id ();

		    $aliasinfo{'aliasname'}	= $alias->aliasname ();
		    $aliasinfo{'ttl'}		= $alias->ttl ();
		    $aliasinfo{'dnszone'}	= $alias->dnszone ();
		    $aliasinfo{'dnsstatus'}	= $alias->dnsstatus ();
		    $aliasinfo{'comment'}	= $alias->comment ();

		    push (@alias_ids, $aid);

		    foreach my $key (sort keys %aliasinfo) {
			my $value = $aliasinfo{$key};
			next unless (defined ($value));

			$res{'host'}{$MYNAME}{'alias'}{$aid}{$key} = $value;
		    }
		}

		@{$res{'host'}{$MYNAME}{'host'}{$id}{'aliases'}} = @alias_ids;
	    }

	    # Store basic information about the subnet too. Very useful in monitoring applications.
	    my $subnet = $hostdb->findsubnetbyip ($host->ip ());
	    if ($subnet) {
		my $name = $subnet->netaddr () . '/' . $subnet->slashnotation ();
		my $subnet_id = $subnet->id ();

		$res{'host'}{$MYNAME}{'host'}{$id}{'subnet_id'} = $subnet_id;

		$res{'host'}{$MYNAME}{'subnet'}{$subnet_id}{'name'} = $name;
		$res{'host'}{$MYNAME}{'subnet'}{$subnet_id}{'description'} = $subnet->description ();
		$res{'host'}{$MYNAME}{'subnet'}{$subnet_id}{'owner'} = $subnet->owner ();
	    }
	}

	my $res_ref = \%res;
	make_uniq ($$res_ref{'host'}{'addrs'});
	make_uniq ($$res_ref{'host'}{'hostnames'});
	
	$$href{$hostname} = $res_ref;
    }
}

# `sort | uniq` of a list reference
sub make_uniq
{
    my $lref = shift;

    my %hash;
    foreach my $t (@{$lref}) {
	$hash{$t} = 1;
    }

    @{$lref} = sort keys (%hash);
}
