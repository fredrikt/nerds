#!/usr/bin/env perl


=head1 NAME

parse_su_hosts_txt.pl -- Parse a text file with information about hosts
    that should be monitor with Nagios.

=head1 SYNOPSIS

parse_su_hosts_txt.pl -O output-dir /path/to/cfg/su-hosts.txt

For complete usage information :

parse_su_hosts_txt.pl -h

=head1 DESCRIPTION

 This producer parses a text file containing hosts and Nagios checks
 that should be used for that host. Example file :

=head1 EXAMPLE

# MAIL-SERVERS

group mail-servers       mail-admins             e-mail servers

mx1.su.se       check-host-alive        check_smtp, \
                                        check_ssh, \
                                        check_nrpe_1arg!check_disk

av-in4.su.se    check-host-alive        check_nrpe_1arg!check_load, \
                                        check_ssh, \
                                        check_smtp, \
                                        check_nrpe_1arg!check_disk, \
                                        check_procalive!amavisd!8!4, \
                                        check_procalive!clamd!1!4

=head1 EXPLANATION

   Load the su-hosts.txt file. Examples of su-hosts.txt content :

   1) A group

    group mail-servers       mail-admins              e-mail servers

    This will result in

    * a Nagios host group with name "e-mail servers"
    * a Nagios contactgroup with name "mail-admins"
    * a Nagios contact with name "mail-admins-contact"

    2) A host

    mx1.su.se       check-host-alive        check_smtp, \
                                            check_ssh, \
                                            check_nrpe_1arg!check_disk

    This will result in

    * a Nagios host entry for "mx1.su.se", with check_command "check-host-alive",
      belonging to the last seen 'group'.
    * Three Nagios service entrys

=cut

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;

my $MYNAME = 'SU_nagios_hostsfile';
my $debug = 0;
my $o_help = 0;
my @input_dirs;
my $output_dir;
my $hostdb_dir;

Getopt::Long::Configure ("bundling");
GetOptions(
    'd'		=> \$debug,		'debug'		=> \$debug,
    'h'		=> \$o_help,		'help'		=> \$o_help,
    'O:s'	=> \$output_dir,	'output-dir:s'	=> \$output_dir,
    'H:s'	=> \$hostdb_dir,	'hostdb-dir:s'	=> \$hostdb_dir,
    );

if ($o_help or ! $output_dir) {
    die (<<EOT);

Syntax : $0 -O dir [options] input-file

    Required options :

        -O	output directory

    Options :

        -H <dir> or --hostdb-dir <dir>	Directory with SU_HOSTDB NERDS output, for hostname canonization

EOT
}

my $input_file = shift @ARGV;

die ("$0: Invalid output dir '$output_dir'\n") unless ($output_dir and -d $output_dir);

my %canon_hostdata;
load_canon_hostdata ($hostdb_dir, \%canon_hostdata, $debug) if ($hostdb_dir);

my %hostdata;
my $hostdb; # undefined for now

read_suhosts_file ($input_file, \%hostdata, $hostdb, \%canon_hostdata, $debug);

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


sub read_suhosts_file
{
    my $fn = shift;
    my $href = shift;
    my $hostdb = shift;
    my $canon_hostdata = shift;
    my $debug = shift;

    open (FILE, "< $fn") or die ("$0: Could not open su-hosts file '$fn' for reading : $!\n");

    my $group = '';
    my $admin = '';
    my $desc = '';

    while (my $line = <FILE>) {
	chomp ($line);

	next if ($line =~ /^\s*\#/o);	# skip comments
	next if ($line =~ /^\s*$/o);	# and blank lines

	$line =~ s/#.*$//go;	# remove comments at end of line

	if ($line =~ /^group\s+?(.+?)\s*\t+(.+?)\s*\t\s*(.+?)\s*$/) {
	    $group = $1;
	    $admin = $2;
	    $desc = $3;
	    utf8::decode ($desc);

	    warn ("Set current group '$group'\n") if ($debug);
	} elsif ($line =~ /^(\S+?)\s+(\S+?)\s+(.+)\s*$/o or
		 $line =~ /^(\S+?)\s+(\S+?)\s*$/o) {
	    # host line
	    my $host = lc ($1);
	    my $hostalive = $2;
	    my $services_in = $3;

	    my %res;

	    if (defined ($hostdb) and
		! $hostdb->clean_hostname ($host)) {
		warn ("$0: Invalid hostname '$host' on line $. of file '$fn'\n");
		next;
	    }

	    $host = get_canonical_hostname ($host, $canon_hostdata);

	    $services_in =~ s/\s*$//go;	# strip
	    # look for backslash at end of services
	    while ($services_in =~ /\\$/) {
		$services_in =~ s/\\$//go;	# remove the trailing backslash

		my $t = <FILE>;
		chomp ($t);
		die ("$0: Parsed backslash continued line past end of file '$fn' (host $host)\n") unless ($t);

		$services_in .= $t;
		$services_in =~ s/\s*$//go;	# strip
	    }

	    # remove extra spaces and tabs and stuff.
	    $services_in =~ s/\s+/ /go;
	    # remove spaces next to commas
	    $services_in =~ s/\s*,\s*/,/go;

	    my @services = split (',', $services_in);
	    my $service_count = 0 + @services;
	    warn ("Host '$host' - $hostalive, $service_count service(s)\n") if ($debug);

	    add_host (\%res, $host, $hostalive, \@services, $group, $admin, $desc);

	    $$href{$host} = \%res;
	} else {
	    die ("$0: Unparsable data, file '$fn' line $. : '$line'\n");
	}
    }

    close (FILE);

    return 1;
}

sub add_host
{
    my $res = shift;
    my $hostname = shift;
    my $hostalive = shift;
    my $services_ref = shift;
    my $groupname = shift;
    my $groupadmin = shift;
    my $groupdesc = shift;

    # mandatory basic NERDS data for a host
    $$res{'host'}{'version'} = 1;
    $$res{'host'}{'name'} = $hostname;

    $$res{'host'}{'monitoring'}{'nagios'}{'version'} = '3.0';	# to prepare for future changes
    $$res{'host'}{'monitoring'}{'nagios'}{'hostcheck'} = $hostalive;
    $$res{'host'}{'monitoring'}{'nagios'}{'group'}{'name'} = $groupname;
    $$res{'host'}{'monitoring'}{'nagios'}{'group'}{'admin'} = $groupadmin;
    $$res{'host'}{'monitoring'}{'nagios'}{'group'}{'description'} = $groupdesc;

    foreach my $service (@{$services_ref}) {
	add_check ($$res{'host'}{'monitoring'}{'nagios'}, $hostname, $service);
    }
}

=head2 add_check

    add_check ($href, $hostname, $check);

    Add a service check to $hostname, avoiding duplicates. We try to avoid showing
    SNMP community etc. in service descriptions.

    $check examples :

    	"check_disk"
    	"[MY CHECK]check_disk"
    	"[special HTTP]!check_https_port!9443"

=cut
sub add_check
{
    my $href = shift;
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
    if ($$href{'checks'}{$description}) {
	if ($$href{'checks'}{$description}{'command'} eq $command and
	    $$href{'checks'}{$description}{'arguments'} eq $args) {
	    # this check is a duplicate, just return
	    return 0;
	}

	foreach my $i (2..99) {
	    my $t_desc = "${description}_${i}";
	    if (! $$href{'checks'}{'services'}{$t_desc}) {
		$description = $t_desc;
		last;
	    } else {
		if ($$href{'checks'}{$t_desc}{'command'} eq $command and
		    $$href{'checks'}{$t_desc}{'args'} eq $args) {
		    # this check is a duplicate, just return
		    return 0;
		}
	    }
	}

	if ($$href{'checks'}{$description}) {
	    die ("$0: Could not make unique description for check '$check' on host $hostname\n");
	}
    }

    $$href{'checks'}{$description}{'command'} = $command;
    $$href{'checks'}{$description}{'arguments'} = $args;
}


sub get_nerds_data_dir
{
    my $repo = shift;
    my $producer = shift;

    return "$repo/producers/$producer/json";
}

sub load_canon_hostdata
{
    my $input_dir = shift;
    my $hosts_ref = shift;
    my $debug = shift;

    my @files = get_nerds_data_files ($input_dir);

    if (@files) {
	warn ("Loading host data from directory '$input_dir'...\n") if ($debug);
    }

    foreach my $file (@files) {
	warn ("  file '$file'\n") if ($debug);

	open (IN, "< $input_dir/$file") or die ("$0: Could not open '$input_dir/$file' for reading : $!\n");
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

	$$hosts_ref{$hostname} = $t;
    }
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

=head2 get_canonical_hostname

   my $hostname = get_canonical_hostname ($name_in, $hosts_ref);

   Get the 'best' hostname from a number of alternatives.

=cut
sub get_canonical_hostname
{
    my $hostname_in = shift;
    my $hosts_ref = shift;

    $hostname_in = lc ($hostname_in);

    foreach my $hostname (sort keys %{$hosts_ref}) {
	my $a = get_hostdb_attr ('aliases', $hostname, $hosts_ref);
	if ($a) {
	    foreach my $aid (@{$a}) {
		my $aliasname = $$hosts_ref{$hostname}{'host'}{'SU_HOSTDB'}{'alias'}{$aid}{'aliasname'};

		return lc ($hostname) if (lc ($aliasname) eq lc $hostname_in);
	    }
	}
    }

    return $hostname_in;
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

    foreach my $id (keys %{$$hosts_ref{$hostname}{'host'}{'SU_HOSTDB'}{'host'}}) {
	if ($$hosts_ref{$hostname}{'host'}{'SU_HOSTDB'}{'host'}{$id}{'hostname'} eq $hostname) {
            return int ($id);
	}

	# check aliases
	my $a = $$hosts_ref{$hostname}{'host'}{'SU_HOSTDB'}{'host'}{$id}{'aliases'};
	if ($a) {
	    foreach my $aid (@{$a}) {
		if ($$hosts_ref{$hostname}{'host'}{'SU_HOSTDB'}{'alias'}{$aid}{'aliasname'} eq $hostname) {
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

    return $$hosts_ref{$hostname}{'host'}{'SU_HOSTDB'}{'host'}{$id}{$attr};
}
