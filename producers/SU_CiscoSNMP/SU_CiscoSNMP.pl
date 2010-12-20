#!/usr/bin/env perl
#
# Probe suspected Cisco devices for supported SNMP OIDs.
#
# Copyright (c) 2010, Avdelningen för IT och media, Stockholm university
# See the file LICENSE for full license.
#

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;
use Net::SNMP;

use lib '/local/nagios/lib';
use SU_Nagios qw ( &get_snmp_community &snmp_query_agent );

# This array is for some nice logging... We query each device for these and
# log it to the log file. sysDescr is really implicit here since
# check_is_agent_alive always fetches it to determine if the agent is alive
# or not.
#
my @host_info = ('sysDescr',
		 'sysObjectID',
		 'sysName',
		 'sysLocation'
    );

# this hash will holds all the check-types and oidname to check on each host
#
my %checks;

$checks{'CPU_1MIN'} = ['cpmCPUTotal1minRev','cpmCPUTotal1min'];
$checks{'CPU_5MIN'} = ['cpmCPUTotal5minRev','cpmCPUTotal5min'];
$checks{'MEM_CPU_USED'} = ['ciscoMemoryPoolUsedCPU'];
$checks{'MEM_CPU_FREE'} = ['ciscoMemoryPoolFreeCPU'];
$checks{'MEM_IO_USED'} = ['ciscoMemoryPoolUsedIO'];
$checks{'MEM_IO_FREE'} = ['ciscoMemoryPoolFreeIO'];
$checks{'Console'} = ['con0'];
$checks{'BGP_prefix'} = ['cbgpPeerAccept'];
$checks{'VTY'} = ['ltsLineSession'];
$checks{'Fan'} = ['EnvFanState'];
$checks{'PSU'} = ['EnvPsuState'];
$checks{'Wlan_if'} = ['WlanIfStatus'];
$checks{'Port_err'} = ['Interface_error_count'];


my %name2oid = (
		sysDescr		=> '.1.3.6.1.2.1.1.1.0',
		sysObjectID		=> '.1.3.6.1.2.1.1.2.0',
		sysUpTime		=> '.1.3.6.1.2.1.1.3.0',
		sysContact		=> '.1.3.6.1.2.1.1.4.0',
		sysName			=> '.1.3.6.1.2.1.1.5.0',
		sysLocation		=> '.1.3.6.1.2.1.1.6.0',
		sysServices		=> '.1.3.6.1.2.1.1.7.0',
		cpmCPUTotal1minRev	=> '.1.3.6.1.4.1.9.9.109.1.1.1.1.7.1',
		cpmCPUTotal5minRev	=> '.1.3.6.1.4.1.9.9.109.1.1.1.1.8.1',
		cpmCPUTotal1min		=> '.1.3.6.1.4.1.9.9.109.1.1.1.1.4.1',
		cpmCPUTotal5min		=> '.1.3.6.1.4.1.9.9.109.1.1.1.1.5.1',
		ciscoMemoryPoolUsedCPU	=> '.1.3.6.1.4.1.9.9.48.1.1.1.5.1',
		ciscoMemoryPoolFreeCPU	=> '.1.3.6.1.4.1.9.9.48.1.1.1.6.1',
		ciscoMemoryPoolUsedIO	=> '.1.3.6.1.4.1.9.9.48.1.1.1.5.2',
		ciscoMemoryPoolFreeIO	=> '.1.3.6.1.4.1.9.9.48.1.1.1.6.2',
		con0                    => '.1.3.6.1.4.1.9.2.9.2.1.21.1',
		cbgpPeerAccept          => '.1.3.6.1.4.1.9.9.187.1.2.4.1.1.130.237.154.26.1.1',
		ltsLineSession          => '.1.3.6.1.4.1.9.2.9.2.1.1.1',
		EnvFanState             => '.1.3.6.1.4.1.9.9.13.1.4.1.3',
		EnvPsuState		=> '.1.3.6.1.4.1.9.9.13.1.5.1.3',
		WlanIfStatus            => '.1.3.6.1.4.1.9.9.276.1.1.2.1.3.1',
                Interface_error_count	=> '1.3.6.1.2.1.2.2.1.14.1',
	       );


my $MYNAME = 'SU_CiscoSNMP';
my $debug = 0;
my $o_help = 0;
my @input_dirs;
my $output_dir;
my $devicenets_fn;
my @switchlist_fns;

Getopt::Long::Configure ("bundling");
GetOptions(
    'd'		=> \$debug,		'debug'			=> \$debug,
    'h'		=> \$o_help,		'help'			=> \$o_help,
    'O:s'	=> \$output_dir,	'output-dir:s'		=> \$output_dir,
    'F:s'	=> \$devicenets_fn,	'networks-file:s'	=> \$devicenets_fn,
    'S:s'	=> \@switchlist_fns,	'switches-file:s'	=> \@switchlist_fns,
    );

if ($o_help or ! $output_dir) {
    die (<<EOT);

Syntax : $0 -O dir [options] [input-dir ...]

    Required options :

        -O|--output-dir dir	<output directory>
	-F|--networks-file file <file containing network devices subnets (e.g. 192.0.2.0/24)>
	-S|--switches-file file <file with switch names - if colon-separated (rancid), first field is used>

EOT
}

@input_dirs = @ARGV;
push (@input_dirs, $output_dir) unless (@input_dirs);

die ("$0: Invalid output dir '$output_dir'\n") unless (-d $output_dir);

my $community = get_snmp_community();

my @device_networks = ();
if ($devicenets_fn) {
    open (IN, "< $devicenets_fn") or die ("$0: Could not open networks-file '$devicenets_fn' for reading : $!\n");
    while (my $t = <IN>) {
	chomp ($t);
	next if ($t =~ /^\s*#/o);	# comments
	next if ($t =~ /^\s*$/o);	# blank lines

	push (@device_networks, $t);
    }
    close (IN);
}

my %switches;
if (@switchlist_fns) {
    foreach my $switchlist_fn (@switchlist_fns) {
	open (IN, "< $switchlist_fn") or die ("$0: Could not open switch-list-file '$switchlist_fn' for reading : $!\n");
	while (my $t = <IN>) {
	    chomp ($t);
	    next if ($t =~ /^\s*#/o);		# comments
	    next if ($t =~ /^\s*$/o);		# blank lines
	    $t = $1 if ($t =~ /^(.+?):.+$/o);	# colon separated

	    $t = lc ($t);

	    $switches{$t} = 1;
	}
	close (IN);
    }
}

my %hostdata;

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

foreach my $file (@files) {
    warn ("  file '$file'\n") if ($debug);
    process_file ("$file", \%hostdata, \@device_networks, \%switches, $debug, $community,
		  \@host_info, \%checks, \%name2oid) ;
}

# break up the union of all scan files into a JSON file per host
foreach my $host (sort keys %hostdata) {
    my $thishost = $hostdata{$host};

    my $json = JSON->new->utf8->pretty (1)->canonical (1)->encode ($thishost);
    warn ("JSON output for host '$host' :\n${json}\n\n") if ($debug);

    my $dir = get_nerds_data_dir ($output_dir, $MYNAME);
    my $fn = "${dir}/${host}..json";
    warn ("Outputting to '$fn'\n") if ($debug);
    open (OUT, "> $fn") or die ("$0: Could not open '$fn' for writing : $!\n");
    print (OUT $json);
    close (OUT);
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

sub process_file
{
    my $file = shift;
    my $href = shift;
    my $devicenets_ref = shift;
    my $switches_ref = shift;
    my $debug = shift;
    my $community = shift;
    my $host_info_ref = shift;
    my $checks_ref = shift;
    my $name2oid_ref = shift;

    open (IN, "< $file") or die ("$0: Could not open '$file' for reading : $!\n");
    my $json = join ("", <IN>);
    close (IN);

    my $t;

    $t = JSON->new->utf8->decode ($json);

    #warn ("DECODED : " . Dumper ($t) . "\n") if ($debug);

    my $nerds_version = $$t{'host'}{'version'};

    if ($nerds_version != 1) {
	die ("$0: Can't interpret NERDS data of version '$nerds_version' in file '$file'\n");
    }

    my $hostname = lc ($$t{'host'}{'name'});


    if ($$href{$hostname}) {
	warn ("Host '$hostname' already scanned.\n") if ($debug);
	return undef;
    }

    my $do_scan;
    if ($$switches_ref{$hostname}) {
	warn ("$hostname is a known network device\n") if ($debug);
	$do_scan = 1;
    }

    unless ($do_scan) {
	# Check if subnet of this host is one of our network device networks
	foreach my $subnet_id (keys %{$$t{'host'}{'SU_HOSTDB'}{'subnet'}}) {
	    my $subnet = $$t{'host'}{'SU_HOSTDB'}{'subnet'}{$subnet_id}{'name'};
	    my ($t_subnet) = grep { /^${subnet}$/ } @{$devicenets_ref};
	    if ($t_subnet) {
		warn ("$hostname is on a known network device subnet : $t_subnet\n") if ($debug);
		$do_scan = 1;
		last;
	    } else {
		warn ("    Subnet $subnet not found in list : " . join (', ', @{$devicenets_ref}) . "\n") if ($debug);
	    }
	}
    }

    if (! $do_scan) {
	# look for service identified as Cisco telnet or similar
	foreach my $family (keys %{$$t{'host'}{'services'}}) {
	    foreach my $addr (keys %{$$t{'host'}{'services'}{$family}}) {
		foreach my $proto (keys %{$$t{'host'}{'services'}{$family}{$addr}}) {
		    foreach my $port (keys %{$$t{'host'}{'services'}{$family}{$addr}{$proto}}) {
			if ($$t{'host'}{'services'}{$family}{$addr}{$proto}{$port}{'product'} =~ /Cisco/io) {
			    warn ("$hostname:$port looks like a Cisco service\n") if ($debug);
			    $do_scan = 1;
			    last;
			}
		    }
		}
	    }
	}
    }

    snmp_scan_device ($hostname, $href, $debug, $community,
		      $host_info_ref, $checks_ref, $name2oid_ref
	) if ($do_scan);
}

sub snmp_scan_device
{
    my $agent = shift;
    my $hosts_ref = shift;
    my $debug = shift;
    my $community = shift;
    my $host_info_ref = shift;
    my $checks_ref = shift;
    my $name2oid_ref = shift;

    warn ("SNMP scanning $agent\n") if ($debug);

    my ($snmp_session, $snmp_error) = Net::SNMP->session (
	-community => $community,
	-hostname => $agent,
	-version => "2",
	-timeout => 2
	);

    if (! defined ($snmp_session)) {
	warn ("$0: Could not get SNMP session for agent '$agent' : $snmp_error\n");
	return undef;
    }

    my $logfun = sub {
	my $severity = shift;
	my $msg = shift;
	warn ("$MYNAME: $severity: $msg") if ($debug);
    };

    my %res;

    my $agent_alive = check_is_agent_alive ($agent, $snmp_session,  \%res, $name2oid_ref, $host_info_ref, $logfun);

    if ($agent_alive) {
	# mandatory basic NERDS data for a host
	$res{'host'}{'version'} = 1;
	$res{'host'}{'name'} = $agent;

	foreach my $check_name (keys %{$checks_ref}) {
	    # For some checks, there are different OIDs to try (different ones works on different agents).
	    # Figure out if there is a working one for this check on this agent.
	    my @check_oids = @{$$checks_ref{"$check_name"}};
	    my $found = 0;
	    OID: foreach my $oidname (@check_oids) {
		if (snmpStdQuery ($snmp_session, $oidname, $logfun)) {
		    # OK, we have now verified that this agent supports this OID for use by this check
		    $found = 1;
		    $res{'host'}{$MYNAME}{'checks'}{$check_name}{'name'} = $oidname;
		    $res{'host'}{$MYNAME}{'checks'}{$check_name}{'oid'} = $$name2oid_ref{$oidname};
		    # don't check any more oids for this check
		    last OID;
		}
	    }
	}

	$$hosts_ref{$agent} = \%res;
    }

    # Shut down the SNMP session
    $snmp_session->close();

}

# Query an agent about a number of oids, pretty printing them to the log file.
# Returns 1 if the agent responds to the 'sysDescr' OID.
sub check_is_agent_alive
{
    my $agent = shift;
    my $session = shift;
    my $hosts_ref = shift;
    my $name2oid_ref = shift;
    my $host_info_ref = shift;
    my $logfun = shift;

    my @oids = @{$host_info_ref};

    my $res = 0;

    # Start with determining if the agent is alive or not. We query 'sysDescr' even
    # if it is not in @oids.
    if (my $rtn = snmp_query_agent ($session, 'sysDescr', $name2oid{'sysDescr'}, $logfun) ) {
	$rtn =~ s/\"//g;
	$res = 1;  # we got a response, return 1 after querying for the other oids
	$$hosts_ref{'host'}{$MYNAME}{'info'}{'sysDescr'} = $rtn;
    } else {
	return 0;
    }

    # display some host-info for nice logging..
    foreach my $oidname (@oids) {
	next if ($oidname eq 'sysDescr'); # already queried

	my $rtn = snmp_query_agent ($session, $oidname, $$name2oid_ref{$oidname}, $logfun);

	next unless ($rtn);

	$rtn =~ s/\"//g;
	$$hosts_ref{'host'}{$MYNAME}{'info'}{$oidname} = $rtn;
    }

    return $res;
}

#  subroutine for querying the snmp agents (default for our checks)
#
sub snmpStdQuery {
    my $session = shift;
    my $oidName = shift;
    my $log = shift;

    my $oid = $name2oid{$oidName};

    my $rtn = snmp_query_agent ($session, $oidName, $oid, $log);

    if (defined ($rtn)) {
	if ($rtn eq 'noSuchObject' or $rtn eq 'noSuchInstance') {
	    return 0;
	}
	return 1;
    } else {
	return 0;
    }
}
