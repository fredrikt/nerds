#!/usr/bin/env perl
#

use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;

my $debug = 0;
my $o_help = 0;
my @input_dirs;
my $output_dir;
my $nrpe_port = '5666';
my $nrpe_cmd = '/usr/lib/nagios/plugins/check_nrpe';

my @nrpe_checks = ('check_disk',
		   'check_load',
		   'check_swap',
		   'check_sensor',
		   'check_ntp_time',
		   'check_sua_ubuntu',
		   # SU Windows server checks
		   'Checkservice',
		   'CPU_Usage',
		   'Memory_Load',
		   'Disk_Check'
    );

Getopt::Long::Configure ("bundling");
GetOptions(
    'd'		=> \$debug,		'debug'			=> \$debug,
    'h'		=> \$o_help,		'help'			=> \$o_help,
    'O:s'	=> \$output_dir,	'output-dir:s'		=> \$output_dir,
    'p:s'	=> \$nrpe_port,		'nrpe-port:s'		=> \$nrpe_port,
    'c:s'	=> \$nrpe_cmd,		'nrpe-command:s'	=> \$nrpe_cmd,
    );

if ($o_help or ! $output_dir) {
    die (<<EOT);

Syntax : $0 -O dir [options] [input-dir ...]

    Required options :

        -O|--output-dir dir	<output directory>
	-p|--nrpe-port port	<Nagios NRPE port (default: 5666)>
	-c|--nrpe-command cmd	<Nagios NRPE command (default: /usr/lib/nagios/plugins/check_nrpe)>

EOT
}

@input_dirs = @ARGV;
push (@input_dirs, $output_dir) unless (@input_dirs);

die ("$0: Invalid output dir '$output_dir'\n") unless (-d $output_dir);

my %hostdata;

foreach my $input_dir (@input_dirs) {
    die ("$0: Invalid input dir '$input_dir'\n") unless (-d $input_dir);

    my @files = get_nerds_data_files ($input_dir);

    foreach my $file (@files) {
	warn ("  file '$file'\n") if ($debug);
	process_file ("$input_dir/$file", \%hostdata, $nrpe_port, $nrpe_cmd, \@nrpe_checks, $debug);
    }
}

# break up the union of all scan files into an XML blob per host
foreach my $host (sort keys %hostdata) {
    my $thishost = $hostdata{$host};

    my $json = JSON->new->utf8->pretty (1)->canonical (1)->encode ($thishost);
    warn ("JSON output for host '$host' :\n${json}\n\n") if ($debug);

    my $dir = get_nerds_data_dir ($output_dir, 'nagios_nrpe');
    my $fn = "${dir}/${host}..json";
    warn ("Outputting to '$fn'\n") if ($debug);
    open (OUT, "> $fn") or die ("$0: Could not open '$fn' for writing : $!\n");
    print (OUT $json);
    close (OUT);
}

exit (0);


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
    my $nrpe_port = shift;
    my $nrpe_cmd = shift;
    my $nrpe_checks_ref = shift;
    my $debug = shift;

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

    my $hostname = $$t{'host'}{'name'};
    foreach my $family (keys %{$$t{'host'}{'services'}}) {
	ADDR: foreach my $addr (keys %{$$t{'host'}{'services'}{$family}}) {
	    foreach my $proto (keys %{$$t{'host'}{'services'}{$family}{$addr}}) {
		foreach my $port (keys %{$$t{'host'}{'services'}{$family}{$addr}{$proto}}) {
		    if ($port == $nrpe_port) {
			my $res = probe_nrpe ($hostname, $href, $nrpe_port, $nrpe_cmd, $nrpe_checks_ref, $debug);
			next ADDR unless ($res);
		    }
		}
	    }
	}
    }
}

sub probe_nrpe
{
    my ($hostname, $href, $nrpe_port, $nrpe_cmd, $nrpe_checks_ref, $debug) = @_;

    foreach my $check (@{$nrpe_checks_ref}) {
	warn ("      probing '$check'\n") if ($debug);
	my $out = `$nrpe_cmd -H $hostname -c $check`;
	chomp ($out);

	if ($out =~ /(OK|WARNING|CRITICAL)/o) {
	    $$href{$hostname}{'host'}{'version'} = 1;
	    $$href{$hostname}{'host'}{'name'} = $hostname;

	    $$href{$hostname}{'host'}{'nagios_nrpe'}{$check}{'working'} = JSON::true;
	} elsif ($out =~ /^NRPE: Command .* not defined/o or
		 $out =~ /No handler for that command/o) {
	    warn ("         - NO\n") if ($debug);
	} elsif (
	    $out =~ /Received 0 bytes from daemon./o or
	    $out =~ /Error - Could not complete SSL handshake/o or
	    $out =~ /CHECK_NRPE: Socket timeout /o or
	    $out =~ /Connection refused or timed out/o
	    ) {
	    warn ("Giving up on host '$hostname'\n") if ($debug);
	    return 0;
	} else {
	    warn ("Unknown output of check_nrpe on $hostname : $out\n");
	}
    }

    return 1;
}
