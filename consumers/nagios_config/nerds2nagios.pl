#!/usr/bin/env perl
#
# Produce Nagios-configuration based on a whole lot of NERDS producers.
#
# Copyright (c) 2010, Avdelningen för IT och media, Stockholm university
# See the file LICENSE for full license.
#


=head1 NAME

nerds2nagios.pl -- Generate Nagios host and service configuration from a
number of sources.

=head1 SYNOPSIS

nerds2nagios.pl -o master -D output-dir/ -J ~/path/to/merge_nerds/json/ /path/to/cfg/su-hosts.txt

For complete usage information :

nerds2nagios.pl -h

=head1 DESCRIPTION

Stockholm university monitors 10,000 services on 1,500 devices (servers, switches, routers etc.) -
it is unthinkable to manage Nagios configuration files on that scale.

We've generated Nagios configuration from a text file of simple format (su-hosts.txt) for years,
and have added various ways of auto-configuring Nagios for new switches, wireless access points etc.

The latest development (November 2010) is to introduce a new structured format for data about
devices, which we turn into Nagios configuration. This is called NERDS an can be found at

  http://github.com/fredrikt/nerds

In NERDS, you can have any number of producers of data, and cosumers such as this script.

One producer fetches data from HOSTDB (Stockholm university host management system, can be
found at http://github.com/fredrikt/hostdb), another one from cfgstore (another internal system),
a third using NMAP to port scan all our server networks every night to automatically configure
Nagios monitoring of *ALL* services.

=head1 PROGRAMMERS DOCUMENTATION

=cut

use strict;
use Socket;
use FileHandle;
use Getopt::Long;
use Data::Dumper;
use JSON;

my @saved_argv = @ARGV;

my $help;
my $debug;
my $dry_run;
my $disable_hostdb;
my $nerds_json_dir;
my $output_dir;
my $master_output_fn;
my $slave_files;
my $no_auto_open_ports;

Getopt::Long::Configure ("bundling");
GetOptions(
    'h'         => \$help,		'help'          	=> \$help,
    'd'         => \$debug,             'debug'  	      	=> \$debug,
    'n'		=> \$dry_run,		'dry-run'		=> \$dry_run,
    'N'		=> \$disable_hostdb,	'disable-hostdb'	=> \$disable_hostdb,
    'J:s'	=> \$nerds_json_dir,	'nerds-json-dir:s'	=> \$nerds_json_dir,
    'D:s'	=> \$output_dir,	'output-dir:s'		=> \$output_dir,
    'o:s'	=> \$master_output_fn,	'master-file:s'		=> \$master_output_fn,
    'S:s'	=> \$slave_files,	'slave-files:s'		=> \$slave_files,
					'no-auto-open-ports'	=> \$no_auto_open_ports,
    );

warn ("$0: No JSON directory specified\n\n") unless ($nerds_json_dir);

if (defined ($help) or (@ARGV) or ! $nerds_json_dir) {
    die(<<EOT);
Syntax: $0 -J dir [options]

    Options :
	-d		debug
	-n		dry run
	-N		don\'t access HOSTDB
	-J dir		NERDS JSON dir to load
	-D dir		output directory
	-o fn		master node configuration filename
	-S fn,fn 	slave servers configiration filenames
	--no-auto-open-ports		Disable monitoring of open ports found

EOT
}

my %nerds_control;
$nerds_control{'no-auto-open-ports'} = defined ($no_auto_open_ports);

my $nagios_version = 30;
my $master_freshness_check = 'service-is-stale';

my $hostdb;
if (! $disable_hostdb) {
    $hostdb = eval {
	require HOSTDB;

	my $hostdbini = Config::IniFiles->new (-file => HOSTDB::get_inifile ());

	HOSTDB::DB->new (ini => $hostdbini,
			 debug => 0
	    );
    };

    if ($@) {
	die ("$0: Could not initialize HOSTDB. If you do not want to use HOSTDB, " .
	     "retry with the '-N' argument.\n\n" . $@);
    }
}


# hosts and groups are for data read from $hostsfile,
my (%hosts, %groups);

read_nerds_json_dir ($nerds_json_dir, \%hosts, \%groups, $debug, $hostdb, \%nerds_control) or
    die ("$0: Failed loading NERDS data from dir '$nerds_json_dir'\n");

warn_no_nerds (\%hosts, $debug);

my %aux_groups;
build_auxillary_groups (\%hosts, \%aux_groups, $debug);

my %service_groups;
build_service_groups (\%hosts, \%service_groups, $debug);

my ($hostname) = `hostname -f`;
chomp ($hostname);
if ($hostname eq 'sauron.it.su.se') {
    warn ("\nDisabling master-check-freshness on Sauron\n");
    $master_freshness_check = '';
}
my $argv_str = join (' ', @saved_argv);
# hack to not get artificial changes because of new temp file names being used every time -
# replaces PID with $$
$argv_str =~ s/\.\d+\.tmp/\.\$\$\.tmp/og;
my ($whoami) = `whoami`;
chomp ($whoami);
write_nagios_config ($output_dir,
		     $master_output_fn,
		     $slave_files,
		     \%hosts,
		     \%groups,
		     \%aux_groups,
		     \%service_groups,
		     $debug,
		     $dry_run,
		     $whoami,
		     $hostname,
		     $argv_str,
		     $master_freshness_check
    ) or die ("$0: Failed writing nagios config\n");

exit (0);


=head2 read_nerds_json_dir

   read_nerds_json_dir ($input_dir, $hosts_ref, $groups_ref, $debug, $hostdb,
			$nerds_control_ref);

   Load all NERDS data in $input_dir, and add automatic monitoring of any host
   and service found there that is not allready explicitly monitored (through
   su-hosts.txt that is).

=cut
sub read_nerds_json_dir
{
    my $input_dir = shift;
    my $hosts_ref = shift;
    my $groups_ref = shift;
    my $debug = shift;
    my $hostdb = shift;
    my $nerds_control_ref = shift;

    if (! $input_dir) {
	warn ("No NERDS directory provided\n") if ($debug);
	return 1;
    }

    my @files = get_nerds_data_files ($input_dir);

    die ("$0: Found no NERDS data files in '$input_dir'\n") unless (@files);

    warn ("Found " . 0 + @files . " NERDS files in '$input_dir'\n") if ($debug);

    if (@files) {
	warn ("Loading files in directory '$input_dir'...\n") if ($debug);

	my %stats;

	foreach my $file (@files) {
	    warn ("  file '$file'\n") if ($debug);
	    nerds_process_file ("$input_dir/$file", $hosts_ref, $groups_ref, $debug, $hostdb, \%stats,
				$nerds_control_ref);
	}

	warn ("NERDS stats :\n" . Dumper (\%stats) . "\n\n") if ($debug);
    }

    return 1;
}

=head2 get_nerds_data_files

   @files = get_nerds_data_files ($dir);

   Get a list of all potential NERDS data files in a directory. Does not
   actually parse them to verify they are NERDS data files. The returned
   file names are relative to $dir.

=cut
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

    return (sort (@files));
}

=head2 nerds_process_file

   nerds_process_file ($filename, $hosts_ref, $groups_ref, $debug, $hostdb, $stats_ref,
		       $nerds_control_ref);

   Read, parse and process a potential NERDS data file. In effect, this is the
   top level function for adding automatic monitoring of a single host.

=cut
sub nerds_process_file
{
    my $filename = shift;
    my $hosts_ref = shift;
    my $groups_ref = shift;
    my $debug = shift;
    my $hostdb = shift;
    my $stats_ref = shift;
    my $nerds_control_ref = shift;

    open (IN, "< $filename") or die ("$0: Could not open '$filename' for reading : $!\n");
    my $json = join ('', <IN>);
    close (IN);

    my $t;

    $t = JSON->new->utf8->decode ($json);

    #warn ("DECODED : " . Dumper ($t) . "\n") if ($debug);

    my $nerds_version = $$t{'host'}{'version'};
    my $hostname = $$t{'host'}{'name'};

    if ($nerds_version != 1) {
	die ("$0: Can't interpret NERDS data of version '$nerds_version' in file '$filename'\n");
    }

    if (defined ($hostdb) and ! $hostdb->clean_hostname ($hostname)) {
	warn ("ERROR: Bad hostname '$hostname' in NERDS file $filename - skipping\n");
	next;
    }

    warn ("Loaded host '$hostname' from file '$filename'\n") if ($debug);
    $$hosts_ref{$hostname}{'nerds_data'} = $t;

    my $ip = get_hostdb_attr ('ip', $hostname, $hosts_ref);
    if (! $ip and $$t{'host'}{'addrs'}) {
	$ip = @{$$t{'host'}{'addrs'}}[0];
    }
    set_host_ip ($hostname, $ip, $hosts_ref);

    my $group = $$t{'host'}{'monitoring'}{'nagios'}{'group'}{'name'} || 'serverdrift-auto';
    my $admin = $$t{'host'}{'monitoring'}{'nagios'}{'group'}{'admin'} || 'serverdrift-admins';
    my $desc  = $$t{'host'}{'monitoring'}{'nagios'}{'group'}{'description'} || 'Auto-discovered devices';

    if ($$t{'host'}{'SU_CiscoSNMP'} or
	$$t{'host'}{'nmap_services_NetworkDevices'}) {
	# Do not put auto discovered network devices in 'serverdrift' groups
	my $t;
	# Divide network devices into three groups
	if (lc ($hostname) =~ /^[a-h]/o) {
	    $t = '1';
	} elsif (lc ($hostname) =~ /^[i-p]/o)  {
	    $t = '2';
	} else {
	    $t = '3';
	}
	$group = 'network-devices-' . $t;
	$admin = 'misc-noc-admins';
	$desc  = 'Network devices ' . $t;
    }

    unless ($$groups_ref{$group}) {
	add_group ($groups_ref, $group, $admin, $desc);
    }

    my $hostcheck = $$t{'host'}{'monitoring'}{'nagios'}{'hostcheck'} || 'check-host-alive';
    add_host ($hosts_ref, $hostname, $group, $hostcheck);

    if ($desc eq 'Network devices.') {
	# Backwards compatibility
	add_check ($hosts_ref, $hostname, 'check_ping_placeholder');
    }

    #
    # MANUALLY CONFIGURED CHECKS (from su-hosts.txt)
    #
    my $nagios_mon_ref = $$t{'host'}{'monitoring'}{'nagios'}{'checks'};
    nerds_add_manual_checks ($hostname, $hosts_ref, $stats_ref, $debug, $nagios_mon_ref);

    if (! get_service_count ($hosts_ref, $hostname)) {
	warn ("No manual checks of '$hostname'\n") if ($debug);
    }

    #
    # AUTOMATIC CHECKS (from various NERDS producers: nagios_nrpe, nagios_nrpe, SU_CiscoSNMP
    #                   and possibly more if this comment gets outdated)
    #
    nerds_add_automatic_checks ($hostname, $hosts_ref, $stats_ref, $debug, $t, $nerds_control_ref);


    # REMOVE CERTAIN HOSTS AGAIN

    my $candidate = 0;
    # don't do automatic service monitoring for strictly development hosts

    $candidate = 1 if ($hostname =~ /\.dev\.it\.su\.se\.*$/o);
    $candidate if ($hostname =~ /\.dev\.it\.secure\.su\.se\.*$/o);

    # don't auto-monitor the lab
    my $subnet_desc = get_hostdb_subnet_attr ('description', $hostname, $hosts_ref) || '';
    $candidate = 1 if ($subnet_desc =~ /labb/i);

    if ($candidate and ! get_service_count ($hosts_ref, $hostname)) {
	warn ("Removing dev/lab host '$hostname' without services.\n") if ($debug);
	remove_host ($hosts_ref, $hostname);
    }
}

=head2 nerds_add_automatic_checks

   nerds_add_automatic_checks ($hostname, $hosts_ref, $stats_ref, $debug, $nerds_data,
			       $nerds_control_ref);

   Add monitoring of detected services on $hostname.

   $nerds_data example data structure :

     {
          'host' => {
                      name => 'foo.example.com',
                      'rancid_metadata' => { ... },
                      'SU_HOSTDB' => { ... },
                      'services' => { ... },
                      ...
     };

=cut
sub nerds_add_automatic_checks
{
    my $hostname = shift;
    my $hosts_ref = shift;
    my $stats_ref = shift;
    my $debug = shift;
    my $this = shift;
    my $nerds_control_ref = shift;

    # don't do automatic service monitoring for strictly development hosts
    return undef if ($hostname =~ /\.dev\.it\.su\.se\.*$/o);
    return undef if ($hostname =~ /\.dev\.it\.secure\.su\.se\.*$/o);

    # don't auto-monitor the lab
    my $subnet_desc = get_hostdb_subnet_attr ('description', $hostname, $hosts_ref) || '';
    return undef if ($subnet_desc =~ /labb/i);

    # check if auto-monitoring is opted out for the whole host
    if ($$this{'host'}{'monitoring'}{'nagios'}{'auto_monitoring'}) {
	unless ($$this{'host'}{'monitoring'}{'nagios'}{'auto_monitoring'} == JSON::true()) {
	    warn ("NERDS: auto monitoring of host '$hostname' disabled\n") if ($debug);
	    return undef;
	}
    }

    #
    # DETECTED NRPE SERVICES
    #
    my $nrpe_ref = $$this{'host'}{'nagios_nrpe'};
    nerds_add_nrpe_checks ($hostname, $hosts_ref, $stats_ref, $debug, $nrpe_ref);

    unless ($$nerds_control_ref{'no-auto-open-ports'}) {
	#
	# OPEN PORTS
	#
	nerds_process_open_port_checks ($hostname, $hosts_ref, $stats_ref, $debug);
    }

    #
    # CISCO SNMP
    #
    my $cisco_ref = $$this{'host'}{'SU_CiscoSNMP'}{'checks'};
    nerds_add_cisco_snmp_monitoring ($hostname, $hosts_ref, $cisco_ref, $debug);
}

=head2 nerds_add_manual_checks

   nerds_add_manual_checks ($hostname, $hosts_ref, $stats_ref, $debug, $nrpe_ref);

   Add monitoring of manually configured services on $hostname.

   $nref example data structure :

     {
          'DISK' => {
                     'arguments' => 'check_disk',
                     'command' => 'check_nrpe_1arg'
                    },
          'SSH'  => {
                     'arguments' => '',
                     'command' => 'check_ssh'
                    }
     };

=cut
sub nerds_add_manual_checks
{
    my $hostname = shift;
    my $hosts_ref = shift;
    my $stats_ref = shift;
    my $debug = shift;
    my $nref = shift;

    return unless $nref;

    foreach my $check_descr (sort keys %{$nref}) {
	my $command = $$nref{$check_descr}{'command'};
	my $args = $$nref{$check_descr}{'arguments'};
	my $check = "[$check_descr]" . join ('!', $command, $args);
	# remove trailing !
	$check =~ s/\!$//o;
	add_check ($hosts_ref, $hostname, $check);
    }
}

=head2 nerds_add_nrpe_checks

   nerds_add_nrpe_checks ($hostname, $hosts_ref, $stats_ref, $debug, $nrpe_ref);

   Add automatic monitoring of probed NRPE services on $hostname.

   $nrpe_ref example data structure :

     {
          'check_swap' => { 'working' => 1 },
          'check_load' => { 'working' => 1 }
     };

=cut
sub nerds_add_nrpe_checks
{
    my $hostname = shift;
    my $hosts_ref = shift;
    my $stats_ref = shift;
    my $debug = shift;
    my $nrpe_ref = shift;

    my @nrpe_checks = sort keys %{$nrpe_ref};
    warn ("NRPE checks probed for $hostname : " . join (', ', @nrpe_checks) . "\n") if ($debug);

    foreach my $nrpe (@nrpe_checks) {
	if ($$nrpe_ref{$nrpe}{'working'} == JSON::true ()) {
	    if (is_monitored_nrpe ($hostname, $nrpe, $hosts_ref)) {
		$$stats_ref{'services_monitored'}++;
		#warn ("Auto-detected NRPE $nrpe on $hostname:$port already monitored\n") if ($debug)
	    } else {
		$$stats_ref{'services_NOT_monitored'}++;
		warn ("Auto-detected NRPE $nrpe on $hostname NOT monitored\n") if ($debug);

		if (should_auto_monitor ($$nrpe_ref{$nrpe})) {
		    nerds_add_auto_discovered_nrpe ($hostname, $nrpe, $hosts_ref);
		} else {
		    $$stats_ref{'services_NOT_monitored_and_OPTED_OUT'}++;
		    warn ("OPT-OUT: auto-monitoring of $nrpe on $hostname\n") if ($debug);
		}
	    }
	}
    }

    return 1;
}

=head2 nerds_add_auto_discovered_nrpe

   $nrpe = 'check_disk';
   nerds_add_auto_discovered_nrpe ($hostname, $nrpe, $hosts_ref);

   Add an NRPE check with a description indicating the fact that it was automatically
   set up, and the check name. The result from the example above would be a service
   with description "AUTO disk" and command "check_nrpe_1arg!check_disk".

   NOTE: Currently only supports 1arg NRPE checks.

=cut
sub nerds_add_auto_discovered_nrpe
{
    my $hostname = shift;
    my $nrpe = shift;
    my $hosts_ref = shift;

    my $check;
    if ($nrpe =~ /^check_(.+)/o) {
	$check = "[AUTO $1]check_nrpe_1arg!$nrpe";
    } else {
	$check = "[AUTO $nrpe]check_nrpe_1arg!$nrpe";
    }

    add_check ($hosts_ref, $hostname, $check);
}

=head2 nerds_process_open_port_checks

   nerds_process_open_port_checks ($hostname, $hosts_ref, $stats_ref, $debug);

   Add automatic monitoring of non-monitored services (i.e. open ports) on $hostname.

=cut
sub nerds_process_open_port_checks
{
    my $hostname = shift;
    my $hosts_ref = shift;
    my $stats_ref = shift;
    my $debug = shift;

    my $t = $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'services'};

    foreach my $family (keys %{$t}) {
	foreach my $addr (keys %{$$t{$family}}) {
	    foreach my $proto (keys %{$$t{$family}{$addr}}) {
		foreach my $port (sort keys %{$$t{$family}{$addr}{$proto}}) {
		    my $this = $$t{$family}{$addr}{$proto}{$port};

		    nerds_process_open_port ($proto, $hostname, $port, $this, $hosts_ref, $stats_ref);
		}
	    }
	}
    }
}

=head2 nerds_process_open_port

   $proto = 'tcp';
   nerds_add_nrpe_checks ($proto, $hostname, $port, $service_ref, $hosts_ref, $stats_ref);

   Add automatic monitoring of unmonitored ports on a host.

   If the service is already monitored explicitly (as determined by is_monitored_port (...) ),
   this function won't add any monitoring for it.

   If the service is tcp:5666, it is check_tcp monitored unless there is one or more
   NRPE checks listed for this host (so adding probed NRPE checks should be done before
   this function is called).

   If the service has auto_monitoring == JSON::false, it won't be monitored and a warning
   will be produced.

   $service_ref example data structure :

     {
          'proto'      => 'unknown',
          'version'    => '5.0.87-log',
          'name'       => 'mysql',
          'product'    => 'MySQL',
          'confidence' => '10'
     };

=cut
sub nerds_process_open_port
{
    my $proto = shift;
    my $hostname = shift;
    my $port = shift;
    my $service_ref = shift;
    my $hosts_ref = shift;
    my $stats_ref = shift;

    my $t = $service_ref;

    my $nmap_name = $$t{'name'};

    $$stats_ref{'services_count'}++;

    if ($port == 5666 and $proto eq 'tcp') {
	# if host has any NRPE checks (auto-detected or not), we do not
	# need to check_tcp port 5666.
	my $has_nrpe = 0;
	foreach my $check_descr (keys %{$$hosts_ref{$hostname}{'services'}}) {
	    if ($$hosts_ref{$hostname}{'services'}{$check_descr}{'command'} =~ /^check_nrpe/o) {
		$has_nrpe = 1;
		last;
	    }
	}
	next if ($has_nrpe);
	warn ("WARNING: NRPE available but no standard NRPE checks found on $hostname\n");
    }

    if (is_monitored_port ($proto, $hostname, $port, $service_ref, $hosts_ref)) {
	$$stats_ref{'services_monitored'}++;
	#warn ("Auto-detected '$nmap_name'/$what on $hostname:$port already monitored\n") if ($debug)
    } else {
	$$stats_ref{'services_NOT_monitored'}++;
	warn ("Auto-detected '$nmap_name' on $hostname:$port NOT monitored\n") if ($debug);
	if (should_auto_monitor ($t)) {
	    nerds_add_auto_discovered_port ($proto, $hostname, $port, $service_ref, $hosts_ref);
	} else {
	    $$stats_ref{'services_NOT_monitored_and_OPTED_OUT'}++;
	    warn ("OPT-OUT: auto-monitoring of '$nmap_name' on $hostname:$port\n") if ($debug);
	}
    }
}

=head2 nerds_add_auto_discovered_port

   nerds_add_auto_discovered_port ($proto, $hostname, $port, $service_ref, $hosts_ref);

   Add a check for a discovered service running on a specific port on a host.

   If the service can be identified as one that can be monitored with a specific
   Nagios check (check_ftp, check_ssh, check_http etc.), it will be configured
   to be monitored using that specific check. If not, a standard check_tcp will be
   used (if $proto is 'tcp').

   If the service is identified as something using SSL, a check_certchain will be
   added. Currently ONLY a check_certchain, not a check_smtp and a check_certchain
   for an SSL protected SMTP service for example.

   The check will have a description indicated it was automatically configured.

=cut
sub nerds_add_auto_discovered_port
{
    my $proto = shift;
    my $hostname = shift;
    my $port = shift;
    my $service_ref = shift;
    my $hosts_ref = shift;

    my %port_to_check = (
	21	=>	'[AUTO ftp]check_ftp',
	22	=>	'[AUTO ssh]check_ssh',
	23	=>	'[AUTO telnet]check_telnet',
	25	=>	'[AUTO smtp]check_smtp',
	49	=>	'[AUTO tacacs]check_tacacs',
	80	=>	'[AUTO http]check_httpname',
	389	=>	'[AUTO ldap]check_ldap',
	3306	=>	'[AUTO mysql]check_mysql_su'
	);

    my $port_int = int ($port);
    my $nmap_name = $$service_ref{'name'};
    my $tunnel_proto = $$service_ref{'tunnel'};

    if ($port_to_check{$port_int}) {
	add_check ($hosts_ref, $hostname, $port_to_check{$port_int});
    } else {
	if ($proto eq 'tcp' and $port_int == 1311 and $tunnel_proto eq 'ssl') {
	    # Dell OpenManage running on this host. Can't do check_certchain because they
	    # often have expired certs. Check the login page.
	    my $check = "[AUTO Dell OpenManage]check_ssl_web_page_re!1311!/servlet/OMSALogin!OpenManage";
	    add_check ($hosts_ref, $hostname, $check);
	    return 1;
	}

	if ($proto eq 'tcp') {
	    my $check;
	    if ($tunnel_proto eq 'ssl') {
		# nmap figured out there is an SSL server running on this port. Check certificate.
		$check = "[AUTO ssl certchain/${nmap_name}/${port_int}]check_certchain!${port_int}";
	    } else {
		# Use special description for HTTP service running on HTTPS port (common problem)
		if ($port_int == 443 and $nmap_name eq 'http') {
		    $check = "[AUTO HTTP on HTTPS-port/${port_int}]check_http_port!${port_int}";
		} else {
		    # Do plain check_tcp for all ports where we couldn't figure out anything
		    # more intelligent to do.

		    $check = "[AUTO ${nmap_name}/${port_int}]check_tcp!${port_int}";
		}
	    }
	    add_check ($hosts_ref, $hostname, $check);
	} else {
	    warn ("Auto-monitoring of non-tcp protocol '$proto' NOT IMPLEMENTED yet.\n");
	}
    }
}

=head2 nerds_add_cisco_snmp_monitoring

   nerds_add_cisco_snmp_monitoring ($hostname, $hosts_ref, $groups_ref, $checks_ref, $debug);

   Add monitoring of Cisco SNMP services on $hostname.

   $checks_ref example data structure :

   {
	'MEM_IO_USED' => {
                            'oid'  => '.1.3.6.1.4.1.9.9.48.1.1.1.5.2',
                            'name' => 'ciscoMemoryPoolUsedIO'
			 },
	'CPU_1MIN' =>    {
                            'oid' => '.1.3.6.1.4.1.9.9.109.1.1.1.1.7.1',
                            'name' => 'cpmCPUTotal1minRev'
			 }
   }

=cut
sub nerds_add_cisco_snmp_monitoring
{
    my $hostname = shift;
    my $hosts_ref = shift;
    my $checks_ref = shift;
    my $debug = shift;

    return unless ($checks_ref);

    my %check_types;

    # All the SNMP based checks we support. Left hand side is Nagios check name,
    # right hand side is OID names required for that check.
    $check_types{'CPU_1MIN'} = ['CPU_1MIN'];
    $check_types{'CPU_5MIN'} = ['CPU_5MIN'];
    $check_types{'MEM_CPU'} = ['MEM_CPU_USED','MEM_CPU_FREE'];
    $check_types{'MEM_IO'} = ['MEM_IO_USED','MEM_IO_FREE'];
    $check_types{'Fan'} = ['Fan'];
    $check_types{'PSU'} = ['PSU'];
    $check_types{'Console'} = ['Console'];
    $check_types{'Wlan_if'} = ['Wlan_if'];

    my %agent_supports;

    my @checks = ('check_ping_placeholder');

    my $snmp_env_added = 0;

    foreach my $checkname (sort keys %check_types) {
	if (snmp_check_is_available ($checkname, $checks_ref, \%check_types)) {
	    if ($checkname eq 'Fan' or
		$checkname eq 'PSU') {
		unless ($snmp_env_added) {
		    push (@checks, "[ENVIRONMENT]check_cisco_env!$hostname");
		    $snmp_env_added = 1;
		};
		next;
	    }
	    ($checkname eq 'Console') && do {
		push (@checks, "[$checkname]check_cisco_vty!$hostname");
		next;
	    };
	    ($checkname eq 'Wlan_if') && do {
		if ($hostname =~ /^ap/o and $hostname !~ m/wds/o ) {
		    push (@checks, "[$checkname]check_cisco_wlan!$hostname");
		}
		next;
	    };

	    # default fallback, standard check_cisco check..
	    my $warn = get_default_limit ($checkname, 'WARNING');
	    my $crit = get_default_limit ($checkname, 'CRITICAL');
	    push (@checks, "[$checkname]check_cisco!$checkname!$hostname!$warn!$crit");
	}
    }

    my $service_count = 0 + @checks;
    warn ("No SNMP services to check on $hostname\n") if (! @checks);

    foreach my $check (@checks) {
	add_check ($hosts_ref, $hostname, $check);
    }

    return 1;
}

=head2 snmp_check_is_available

   if (snmp_check_is_available ('CPU_1MIN', $checks_ref, $check_types_ref)) {
       ...
   }

   Check if all required OIDs for a check is available for this agent.
   Return 1 if check is possible, 0 if not.

   $checks_ref is a reference to a hash like

   $VAR1 = {
          'MEM_IO_USED' => '3417168',
          'CPU_1MIN' => '0',
          'MEM_IO_FREE' => '9165744',
	   ...
        }

   Key is an OID name, and value is the retreived value.

   $check_types_ref is a reference to a hash like

   $VAR1 = {
          'CPU_1MIN' => [ 'CPU_1MIN' ],
          'MEM_IO' =>   [ 'MEM_IO_USED', 'MEM_IO_FREE' ],
	   ...
        }

   Key here is a Nagios check name, and value is a list of
   OID names that are required for that check.

=cut
sub snmp_check_is_available
{
    my $check_name = shift;
    my $checks_ref = shift;
    my $check_types_ref = shift;

    my @required_names = @{$$check_types_ref{$check_name}};

    foreach my $t (@required_names) {
	return 0 unless defined ($$checks_ref{$t});
    }

    return 1;
}

sub get_default_limit
{
    my $checkname = shift;
    my $type = shift;

    my %check_default_limits = (

	'CPU_1MIN'	=> { 'WARNING' => '90', 'CRITICAL' => '100' },
	'CPU_5MIN'	=> { 'WARNING' => '89', 'CRITICAL' => '90'  },
	'MEM_CPU'	=> { 'WARNING' => '90', 'CRITICAL' => '95'  },
	'MEM_IO'	=> { 'WARNING' => '85', 'CRITICAL' => '95'  },

	);

    return $check_default_limits{$checkname}{$type};
}

=head2 is_monitored_nrpe

    if (is_monitored_nrpe ($hostname, 'check_nrpe_1arg!check_disk', $hosts_ref)) {
        print ("Yes, disk is monitored.\n");
    }

    Check if a specific NRPE check is configured for $hostname. Checks for
    both check_nrpe and check_nrpe_1arg checks.

=cut
sub is_monitored_nrpe
{
    my $hostname = shift;
    my $what = shift;
    my $hosts_ref = shift;

    foreach my $s_desc (keys %{$$hosts_ref{$hostname}{'services'}}) {
	my $cmd = $$hosts_ref{$hostname}{'services'}{$s_desc}{'command'};
	next unless ($cmd eq 'check_nrpe_1arg' or $cmd eq 'check_nrpe');
	my $args = $$hosts_ref{$hostname}{'services'}{$s_desc}{'args'};

	my @argl = split ('!', $args);

	return 1 if ($argl[0] and $argl[0] eq $what);
    }

    return 0;
}

=head2 is_monitored_port

    if (is_monitored_port ($proto, $hostname, $port, $service_ref, $hosts_ref)) {
        print ("Yes, port $port is monitored.\n");
    }

    Check if a specific port on $hostname is being monitored. Does this by
    checking for either a check_tcp (if $proto is 'tcp') for this port, or
    some other check known to check a specific port (for example check_ssh).

=cut
sub is_monitored_port
{
    my $proto = shift;
    my $hostname = shift;
    my $port = shift;
    my $service_ref = shift;
    my $hosts_ref = shift;

    my $port_int = int ($port);
    my $tunnel_proto = $$service_ref{'tunnel'};

    my %checks_with_static_port = (
	'check_ftp'		=> 21,
	'check_ssh'		=> 22,
	'check_telnet'		=> 23,
	'check_smtp'		=> 25,
	'check_tacacs'		=> 49,
	'check_http'		=> 80,
	'check_ldap'		=> 389,
	'check_ldap_su'		=> 389,
	'check_ldap_connections' => 389,
	'check_https'		=> 443,
	'check_cvspserver'	=> 2401,
	'check_mysql_su'	=> 3306,
	'check_terminalserver'	=> 3389,
	'check_nrpe_1arg'	=> 5666,


	# netsaint statd checks
	'remote_check_disk'	=> 1040,
	'remote_check_filesizeindir' => 1040,
	'remote_check_load'	=> 1040,
	'remote_check_mem'	=> 1040,
	'remote_check_ntp'	=> 1040,
	'remote_check_procs'	=> 1040,
	'remote_check_proctime'	=> 1040,
	'remote_check_swap'	=> 1040

    );

    my @checks_with_port_arg_first = (
	'check_tcp',
	'check_ssh_port',
	'check_https_port',
	'check_certchain',
	'check_ssl',
	'check_spocp',
	'check_web_page'
	);

    foreach my $s_desc (keys %{$$hosts_ref{$hostname}{'services'}}) {
	my $cmd = $$hosts_ref{$hostname}{'services'}{$s_desc}{'command'};
	my $args = $$hosts_ref{$hostname}{'services'}{$s_desc}{'args'};

	if ($checks_with_static_port{$cmd}) {
	    return 1 if ($port_int == $checks_with_static_port{$cmd});
	}

	my @argl = split ('!', $args);

	my ($grep_res) = grep { $cmd } @checks_with_port_arg_first;
	if ($grep_res) {
	    return 1 if ($argl[0] and $argl[0] eq $port);
	}
    }

    return 0;
}

=head2 should_auto_monitor

    if (should_auto_monitor ($service_ref)) {
        # add monitoring
    }

    Verifies that $service_ref should be automatically monitored. We currently
    employ OPT-OUT of auto-monitoring, so this is effectively done by checking that
    $$service_ref{'auto_monitoring'} is not actively set to JSON::true.

=cut
sub should_auto_monitor
{
    my $t = shift;

    if (defined ($$t{'auto_monitoring'})) {
	return ($$t{'auto_monitoring'} == JSON::true ());
    }

    # We do OPT-OUT of auto-monitoring. Not defined here means we should auto-monitor.
    return 1;
}

=head2 warn_no_nerds

    warn_no_nerds ($hosts_ref, $debug)

    Prints a warning (to stderr) about all hosts in $hosts_ref not having NERDS data.

=cut
sub warn_no_nerds
{
    my $hosts_ref = shift;
    my $debug = shift;

    foreach my $h (sort keys %$hosts_ref) {
	unless ($$hosts_ref{$h}{'nerds_data'}) {
	    warn ("No NERDS data for $h\n");
	}
    }
}

=head2 build_auxillary_groups

    build_auxillary_groups ($hosts_ref, $aux_ref, $debug)

    Add hosts to zero or more auxillary Nagios Hostgroups. Examples of
    auxillary host groups are per-subnet, per-Linux-distro, virtual or
    physical, Cisco IOS version etc.

=cut
sub build_auxillary_groups
{
    my $hosts_ref = shift;
    my $aux_ref = shift;
    my $debug = shift;

    foreach my $hostname (sort keys %{$hosts_ref}) {
	my $goldenname = get_goldenname ($hostname, $hosts_ref);

	my $subnet_desc = get_hostdb_subnet_attr ('description', $hostname, $hosts_ref);
	if ($subnet_desc) {
	    my $subnet_id = get_hostdb_attr ('subnet_id', $hostname, $hosts_ref);
	    my $t = "aux-subnet-${subnet_id}-${subnet_desc}";
	    utf8::downgrade ($t);
            $t =~ s/[\xe5\xe4]/a/og;	# a-ring and a-umlaut
            $t =~ s/[\xf6]/o/og;	# o-umlaut
            $t =~ s/[\xc5\xc4>]/A/og;	# capital a-ring and a-umlaut
            $t =~ s/[\xd6]/O/og;	# capital o-umlaut

	    # Nagios is picky about allowed characters in the group name.
	    $t =~ s/[^\w\.-]/_/go;

	    utf8::encode ($subnet_desc);

	    add_aux_group ($hostname, $aux_ref, $t, $subnet_desc);

	    if ($subnet_desc =~ /B2/o) {
		add_aux_group ($hostname, $aux_ref, 'aux-location-B2', 'Placerad i B2');
	    }

	    if ($subnet_desc =~ /NY/o) {
		add_aux_group ($hostname, $aux_ref, 'aux-location-NY', 'Placerad i NY');
	    }
	}

	if ($goldenname =~ /Cisco/oi) {
	    # Skip any non- Cisco-IOS and Cisco-CatOS
	    next if ($goldenname !~ /Cisco\-/);
	}

	# skip empty goldenname until we have rancid id of network devices
	next unless ($goldenname);

	if (is_virtual ($hostname, $hosts_ref)) {
	    add_aux_group ($hostname, $aux_ref, 'aux-virtual-servers', 'Virtual servers');
	} else {
	    add_aux_group ($hostname, $aux_ref, 'aux-physical-servers', 'Physical servers');
	}

	if ($goldenname) {
	    my $groupname = 'aux-' . $goldenname;
	    $groupname =~ s/\s/_/o;	# replace spaces with underscore
	    add_aux_group ($hostname, $aux_ref, $groupname, $goldenname);
	}

	if ($$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_nagios_metadata'}) {
	    next unless ($$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_nagios_metadata'}{'aux_hostgroups'});

	    my @groups = @{$$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_nagios_metadata'}{'aux_hostgroups'}};
	    foreach my $g (@groups){
		my $desc = $g;
		$desc = ucfirst ($1) if ($g =~ /^aux-(.+)$/);
		add_aux_group ($hostname, $aux_ref, $g, $desc);
	    }
	}

    }
}

=head2 add_aux_group

    add_aux_group ($hostname, $aux_ref, $group_name, $group_description)

    Create an auxillary Nagios Hostgroup if it does not already exist, and
    add $hostname to it's list of members.

=cut
sub add_aux_group
{
    my $hostname = shift;
    my $aux_ref = shift;
    my $g_name = shift;
    my $g_desc = shift;

    $$aux_ref{$g_name}{'desc'} = $g_desc;
    $$aux_ref{$g_name}{'members'}{$hostname} = 1;
}

=head2 build_service_groups

    build_service_groups ($hosts_ref, $serviegroups_ref, $debug)

    Add services on hosts to zero or more Nagios service roups. Examples
    of service groups are our products (Mondo, SISU).

=cut
sub build_service_groups
{
    my $hosts_ref = shift;
    my $servicegroups_ref = shift;
    my $debug = shift;

    foreach my $hostname (sort keys %{$hosts_ref}) {
	if ($$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_nagios_metadata'}) {
	    next unless ($$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_nagios_metadata'}{'service_groups'});
	    my @service_regexps = keys %{$$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_nagios_metadata'}{'service_groups'}};
	    foreach my $regexp (sort @service_regexps){

		foreach my $service (sort keys %{$$hosts_ref{$hostname}{'services'}}) {
		    if ($service =~ /$regexp/) {
			my @groups = @{$$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_nagios_metadata'}{'service_groups'}{$regexp}};
			foreach my $group (@groups) {
			    $$servicegroups_ref{$group}{$hostname}{$service} = 1;
			}
		    }
		}
	    }
	}
    }
}

=head2 write_nagios_config

    write_nagios_config ($output_dir, $master_output_fn, $slave_output_fns,
		         $hosts_ref, $groups_ref, $aux_ref,
			 $servicegroups_ref,
			 $debug, $dry_run, $whoami, $hostname, $argv_str,
			 $master_freshness_check)

    Top level function for creating Nagios configuration.

    If $slave_output_fns is given ("file1,file2,..."), Nagios Hostgroups will
    be distributed over the slave server configuration files as even as
    possible, within reason. This means we will check how many services are
    checked in all Hostgroups, and try to give each slave server an equal
    portion of the work load.

    Auxillary host groups are ONLY written to the master server configuration
    file, since we use them for presentation purposes only.

    Service groups are ONLY written to the master server configuration
    file, since we use them for presentation/notification purposes only.

    $whoami, $hostname and $argv_str are used to provide information about
    how the output file(s) were generated as comments only.

    If $master_freshness_check is set, the master file will have all it's
    checks defined to use this check command rather than the real ones. This
    is used to make the master show a 'service is stale' warning when a
    service result has not been received from one of the slave servers in
    a reasonable amount of time.

=cut
sub write_nagios_config
{
    my $output_dir = shift;
    my $master_output_fn = shift;
    my $slave_output_fns = shift;
    my $hosts_ref = shift;
    my $groups_ref = shift;
    my $aux_ref = shift;
    my $servicegroups_ref = shift;
    my $debug = shift;
    my $dry_run = shift;
    my $whoami = shift;
    my $hostname = shift;
    my $argv_str = shift;
    my $master_freshness_check = shift;

    my $exitstat = 1;
    $master_output_fn = '-' if (! $master_output_fn or $dry_run);

    my %output_grouping;
    # figure out what groups should be written to what files
    get_files_and_groups ($master_output_fn, $slave_output_fns, $groups_ref, $hosts_ref, \%output_grouping, $debug);

    my %warned_about;

    foreach my $file (sort keys %output_grouping) {
	my $is_master_file = 0;
	$is_master_file = 1 if ($file eq $master_output_fn);

	my $fn = $file;
	$fn = $output_dir . "/" . $file if ($output_dir and $fn ne '-');

	my %defined_contactgroups;

	my $fhandle = new FileHandle;
	open ($fhandle, "> $fn") or die ("$0: Could not open output file '$fn' for writing : $!");

	print ("\n\nWhat would have been written to file if this was not a dry run :\n\n") if ($dry_run);

	my $now = localtime();

	print ($fhandle <<EOT);
# AUTO GENERATED FILE, DO NOT EDIT
#
# Generated by $0 running as $whoami\@$hostname.
#
# Command line : $0 $argv_str
#
# Table of contents :
#
EOT
        # first one pass through everything to just print the ToC (valuable to make
        # commit mails readable)
        my ($g_count, $h_count, $s_count) = (0, 0, 0);
	foreach my $g (sort @{$output_grouping{$file}{groups}}) {
	    $g_count++;
	    print ($fhandle "#  Hostgroup $g\n");
	    foreach my $h (sort keys %{$hosts_ref}) {
		my $hosts_group = $$hosts_ref{$h}{'group'};

		unless ($hosts_group) {
		    warn ("ERROR: Host '$h' has no group!\n" . Dumper ($$hosts_ref{$h}) . "\n");
		    # We get false positives about this when accessing hash elements that don't exist :(
		    delete($hosts_ref->{$h});
		    $hosts_group = '';
		}

		next unless ($hosts_group eq $g);

		if (! get_service_count ($hosts_ref, $h)) {
		    # nagios complains if there are no services associated with a host. use
		    # a dummy extra ping check as a placeholder.
		    add_check ($hosts_ref, $h, 'check_ping_placeholder');

		    warn ("Using dummy ping-service as placeholder on host without services : '$h'\n") if ($debug);
		}

		$h_count++;
		foreach my $check (sort keys %{$$hosts_ref{$h}{'services'}}) {
		    $s_count++;
		    my $cmd = $$hosts_ref{$h}{'services'}{$check}{'command'};
		    my $args = $$hosts_ref{$h}{'services'}{$check}{'args'} || '';
		    printf ($fhandle "#    %-30s %-30s %s %s\n", $h, $check, $cmd, $args);
		}
	    }
        }

	printf ($fhandle <<EOT);
#
# Summary : $s_count services on $h_count hosts in $g_count groups.
#
# End table of contents

EOT

	foreach my $g (sort @{$output_grouping{$file}{groups}}) {
	    my $group_admin = $$groups_ref{$g}{admin};
	    my $group_desc = $$groups_ref{$g}{desc};
	    my @group_members;

	    warn ("Group \"$g\" to file $file\n") if ($debug);

	    print ($fhandle "# GROUP $g :\n\n");

	    foreach my $h (sort keys %{$hosts_ref}) {
		warn ("$0: Ignoring invalid hostname '$h'\n"), next if (defined ($hostdb) and ! $hostdb->clean_hostname ($h));

		my $hosts_group = $$hosts_ref{$h}{'group'};

		if ($hosts_group eq $g) {
		    push (@group_members, $h);
		    print ($fhandle "#\n# HOST $h :\n#\n");

		    my $ip = get_host_ip ($h, $hosts_ref);

		    if (! $ip) {
			warn ("Host '$h' could not be resolved!\n") unless ($warned_about{$h});
			$warned_about{$h} = 1;
			# Use hostname instead of IP when no IP can be found. DNS might be updated later than Nagios.
			$ip = $h;
		    }

		    print_host ($hosts_ref, $h, $ip, $group_admin, $fhandle) or warn ("$0: Failed writing host to file '$file'\n"), return undef;

		    my $check_command_override = '';
		    if ($is_master_file and $master_freshness_check) {
			$check_command_override = $master_freshness_check;
		    }

		    foreach my $check (sort keys %{$$hosts_ref{$h}{'services'}}) {
			print_host_service ($hosts_ref, $h, $check, $group_admin, $fhandle,
					    $check_command_override) or
			    warn ("$0: Failed writing host services to file '$file'\n"), return undef;
		    }
		}
	    }

	    if (! $defined_contactgroups{$group_admin}) {
		print_contact ($g, $group_admin, $fhandle) or warn ("$0: Failed writing contact to file '$file'\n"), return undef;
		print_contact_group ($g, $group_admin, $fhandle) or warn ("$0: Failed writing contact group to file '$file'\n"), return undef;
		$defined_contactgroups{$group_admin} = 1;
	    } else {
		warn ("Not re-defining contact group $g $group_admin\n") if ($debug);
	    }

	    print_host_group ($g, $group_desc, $group_admin, \@group_members, $fhandle) or warn ("$0: Failed writing host group to file '$file'\n"), return undef;

	    print ($fhandle "\n");
	}

	if ($is_master_file) {
	    print_aux_groups ($aux_ref, $fhandle);
	    print_service_groups ($servicegroups_ref, $fhandle);
	}

	close ($fhandle) unless ($fn eq '-');
    }

    return $exitstat;
}

=head2 get_files_and_groups

    my %output_grouping;
    # figure out what groups should be written to what files
    get_files_and_groups ($master_output_fn, $slave_output_fns, $groups_ref, $hosts_ref, \%output_grouping, $debug);

    Determine what Nagios Hostgroups should be written to what output files.

    All groups are written to the $master_output_fn, and (non-auxillary) Hostgroups are
    distributed over the given $slave_output_fns (comma-separated list of filenames in a string)
    as evenly as possible.

    We strive to let each slave server have an as equal number of services to check as
    the other slave servers, without implementing a full Knapsack algorithm. A simple
    scheme of splitting the hostgroups in half worked for the first six years of Nagios
    monitoring on Stockholm university, so this does not need perfection.

=cut
sub get_files_and_groups
{
    my $master_output_fn = shift;
    my $slave_output_fns = shift;
    my $groups_ref = shift;
    my $hosts_ref = shift;
    my $output_ref = shift;
    my $debug = shift;

    my %services_per_group;
    my $total_count = 0;

    # count number of services per group
    foreach my $g (keys %$groups_ref) {
	my $group_sc = 0;

	# find all host matching this group, and count their services
	foreach my $h (keys %$hosts_ref) {
	    next unless $$hosts_ref{$h}{group} eq $g;

	    my $host_sc = 1;	# count one service for the host check

	    $host_sc += get_service_count ($hosts_ref, $h);

	    $group_sc += $host_sc;
	}

	$services_per_group{$g} = $group_sc;
	$total_count += $group_sc;

	if ($master_output_fn) {
	    # print all groups to $master_output_fn, if one is requested
	    push (@{$$output_ref{$master_output_fn}{groups}}, $g);
	}
    }

    if ($master_output_fn) {
	$$output_ref{$master_output_fn}{service_count} = $total_count;
    }

    warn ("Services per group : \n" . Dumper (\%services_per_group) . "\n") if ($debug);

    if ($slave_output_fns) {
	# figure out how many parts we should divide the output to for the slaves
	my @slave_fns = sort (split (',', $slave_output_fns));

	# Spread the groups over the number of slave configuration files requested.
	# This is a simple algorithm, probably not resulting in optimal distribution.
	# It has been good enough for six years already though.
	#
	# See http://en.wikipedia.org/wiki/Knapsack_problem for interesting ideas =).
	my @groups_in_size_order = sort { $services_per_group{$b} <=> $services_per_group{$a} } keys %services_per_group;

	my $services_left = $total_count;

      FILE: while (@slave_fns) {
	  my $slave_file = shift @slave_fns;
	  my $in_this_file = 0;

	  my $ideal = 0;
	  $ideal = int ($services_left / (1 + @slave_fns)) if ($services_left);
	  warn ("Dividing $services_left services into " . (1 + @slave_fns) .
		" slave configuration files (ideally $ideal services per slave)\n") if ($debug);

	  while (@groups_in_size_order) {
	      my $g = $groups_in_size_order[0];

	      my $s = $services_per_group{$g};

	      if (! $in_this_file and $s > $ideal) {
		  # A single group too big for an empty file. Since we can't currently
		  # split groups, we put this group in this file and move on.
		  warn ("Group $g larger than ideal ($s > $ideal). Split group to distribute check load better.\n");
	      } else {
		  if (@slave_fns and ($in_this_file + $s > $ideal)) {
		      warn ("Can't fit group $g with $s services into file $slave_file that already " .
			    "has $in_this_file services in it, advancing.\n") if ($debug);
		      next FILE;
		  }
	      }

	      $in_this_file += $s;
	      $services_left -= $s;

	      warn ("Group $g, $s services, into file $slave_file (new count : $in_this_file)\n") if ($debug);

	      push (@{$$output_ref{$slave_file}{groups}}, $g);
	      $$output_ref{$slave_file}{service_count} += $s;

	      shift @groups_in_size_order;
	  }

	  warn ("All groups distributed\n") if ($debug);
      }
    }

    warn ("File distribution result :\n" . Dumper ($output_ref) . "\n") if ($debug);

    return 1;
}

=head2 print_aux_groups

    print_aux_groups ($aux_ref, $fhandle);

    Print Nagios hostgroup definitions for all auxillary host groups to a file handle.

=cut
sub print_aux_groups
{
    my $aux_ref = shift;
    my $fhandle = shift;

    foreach my $g_name (sort keys %{$aux_ref}) {
	my $desc = $$aux_ref{$g_name}{'desc'};
	my @m = sort keys (%{$$aux_ref{$g_name}{'members'}});
	my $members = join (',', @m);
	my $member_count = '# ' . scalar (@m) . ' members';

	print ($fhandle <<EOH) or warn ("$0: Could not write aux-group to file handle : $!\n"), return 0;
define hostgroup {
	hostgroup_name	$g_name
	alias		$desc
	$member_count
	members		$members
}

EOH
    }

    return 1;
}

=head2 print_service_groups

    print_service_groups ($servicegroups_ref, $fhandle);

    Print Nagios service group definitions for all service groups to a file handle.

=cut
sub print_service_groups
{
    my $servicegroups_ref = shift;
    my $fhandle = shift;

    foreach my $group (sort keys %{$servicegroups_ref}) {
	my $desc = ucfirst ($group);

	my @m;
	foreach my $hostname (sort keys %{$$servicegroups_ref{$group}}) {
	    foreach my $service (sort keys %{$$servicegroups_ref{$group}{$hostname}}) {
		my $this = "\t" . tab_format (3, 'members') . $hostname . ',' . $service;
		push (@m, $this);
	    }
	}

	my $members = join ("\n", @m);
	my $member_count = '# ' . scalar (@m) . ' members';

	print ($fhandle <<EOH) or warn ("$0: Could not write service-group to file handle : $!\n"), return 0;
define servicegroup {
	servicegroup_name	$group
	alias			$desc
	$member_count
$members
}

EOH
    }

    return 1;
}

=head2 print_host

    print_host ($hosts_ref, $hostname, $ip, $group_admin, $fhandle);

    Print a Nagios host definition to a file handle.

=cut
sub print_host
{
    my $hosts_ref = shift;
    my $hostname = shift;
    my $ip = shift;
    my $group_admin = shift;
    my $fhandle = shift;

    my $host_check = $$hosts_ref{$hostname}{'hostalive'};
    $host_check =~ s/\,$//go;

    my $host_name = tab_format (3, 'host_name') . $hostname;
    my $alias = tab_format (3, 'alias') . $hostname;
    my $address = tab_format (3, 'address') . $ip;
    my $check_command = tab_format (3, 'check_command') . $host_check;

    my $contact_groups = '';
    if ($nagios_version >= 20) {
	$contact_groups = tab_format (3, 'contact_groups') . $group_admin;
    }

    my $use = tab_format (3, 'use') . 'SU-generic-host';

    my $notes = '';
    if ($nagios_version >= 30) {
	# Construct a 'notes' section for this host, typically showing host comment from HOSTDB
	# and whether this is a physical or virtual host plus OS distribution information.
	$notes = get_notes_for_host ($hostname, $hosts_ref);
	$notes = tab_format (3, 'notes') . $notes if ($notes);
    }

    my $parents = get_host_parents ($hostname, $hosts_ref);
    $parents = tab_format (3, 'parents') . $parents if ($parents);
    if (! $parents) {
	$parents = '';
	$parents = '# No parent(s) found.' if ($nagios_version >= 30);
    }

    my $icon_image = '';
    my $icon_image_alt = '';
    if ($nagios_version >= 30) {
	($icon_image, $icon_image_alt) = get_icon_image ($hostname, $hosts_ref);
	$icon_image = tab_format (3, 'icon_image') . $icon_image if ($icon_image);
	$icon_image_alt = tab_format (3, 'icon_image_alt') . $icon_image_alt if ($icon_image_alt);
	$icon_image = '# No icon image.' unless ($icon_image);
	$icon_image_alt = '# No alt icon image.' unless ($icon_image_alt);
    }

    print ($fhandle <<EOH) or warn ("$0: Could not write host to file handle : $!\n"), return 0;
define host {
	$use

	$host_name
	$alias
	$address
	$parents
	$check_command
	$contact_groups
	$notes
	$icon_image
	$icon_image_alt
}

EOH

    return 1;
}

=head2 get_notes_for_host

    get_notes_for_host ($hostname, $hosts_ref);

    Construct what 'Notes' we tell Nagios about a host. A human readable
    string with good information about the device being monitored, such as
    comment from HOSTDB (host management system), virtual or physical,
    operating system etc.

=cut
sub get_notes_for_host
{
    my $hostname = shift;
    my $hosts_ref = shift;

    my @res;
    my $comment = get_hostdb_attr ('comment', $hostname, $hosts_ref) ||
	$$hosts_ref{$hostname}{'nerds_data'}{'host'}{'comment'};
    utf8::encode ($comment);
    $comment = 'No HOSTDB comment' if (! $comment or $comment eq 'dns-import');
    push (@res, $comment);

    my $os_info = get_os_info ($hostname, $hosts_ref) || '';

    my $virtual_str = '';
    if (! $os_info or $os_info !~ /Cisco/o) {
	is_virtual ($hostname, $hosts_ref, \$virtual_str);
	push (@res, $virtual_str) if ($virtual_str);
    }

    if ($os_info =~ /^Cisco/o) {
	my $hw_descr = $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'rancid_metadata'}{'hw_description'};
	push (@res, $hw_descr) if ($hw_descr);
    }

    if ($os_info) {
	push (@res, $os_info);
    }

    return (join (', ', @res));
}

=head2 get_icon_image

    get_icon_image ($hostname, $hosts_ref);

    Decide what 40x40 pixels icon image Nagios should use for a host. Penguins
    for Linux, devils for BSD, flags for Windows etc.

=cut
sub get_icon_image
{
    my $hostname = shift;
    my $hosts_ref = shift;

    my @res;

    my $goldenname = get_os_info ($hostname, $hosts_ref);

    # servers
    return ('base/ubuntu.png', $goldenname . ' Linux')	if ($goldenname =~ /^Ubuntu/oi);
    return ('base/linux40.png', $goldenname . ' Linux')	if ($goldenname =~ /^Lunar/oi);
    return ('base/redhat.png', $goldenname . ' Linux')	if ($goldenname =~ /^RedHat/oi);
    return ('base/freebsd40.png', $goldenname)		if ($goldenname =~ /^FreeBSD/oi);
    return ('base/openbsd.gif', $goldenname)		if ($goldenname =~ /^OpenBSD/oi);
    return ('base/linux40.png', $goldenname)		if ($goldenname =~ /^Linux/oi);
    return ('base/mac40.png', $goldenname)		if ($goldenname =~ /Mac OS/oi);
    return ('base/win40.png', $goldenname)		if ($goldenname =~ /Win/oi);

    # network equipment
    if ($goldenname =~ /^Cisco.(IOS|CatOS)/o) {
	my $hw_descr = $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'rancid_metadata'}{'hw_description'};

	return ('base/router40.png', "$hw_descr, $goldenname")	if ($hostname =~ /-gw/oi or $hw_descr =~ /router/o);
	return ('base/switch40.png', "$hw_descr, $goldenname")	if ($hostname =~ /-sw/oi or $hw_descr =~ /switch/o);
	return ('logos/cisco.png',   "$hw_descr, $goldenname wireless access point") if ($hostname =~ /^ap-/oi);
	return ('logos/cisco.png',   "$hw_descr, $goldenname");
    }
    if ($goldenname =~ /Cisco/o) {
	my $hw_descr = $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'rancid_metadata'}{'hw_description'};
	my $alt_text = $goldenname;
	$alt_text = "$hw_descr, $goldenname" if ($hw_descr);
	return ('logos/cisco.png', $alt_text);
    }

    return ('base/router40.png', 'Unknown router')	if ($hostname =~ /-gw/oi);
    return ('base/switch40.png', 'Unknown switch')	if ($hostname =~ /-sw/oi);

    return ('', '');
}

=head2 get_host_parents

    get_host_parents ($hostname, $hosts_ref);

    Nagios host dependency information. If a host is a 'child' of another
    host in HOSTDB, say that the parent is the parent host. Otherwise use
    the default gateway on the subnet as 'parent'. Was an experiment in
    getting a usable service map which did not work out, but is being kept
    since it might prove useful during network outages.

=cut
sub get_host_parents
{
    my $hostname = shift;
    my $hosts_ref = shift;

    my @res;

    # check if host has a parent in HOSTDB
    my $parent_id = get_hostdb_attr ('parent', $hostname, $hosts_ref);
    if ($parent_id) {
	my $parent_name = get_hostdb_attr_by_id ($parent_id, 'hostname', $hostname, $hosts_ref);
	#warn("Found parent of $hostname with id $parent_id : $parent_name\n");
	if (! $$hosts_ref{$parent_name}) {
	    warn ("WARNING: No monitoring of ${hostname}'s parent $parent_name\n");
	    return '';
	}
	return $parent_name if ($parent_name);
    }

    # No HOSTDB parent, use subnet gateway as parent
    my $subnet = get_hostdb_subnet_attr ('name', $hostname, $hosts_ref);
    if ($subnet) {

	if ($subnet =~ /^(\d+\.\d+\.\d+)\.(\d+)\/\d+$/o) {
	    # IPv4 subnet, slash notation (e.g. 130.237.164.0/24)

	    my $base = $1;
	    my $last_octet = $2;

	    my $router_ip = sprintf ("%s.%i", $base, int ($last_octet) + 1);

	    #warn ("Looking for router $router_ip of subnet $subnet\n");

	    # now, brute force search $hosts_ref for $router_ip
	    foreach my $h (keys %{$hosts_ref}) {
		if ($$hosts_ref{$h}{'ip'} eq $router_ip) {
		    #warn ("FOUND router $h\n");
		    if ($h eq $hostname) {
			# Routers can be detected as having themselves as parents
			return '';
		    }
		    return $h;
		}
	    }
	    #warn ("FOUND NO router\n");
	}
    }

    return '';
}

=head2 print_host_service

    print_host_service ($hosts_ref, $hostname, $service_desc, $groupadmin, $fhandle,
			$check_command_override);

    Print a Nagios service definition to a file handle.

    If $check_command_override is set, that command will be used instead of the
    command and arguments stored in $hosts_ref for $service_desc on $hostname.

=cut
sub print_host_service
{
    my $hosts_ref = shift;
    my $hostname = shift;
    my $service_desc = shift;
    my $group_admin = shift;
    my $fhandle = shift;
    my $check_command_override = shift;

    my $cmd = $$hosts_ref{$hostname}{'services'}{$service_desc}{'command'};
    my $args = $$hosts_ref{$hostname}{'services'}{$service_desc}{'args'};

    # interpolating
    my $use = '';
    my $check_command = join ('!', ($cmd, $args));
    $check_command =~ s/\!$//o;

    if ($check_command_override) {
	$check_command = $check_command_override;
    }

    my $opts = '';

    if ($service_desc =~ /PASSIVE/o) {
	# XXX unused I think
	$use = tab_format (3, 'use') . 'SU-generic-volatile-service';
	$check_command = tab_format (3, 'check_command') . 'no-check';
	$opts = tab_format(3,'active_checks_enabled') . '0';
    } else {
	$use = tab_format (3, 'use') . 'SU-generic-service';
	$check_command = tab_format (3, 'check_command') . $check_command;
    }
    my $host_name = tab_format (3, 'host_name') . $hostname;
    my $service_description = tab_format (3, 'service_description') . $service_desc;
    my $contact_groups = tab_format (3, 'contact_groups') . $group_admin;

    print ($fhandle <<EOS) or warn ("$0: Could not write host to file handle : $!\n"), return 0;
define service {
	$use

	$host_name
        $check_command
        $opts
	$service_description
	$contact_groups
}

EOS

    return 1;
}

=head2 print_contact

    print_contact ($hostgroup, $contact, $fhandle);

    Print a Nagios contact definition to a file handle. We fake the e-mail address
    for host groups - notification-handler determines who gets e-mails.

=cut
sub print_contact
{
    my $hostgroup = shift;
    my $contact = shift;
    my $fhandle = shift;

    # interpolating
    my $use = tab_format (3, 'use') . 'SU-generic-contact';
    my $contact_name = tab_format (3, 'contact_name') . "${contact}-contact";
    my $alias = tab_format (3, 'alias') . "Contact for host group '$hostgroup'";
    my $email = tab_format (3, 'email') . "${hostgroup}\@localhost";

    print ($fhandle <<EOC) or warn ("$0: Could not write host to file handle : $!\n"), return 0;
define contact {
	$use

	$contact_name
	$alias
	$email
}

EOC

    return 1;
}

=head2 print_contact_group

    print_contact_group ($hostgroup, $contact, $fhandle);

    Print a Nagios contactgroup definition to a file handle.

=cut
sub print_contact_group
{
    my $hostgroup = shift;
    my $contact = shift;
    my $fhandle = shift;

    # interpolating
    my $contactgroup_name = tab_format (3, 'contactgroup_name') . $contact;
    my $alias = tab_format (3, 'alias') . "Contact group for host group '$hostgroup'";
    my $members = tab_format (3, 'members') . "${contact}-contact";

    print ($fhandle <<EOC) or warn ("$0: Could not write host to file handle : $!\n"), return 0;
define contactgroup {
	$contactgroup_name
	$alias
	$members
}

EOC

    return 1;
}

=head2 print_host_group

    print_host_group ($group, $desc, $group_admin, $members_ref, $fhandle);

    Print a Nagios hostgroup definition to a file handle.

=cut
sub print_host_group
{
    my $group = shift;
    my $desc = shift;
    my $group_admin = shift;
    my $members_ref = shift;
    my $fhandle = shift;

    # interpolating
    my $hostgroup_name = tab_format (3, 'hostgroup_name') . $group;
    my $alias = tab_format (3, 'alias') . $desc;
    my $contact_groups = '';
    if ($nagios_version >= 10 and $nagios_version <= 19) {
	$contact_groups = tab_format (3, 'contact_groups') . $group_admin;
    }
    my $members = tab_format (3, 'members') . join (', ', @$members_ref);

    print ($fhandle <<EOS) or warn ("$0: Could not write host to file handle : $!\n"), return 0;
define hostgroup {
	$hostgroup_name
	$alias
	$contact_groups
	$members
}

EOS

    return 1;
}

=head2 tab_format

    my $left = tab_format ($tab_count, $string);
    print ($left . "\t${right}");

    Used in pretty-printing. Print $string followed by a number of tabs
    reduced with the length of $string, to get neat columns.

=cut
sub tab_format
{
    my $tab_count = shift;
    my $string = shift;

    my $minus_tabs = int (length ($string) / 8);

    return $string . "\t" x ($tab_count - $minus_tabs);
}

=head2 host2ip

    my $ip = host2ip ($hostname);

    Turn hostname into IP address.

=cut
sub host2ip
{
    my $hostname = shift;

    my ($name, $aliases, $addrtype, $length, @addrs) = gethostbyname ($hostname);

    my $ip = join ('.', unpack('C4',$addrs[0]));

    #warn ("Host '$hostname' had to be resolved in DNS ($ip)\n");

    return $ip;
}

=head2 add_check

    add_check ($hosts_ref, $hostname, $check);

    Add a service check to $hostname, avoiding duplicates. We try to avoid showing
    SNMP community etc. in service descriptions.

    $check examples :

	"check_disk"
	"[MY CHECK]check_disk"
	"[special HTTP]!check_https_port!9443"

=cut
sub add_check
{
    my $hosts_ref = shift;
    my $hostname = shift;
    my $check = shift;

    my $description = '';
    $description = $1 if $check =~ s/^\[([^\]]*)\]//o;	# $check has a description inside brackets
    if (!$description && $check =~ /^(remote_)*check_([a-z0-9A-Z\-]+)/go) {
	$description = uc ($2);
	if ($check =~ /!(.+)$/go) {
	    # arguments, add them too (must make description unique for this host)
	    my $t = $1;
	    $t =~ s/!/ /go;
	    $description .= " $t";
	}
    }

    if ($description =~ /^RADIUS probe/o) {
	# the arguments to the radius check are secrets. make sure we don't disclose them
	# in the service name. Add $hostname to make it (more) unique.
	$description = "RADIUS probe of $hostname"
    }

    if ($description =~ /^SNMP\s(\S+?)\s(.+)$/o) {
	# Hide SNMP community given as first argument to this check (check_snmp_process!secret!BungeeService)
	$description = "SNMP $2";
    }

    if ($description =~ /^EQUALLOGIC\s(\S+?)\s(.+)$/o) {
	# Hide SNMP community given as first argument to this check (check_snmp_process!secret!BungeeService)
	$description = "EQL $2";
    }

    if ($description =~ /^NRPE\s+check_(.+)$/o) {
	# Change "NRPE check_disk" -> "DISK" - who cares if NRPE is used?
	$description = uc ($1);
    }

    if ($description =~ /^NRPE\s+(.+)$/o) {
	# Change "NRPE Memory_Load" -> "Memory_Load" - who cares if NRPE is used?
	$description = $1;
    }


    # some characters (complete list not known by me) are illegal for service descriptions
    $description =~ s/%/_/go;

    my $command = $check;
    my $args = '';

    if ($check =~ /^(.+?)!(.+)$/o) {
	$command = $1;
	$args = $2;
    }

    # now, verify description is unique (for this host) - otherwise start appending digits
    if ($$hosts_ref{$hostname}{'services'}{$description}) {
	if ($$hosts_ref{$hostname}{'services'}{$description}{'command'} eq $command and
	    $$hosts_ref{$hostname}{'services'}{$description}{'args'} eq $args) {
	    # this check is a duplicate, just return
	    return 0;
	}

	foreach my $i (2..99) {
	    my $t_desc = "${description}_${i}";
	    if (! $$hosts_ref{$hostname}{'services'}{$t_desc}) {
		$description = $t_desc;
		last;
	    } else {
		if ($$hosts_ref{$hostname}{'services'}{$t_desc}{'command'} eq $command and
		    $$hosts_ref{$hostname}{'services'}{$t_desc}{'args'} eq $args) {
		    # this check is a duplicate, just return
		    return 0;
		}
	    }
	}

	if ($$hosts_ref{$hostname}{'services'}{$description}) {
	    die ("$0: Could not make unique description for check '$check' on host $hostname\n");
	}
    }

    $$hosts_ref{$hostname}{'services'}{$description}{'command'} = $command;
    $$hosts_ref{$hostname}{'services'}{$description}{'args'} = $args;

    $$hosts_ref{$hostname}{'service_count'}++;
}

=head2 get_os_info

    get_os_info ($hostname, $hosts_ref);

    Same as get_goldenname ($hostname, $hosts_ref, 1).

=cut
sub get_os_info
{
    my $hostname = shift;
    my $hosts_ref = shift;

    get_goldenname ($hostname, $hosts_ref, 1);
}

=head2 get_goldenname

    get_goldenname ($hostname, $hosts_ref, $use_os_fingerprint);

    Get the 'golden name' of a host. This is usually an abbreviated string identifying
    the operating system and/or Linux distribution. If no such information has been
    collected (through NERDS), use nmap OS fingerprinting if $use_os_fingerprinting is
    non-zero.

=cut
sub get_goldenname
{
    my $hostname = shift;
    my $hosts_ref = shift;
    my $use_os_fingerprint = shift;

    return undef unless ($$hosts_ref{$hostname});

    # We prefer to identify hosts OS using cfgstore goldenname, since it is almost
    # guaranteed to be correct if present.
    my $goldenname = get_cfgstore_attr ('goldenname', $hostname, $hosts_ref) || '';

    return $goldenname if ($goldenname);

    # get parent host name as fallback lookup entry
    my $parent_id = get_hostdb_attr ('parent', $hostname, $hosts_ref);
    my $parent_name;
    if ($parent_id) {
	$parent_name = get_hostdb_attr_by_id ($parent_id, 'hostname', $hostname, $hosts_ref);
    }

    if ($parent_name) {
	# if no goldenname, and host has parent, check for goldenname of parent
	$goldenname = get_cfgstore_attr ('goldenname', $parent_name, $hosts_ref) || '';
    }

    return $goldenname if ($goldenname);

    if ($$hosts_ref{$hostname}{'nerds_data'}{'host'}{'rancid_metadata'}{'type'} eq 'cisco') {
	# example : "C6MSFC-JSV-M, 12.1(22)E1, EARLY DEPLOYMENT RELEASE SOFTWARE (fc1)"
	my $ios = $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'rancid_metadata'}{'image'}{'software'};
	my $ver = (split (',', $ios))[1];
	if ($ver =~ /^\s*(\d+\.\d+)/o) {
	    return ("Cisco-IOS-$1");
	}
    }

    if ($$hosts_ref{$hostname}{'nerds_data'}{'host'}{'rancid_metadata'}{'type'} eq 'cisco-cat') {
	# example : "C6MSFC-JSV-M, 12.1(22)E1, EARLY DEPLOYMENT RELEASE SOFTWARE (fc1)"
	my $catos = $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'rancid_metadata'}{'image'}{'software'};

	my $ver = (split (' ', $catos))[1];
	if ($ver =~ /^\s*(\d+\.\d+)/o) {
	    return ("Cisco-CatOS-$1");
	}
    }

    if ($use_os_fingerprint) {
	# if still no goldenname, go for nmap OS fingerprint
	$goldenname = $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'nmap_services'}{'os'}{'name'} || '';
	if (! $goldenname and $parent_name) {
	    $goldenname = $$hosts_ref{$parent_name}{'nerds_data'}{'host'}{'nmap_services'}{'os'}{'name'} || '';
	}
    }

    return $goldenname;
}

=head2 is_virtual

    my $str;
    if (is_virtual ($hostname, $hosts_ref, \$str)) {
        print ("YES, is virtual ($str)\n");
    }

    Try to determine if a host is a virtual server or not. If we have
    NERDS cfgstore data 'is_virtual', we consider this certain. If not,
    we look at the MAC address and if it is known to belong to VMWare,
    we say it's probably virtual. We do not handle other hypervisor
    vendors for now.

=cut
sub is_virtual
{
    my $hostname = shift;
    my $hosts_ref = shift;
    my $str_ref = shift;

    my $virtual = get_cfgstore_attr ('is_virtual', $hostname, $hosts_ref);
    if (defined ($virtual)) {
	if ($virtual) {
	    $$str_ref = 'Virtual server' if ($str_ref);
	    return 1;
	} else {
	    $$str_ref = 'Physical server' if ($str_ref);
	    return 0;
	}
    } else {
	# No cfgstore information about if this host is virtual or not. Guess based on MAC address.
	my $mac = get_hostdb_attr ('mac', $hostname, $hosts_ref);
	if (defined ($mac)) {
	    if ($mac =~ /^00:50:56:/o) {
		$$str_ref = 'Probably virtual server' if ($str_ref);
		return 1;
	    } else {
		$$str_ref = 'Probably physical server' if ($str_ref);
		return 0;
	    }
	}
    }

    return undef;
}

=head2 get_service_count

    my $count = get_service_count ($hostname, $hosts_ref);

    Get number of monitored services on $hostname.

=cut
sub get_service_count
{
    my $hosts_ref = shift;
    my $hostname = shift;

    if ($$hosts_ref{$hostname}{'service_count'}) {
	return $$hosts_ref{$hostname}{'service_count'};
    }

    return 0;
}

=head2 add_host

    add_host ($hosts_ref, $hostname, $group, $host_check);

    Add a new host with just a host check (typically 'check_ping_placeholder').

=cut
sub add_host
{
    my $hosts_ref = shift;
    my $hostname = shift;
    my $group = shift;
    my $host_check = shift;

    $$hosts_ref{$hostname}{'group'} = $group;
    $$hosts_ref{$hostname}{'hostalive'} = $host_check;
}

sub remove_host
{
    my $hosts_ref = shift;
    my $hostname = shift;

    delete $hosts_ref->{$hostname};
}

=head2 add_group

    my $name = 'serverdrift-auto';
    my $admin = 'serverdrift-admins';
    my $desc = 'Auto-discovered devices';

    add_group ($groups_ref, $name, $admin, $desc);

    Add a new group.

=cut
sub add_group
{
    my $groups_ref = shift;
    my $name = shift;
    my $admin = shift;
    my $desc = shift;

    # Check if group exists first, to not overwrite admin/description if there are
    # different bids for the same $name
    if (! $$groups_ref{$name}) {
	$$groups_ref{$name}{'admin'} = $admin;
	$$groups_ref{$name}{'desc'} = $desc;
    }
}

=head2 get_host_ip

    my $ip = get_host_ip ($hostname, $hosts_ref);

    Get a hosts (primary) IP. Order of preference :

       NERDS
       host2ip ()

    However we figure it out, we will cache the result.

=cut
sub get_host_ip
{
    my $hostname = shift;
    my $hosts_ref = shift;

    my $l_hostname = lc ($hostname);

    unless ($$hosts_ref{$l_hostname}{'ip'}) {
	my $ip = host2ip ($hostname);
	set_host_ip ($l_hostname, $ip, $hosts_ref);
	return ($ip);
    }
    return ($$hosts_ref{$l_hostname}{'ip'});
}

=head2 set_host_ip

    my $ip = set_host_ip ($hostname, $ip, $hosts_ref);

    Set hosts (primary) IP address, for later retreival using get_host_ip ().

=cut
sub set_host_ip
{
    my $hostname = shift;
    my $ip = shift;
    my $hosts_ref = shift;

    my $l_hn = lc ($hostname);
    $$hosts_ref{$l_hn}{'ip'} = $ip;
}

=head2 get_hostdb_attr

    my $value = get_hostdb_attr ('dnsstatus', $hostname, $hosts_ref);

    Get a HOSTDB value from NERDS.

=cut
sub get_hostdb_attr
{
    my $attr = shift;
    my $hostname = shift;
    my $hosts_ref = shift;

    my $id = get_hostdb_id ($hostname, $hosts_ref);
    get_hostdb_attr_by_id ($id, $attr, $hostname, $hosts_ref);
}

=head2 get_hostdb_id

    my $hostid = get_hostdb_id ($hostname, $hosts_ref);

    Get the HOSTDB ID of a host.

=cut
sub get_hostdb_id
{
    my $hostname = shift;
    my $hosts_ref = shift;

    return undef unless defined ($$hosts_ref{$hostname});

    foreach my $id (keys %{$$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_HOSTDB'}{'host'}}) {
	if ($$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_HOSTDB'}{'host'}{$id}{'hostname'} eq $hostname) {
            return int ($id);
	}

	# check aliases
	my $a = $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_HOSTDB'}{'host'}{$id}{'aliases'};
	if ($a) {
	    foreach my $aid (@{$a}) {
		if ($$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_HOSTDB'}{'alias'}{$aid}{'aliasname'} eq $hostname) {
		    return int ($id);
		}
	    }
	}
    }
}

=head2 get_hostdb_attr_by_id

    my $value = get_hostdb_attr_by_id ($hostid, 'dnsstatus', $hostname, $hosts_ref);

    Get a HOSTDB value from NERDS for a specific host id included in the NERDS
    data for $hostname. The id typically points at a parent/child/alias host.

=cut
sub get_hostdb_attr_by_id
{
    my $id = shift;
    my $attr = shift;
    my $hostname = shift;
    my $hosts_ref = shift;

    return $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_HOSTDB'}{'host'}{$id}{$attr};
}

=head2 get_cfgstore_attr

    my $value = get_cfgstore_attr ('is_virtual', $hostname, $hosts_ref);

    Get a cfgstore value from NERDS.

=cut
sub get_cfgstore_attr
{
    my $attr = shift;
    my $hostname = shift;
    my $hosts_ref = shift;

    return undef unless defined ($$hosts_ref{$hostname});

    return $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_cfgstore'}{$attr};
}

=head2 get_cfgstore_attr

    my $subnet_descr = get_hostdb_subnet_attr ('description', $hostname, $hosts_ref);

    Get a parameter for the subnet of $hostname from NERDS.

=cut
sub get_hostdb_subnet_attr
{
    my $attr = shift;
    my $hostname = shift;
    my $hosts_ref = shift;

    my $subnet_id = get_hostdb_attr ('subnet_id', $hostname, $hosts_ref);
    if ($subnet_id) {
	return $$hosts_ref{$hostname}{'nerds_data'}{'host'}{'SU_HOSTDB'}{'subnet'}{$subnet_id}{$attr};
    }

    return undef;
}
