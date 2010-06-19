#!/usr/bin/perl
#
# Copyright (C) 2006-2010 by John P. Weiss
#
# This package is free software; you can redistribute it and/or modify
# it under the terms of the Artistic License, included as the file
# "LICENSE" in the source code archive.
#
# This package is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# You should have received a copy of the file "LICENSE", containing
# the License John Weiss originally placed this program under.
#
# RCS $Id$
############


############
#
# Configuration Variables
#
############


my $_ConfigFile = undef();
my $_DataFile = "/tmp/mrtg-ping-bandwidth.dat";
my $_TieAttempts = 5;
my $_TieWait = 1;
my $_PostDaemonizeWait = 5;
#my $_DaemonPIDFile = "/tmp/mrtg-ping-bandwidth.pid";
my $_DaemonPIDFile = "/var/run/mrtg-ping-bandwidth.pid";
my $_DaemonLog = "/tmp/mrtg-ping-bandwidth.log";
my $_ProbeInterval = 5*60;
my $_ConfigUpdateInterval = 7;


############
#
# Precompilation Init
#
############
# Before anything else, split the script's name into directory/file.  We
# want to add the script's directory to the set of include-dirs.  This way, we
# get any packages living in the script's directory.
my $_MyName;
my $_MyPath;
BEGIN {
    if ($0 =~ m|\A(.*)/([^/]+\Z)|) {
        if ($1 ne ".") { $_MyPath = $1; }
        $_MyName = $2;
    } else { $_MyName = $0; }  # No path; only the script name.
    if (defined($_MyPath)) { push @INC, $_MyPath; }
}


############
#
# Includes/Packages
#
############


require 5;
use strict;
use bytes;           # Overrides Unicode support
use Data::Dumper;
use Tie::File;
use POSIX qw(nice setsid);


############
#
# Other Global Variables
#
############


my $_TracerouteCmd = "traceroute -4 -n -w 1 -N 1 ";
my @_Measurements;
my $_refDataTieObj;


############
#
# Functions
#
############


#
# Ping/Traceroute
#

sub bandwidth_ping($) {
    my $host = shift();

    my $pingcmd="/bin/ping -A -w 2 -n ";
    $pingcmd .= $host;
    $pingcmd .= " 2>&1 |";
    unless (open(PINGFH, $pingcmd)) {
        print STDERR ("FATAL: Can't run command: ", $pingcmd,
                      "\nReason: \"", $!, "\"\n");
        return -1;
    }
    my @pingLines = <PINGFH>;
    close(PINGFH);

    my $bytes = 0;
    my $msecs = 0;
    foreach (@pingLines) {
        if (m/(\d+) bytes from .* time=([[:digit:].]+) ms/) {
            $bytes += $1;
            $msecs += $2;
        }
    }

    my $rate = $bytes;
    if ($msecs) {
        $rate /= $msecs;
        $rate *= 1000;
    } else {
        $rate = 0;
    }

    return $rate;
}


sub get_hop_ips($\@) {
    my $target = shift();
    my $ref_hop_numbers = shift();
    my @hops = ();

    my $cmd = $_TracerouteCmd;
    $cmd .= " -q 1 ";
    $cmd .= $target;
    $cmd .= " 2>&1 |";
    unless (open(TRTFH, $cmd)) {
        print STDERR ("ERROR: Can't run command: ", $cmd,
                      "\nReason: \"", $!, "\"\n");
        return ();
    }

    my @traceroute_output = <TRTFH>;

    close(TRTFH)
        or warn("Error closing pipe to command:\n\t", $cmd,
                ($! ? "\nReason: \"".$!."\"\n" : "\n"));

    foreach (@traceroute_output) {
        chomp;
        next unless (m/^\s*\d+\s/);
        my @fields = split();
        if ($fields[1] =~ m/\*/) {
             $hops[$fields[0]] = undef();
        } else {
             $hops[$fields[0]] = $fields[1];
        }
    }

    return @hops[@$ref_hop_numbers];
}


#
# Configfile Processing
#


sub are_numbers(;@) {
    foreach (@_){
        if (m/\D/) {
            print STDERR "ERROR: \"";
            print STDERR ;
            print STDERR "\" is not a number.";
            return 0;
        }
    }
    return 1;
}


sub build_cfgfile_name() {
    if (defined($_ConfigFile) && ($_ConfigFile ne "")) {
        return;
    }

    $_ConfigFile = $_MyPath;
    $_ConfigFile .= "/";

    unless ($_ConfigFile =~ s/bin/etc/) {
        $_ConfigFile .= "etc/";
    }

    if (! -d $_ConfigFile) {
        $_ConfigFile = "/etc/mrtg/";
    }
    $_ConfigFile .= $_MyName;
    $_ConfigFile =~ s/.pl$/.cfg/;
}


sub read_config(\$\@\@) {
    my $ref_remote_host = shift();
    my $ref_hop_numbers = shift();
    my $ref_measurement_targets = shift();

    build_cfgfile_name();

    my %options=();
    my $array_option="";

    open(IN_FS, "$_ConfigFile")
        or die("Unable to open file for reading: \"$_ConfigFile\"\n".
               "Reason: \"$!\"\n");

    while (<IN_FS>) {
        my $line = $_;
        chomp $line; # Remove newline

        # Trim whitespaces from either end of the line
        # (This is faster than the obvious single-regexp way.)
        for ($line) {
            s/^\s+//;
            s/\s+$//;
        }

        # Skip comment or blank lines (using optimizer-friendly Perl idiom).
        next if ($line eq "");
        next if ($line =~ m/^\#/);

        # Special handling:
        # This is the end of an array parameter.  Must come before the
        # array processing block.
        if ($line eq ")") {
            $array_option = "";
            next;
        }

        # Special handling:
        # We are in the middle of processing an array option.
        if ($array_option) {
            push @{$options{$array_option}}, $line;
            next;
        }

        # Get the option name and value, trimming whitespace on either
        # side of the delimiter characters.
        my ($optname, $val) = split /\s*[:=]\s*/, $line;

        # Special handling:
        # This is the start of an array parameter.
        if ($val eq "(") {
            $array_option=$optname;
            $options{$array_option} = [ ];
            next;
        }

        # Regular option processing
        $options{$optname} = $val;
    }
    close IN_FS;

    #print STDERR ("#DBG# ", Dumper(\%options), "\n");

    $$ref_remote_host = $options{"remote_host"};
    @$ref_hop_numbers = @{$options{"hop_numbers"}};
    @$ref_measurement_targets = @{$options{"measurement_targets"}};
    if (defined($options{"_ProbeInterval"})) {
        $_ProbeInterval = $options{"_ProbeInterval"};
    }
   if (defined($options{"_ConfigUpdateInterval"})) {
        $_ConfigUpdateInterval = $options{"_ConfigUpdateInterval"};
    }
    if (defined($options{"_DaemonLog"})) {
        $_DaemonLog = $options{"_DaemonLog"};
    }

    #print STDERR ("#DBG# @varnames\n");
    #print STDERR ("#DBG1# ", $$ref_remote_host, "\n#DBG2# ( ",
    #              join("\n#DBG2# ", @$ref_hop_numbers), " )\n#DBG3# ( ",
    #              join("\n#DBG3# ", @$ref_measurement_targets), " )\n");
    return 1;
}


sub log_config_changes(\@\@) {
    my $ref_old = shift();
    my $ref_new = shift();

    return unless (scalar(@$ref_old) && scalar(@$ref_new));

    my $min_n = $#{$ref_old};
    my $max_n = $min_n;
    my $targChangetypeMsg = "";
    my $targAdded = 0;

    if ($#{$ref_new} > $max_n) {
        $targChangetypeMsg = "Added";
        $targAdded = 1;
        $max_n = $#{$ref_new};
    } else {
        if ($#{$ref_new} != $max_n) {
            $targChangetypeMsg = "Removed   -  was";
        }
        $min_n = $#{$ref_new};
    }

    foreach my $targ_idx (0 .. $min_n) {
        if ($ref_old->[$targ_idx] ne $ref_new->[$targ_idx]) {
            print STDERR ("Target #", $targ_idx + 1, " Changed:\t",
                          $ref_old->[$targ_idx],
                          "   -->   ",
                          $ref_new->[$targ_idx], "\n");
        }
    }

    foreach my $targ_idx (($min_n+1) .. $max_n) {
        print STDERR ("Target #", $targ_idx + 1, " ",
                      $targChangetypeMsg, ":\t",
                      ( $targAdded ? $ref_new->[$targ_idx]
                        : $ref_old->[$targ_idx] ),
                      "\n");
    }
}


sub write_config($\@\@) {
    my $remote_host = shift();
    my $ref_hop_numbers = shift();
    my $ref_measurement_targets = shift();

    build_cfgfile_name();

    unless (open(CFGFH, ">", $_ConfigFile)) {
        print STDERR ("ERROR: Can't open \"",  $_ConfigFile,
                      "\" for writing.\nReason: \"", $!, "\"\n");
        return 0;
    }

    print CFGFH ("remote_host = ", $remote_host, "\n");
    print CFGFH ("hop_numbers = (\n\t",
                 join("\n\t", @$ref_hop_numbers),
                 "\n)\n");
    print CFGFH ("measurement_targets = (\n\t",
                 join("\n\t", @$ref_measurement_targets),
                 "\n)\n");
    print CFGFH ("_ProbeInterval = ", $_ProbeInterval, "\n");
    print CFGFH ("_ConfigUpdateInterval = ", $_ConfigUpdateInterval, "\n");
    print CFGFH ("_DaemonLog = ", $_DaemonLog, "\n");

    close CFGFH;
    return 1;
}


sub update_config($\@;\@) {
    my $remote_host = shift();
    my $ref_hop_numbers = shift();
    my $ref_orig_targets = (scalar(@_) ? shift() : undef());

    unless (($remote_host ne "") && are_numbers(@$ref_hop_numbers)) {
        usage();
    }
    my @measurement_targets = get_hop_ips($remote_host, @$ref_hop_numbers);
    #print STDERR ("#DBG# (\n#DBG# ", join("\n#DBG# ", @measurement_targets,
    #                                      $remote_host), "\n#DBG# )\n");

    my $errmsg = "";
    if (scalar(@measurement_targets)) {
        foreach my $idx (0 .. $#measurement_targets) {
            unless (defined($measurement_targets[$idx])) {
                if ($errmsg eq "") {
                    $errmsg .= "Failed to retrieve all hops from host: ";
                    $errmsg .= $remote_host;
                }
                $errmsg .= "\n\tMissing hop \#";
                $errmsg .= $ref_hop_numbers->[$idx];
                if (defined($ref_orig_targets->[$idx])) {
                    $errmsg .= ".  Reusing:  ";
                    $errmsg .= $ref_orig_targets->[$idx];
                } else {
                    $errmsg .= ".";
                }
                $measurement_targets[$idx] .= $ref_orig_targets->[$idx];
            }
        }

        # Add the traceroute target to the list of hops.
        push (@measurement_targets, $remote_host);
    } else {
        $errmsg .= "Couldn't get hops: (";
        $errmsg .= join(", ", @$ref_hop_numbers);
        $errmsg .= ")\nNo route to host: ";
        $errmsg .= $remote_host
    }

    if ($errmsg eq "") {
        if (defined($ref_orig_targets)) {
            log_config_changes(@$ref_orig_targets, @measurement_targets);
        }
        write_config($remote_host, @$ref_hop_numbers, @measurement_targets);
    } else {
        print STDERR ($errmsg, "\n");
        if (defined($ref_orig_targets)) {
            @measurement_targets = @$ref_orig_targets;
        }
    }

    return @measurement_targets;
}


#
# Client for the rate-monitoring daemon.
#

sub retrieve_rates($$) {
    my $targ1=shift();
    my $targ2=shift();

    #print STDERR ("#DBG# t_0: ", time(),"\n");

    # Process the args
    unless (are_numbers($targ1, $targ2)) {
        usage();
    }

    # Tie an array to the data file, retrying as needed.
    my @measurements;
    my $ref_tied=undef();
    my $attempts=0;
    my $failureReason="";
    do {
        if ($attempts) {
            sleep($_TieWait);
        }
        $ref_tied = tie(@measurements, 'Tie::File', $_DataFile);
        if (!defined($ref_tied) && (($! ne "") || ($@ ne ""))) {
            $failureReason = $!;
            if (($failureReason ne "") && ($@ ne "")) {
                $failureReason .= "\n";
            }
            $failureReason .= $@;
        }
        ++$attempts;
        #print STDERR ("#DBG# TieAttempts: ",$attempts,"\n");
    } while ((!defined($ref_tied) || !scalar(@measurements)) &&
             ($attempts < $_TieAttempts));

    #print STDERR ("#DBG# t1: ", time(),"\n");

    # Handle failed tie-attempt.
    if (!defined($ref_tied) || !scalar(@measurements)) {
        print STDERR ("Failed to tie array to file: \"", $_DataFile, "\".\n");
        if ($failureReason ne "") {
            print STDERR ("Reason: \"", $failureReason, "\"\n");
        } elsif (!scalar(@measurements)) {
            print STDERR ("No measurements present.  ",
                          "(Is the daemon running?)\n");
        }
        return (0, 0);
    }

    # We're ready!  Retrieve the two measurements.
    if ($targ1 > scalar(@measurements)) {
        $targ1 = scalar(@measurements);
    }
    if ($targ2 > scalar(@measurements)) {
        $targ2 = scalar(@measurements);
    }
    --$targ1;
    --$targ2;
    if ($targ1 < 0) { $targ1 = 0; }
    if ($targ2 < 0) { $targ2 = 0; }
    my @result = ($measurements[$targ1], $measurements[$targ2]);

    #print STDERR ("#DBG# t2: ", time(),"\n");

    # Cleanup
    undef($ref_tied);
    untie(@measurements);

    #print STDERR ("#DBG# t_f: ", time(),"\n");

    # //Now// we can return.
    return @result;
}


#
# Daemon-related
#


sub daemonize(;$) {
    my $keepParentRunning = (scalar(@_) ? shift() : 0);

    if ($keepParentRunning) {
        defined(my $pid = fork) or die "Can't fork: $!";
        return 0 if ($pid);
        # else:  We're the child, which we'll use to create the daemon.
    }

    chdir "/tmp"      or die "Can't chdir to /tmp: $!";
    open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
    open STDOUT, ">>$_DaemonLog"
        or die "Can't write to $_DaemonLog: $!";

    defined(my $pid = fork) or die "Can't fork: $!";
    exit 0 if ($pid);
    #else:  We're the (grand)child;

    setsid                  or die "Can't start a new session: $!";
    open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
    return 1;
}


sub renice_self(;$) {
    my $niceness=shift();

    unless (defined($niceness) && (0 <= $niceness) && ($niceness < 20)) {
        $niceness = 19;
    }

    unless (nice($niceness)) {
        warn("Failed to renice myself to '$niceness'.  Aborting.\n");
    }
}


sub no_running_daemon() {
    # Check that the PID file exists.
    return 1 unless (-e $_DaemonPIDFile);

    # Check if the process is running.
    open(PIDFH, "<", $_DaemonPIDFile) or return 1;
    my $daemonPid = <PIDFH>;
    close(PIDFH);
    chomp $daemonPid;

    # Do something to check on process existence.
    # In linux & solaris, we can do this:
    if (-e "/proc/$daemonPid") {
        return 0;
    } #else

    # On other unix variants, we'd need to use code like this:
    #my @running = `ps -e 2>&1`; # or `ps -ax 2>&1`;
    #my @match = grep(/\b$daemonPid\b/, @running);
    #return !scalar(@match);
    ## Don't use "system()", as it discards the output.

    print STDERR ("Process '", $daemonPid, "'not found.\n");
    print STDERR ("Check for dead/stale PID file:  \"", $_DaemonPIDFile,
                  "\"\n");
    return 1;
}


sub daemon_sig_cleanup {
    my $killsig=shift();

    undef($_refDataTieObj);
    untie(@_Measurements);
    unlink($_DaemonPIDFile, $_DataFile);

    if (($killsig == 1) || ($killsig == 2) || ($killsig == 15)) {
        exit 0;
    } # else
    exit $killsig;
}


sub daemon_main(\@$\@) {
    my @measurement_targets = @{shift()};
    my $remote_host = shift();
    my @hop_numbers = @{shift()};

    # Print out something for the log file
    print "\n", "="x78, "\n\n";
    print "#  Starting $_MyName in Daemon Mode\n";
    my $date = localtime();
    print "#  ", $date, "\n\n";

    # Write our PID to the PID file.
    #
    open(PIDFH, ">", $_DaemonPIDFile)
        or die("Cannot open PIDfile: \"".$_DaemonPIDFile."\"\n".
               "Reason: \"".$!."\"\n");
    print PIDFH ($$, "\n");
    close(PIDFH)
        or die("Cannot write PIDfile: \"".$_DaemonPIDFile."\"\n".
               "Reason: \"".$!."\"\n");

    # Install Signal Handlers
    #
    foreach my $signame (keys(%SIG)) {
        # Leave the KILL/STOP signals alone.
        next if (($signame eq 'KILL' ) || ($signame eq 'STOP'));
        if ($signame =~ m/ALRM|CHLD|CLD|NUM/) {
            $SIG{$signame} = "IGNORE";
        } else {
            $SIG{$signame} = \&daemon_sig_cleanup;
        }
    }

    # Tie an array to the data file, retrying as needed.
    #
    my @_Measurements;
    $_refDataTieObj = tie(@_Measurements, 'Tie::File', $_DataFile);
    if (!defined($_refDataTieObj) && (($! ne "") || ($@ ne ""))) {
        my $failureReason = $!;
        if (($failureReason ne "") && ($@ ne "")) {
            $failureReason .= "\n";
        }
        $failureReason .= $@;
        print STDERR ("Failed to tie array to file: \"", $_DataFile, "\".\n",
                      "Reason: \"", $failureReason, "\"\n");
    }

    # The Main Loop
    #
    my $configUpdateInterval_secs = $_ConfigUpdateInterval * 24 * 3600;
    my $nextConfigUpdate = time() + $configUpdateInterval_secs;
    while (1) {
        my $probe_duration = -time();
        my $network_state = 1;
        foreach my $idx (0 .. $#measurement_targets) {
            $_Measurements[$idx] = bandwidth_ping($measurement_targets[$idx]);
            $network_state *= $_Measurements[$idx];
        }

        # Rebuild the config from time to time.
        #
        if (($network_state != 0) && (time() > $nextConfigUpdate)) {
#FIXME:  This isn't running.
            print STDERR ("#DBG#  Trying to update config...\n");
            @measurement_targets = update_config($remote_host,
                                                 @hop_numbers,
                                                 @measurement_targets);
            $nextConfigUpdate += $configUpdateInterval_secs;
        }

        $probe_duration += time();
        if ($_ProbeInterval < $probe_duration) {
            sleep($_ProbeInterval);
        } else {
            sleep($_ProbeInterval - $probe_duration);
        }
    }
}


sub start_daemon($\@$\@) {
    my $keepParentRunning = shift();
    my $ref_measurement_targets = shift();
    my $remote_host = shift();
    my $ref_hop_numbers = shift();

    # daemonize() either exits the parent process or returns 0.
    daemonize($keepParentRunning) or return 1;

    # We're the child process if we reach this point.
    renice_self();
    daemon_main(@$ref_measurement_targets, $remote_host, @$ref_hop_numbers);
    # Should never reach here.
    exit 127;
}


sub usage() {
    print STDERR ("usage: ", $_MyName, " -b <host1> [<host2>]\n");
    print STDERR (" "x7, $_MyName, " -c <hop#>[,<hop#>[,...]] <host>\n");
    print STDERR (" "x7, $_MyName, " -d [ <hop#>[,<hop#>[,...]] <host> ]\n");
    print STDERR (" "x7, $_MyName, " [-r] <target#> [<target#>]\n\n");
    print STDERR ("Both <target#> and <hop#> are 1-offset.  <target#> is ",
                  "not the same as <hop#>.\n\n");
    print STDERR ("In the configfile, \"_ProbeInterval\" is in seconds, ",
                  "while\n\"_ConfigUpdateInterval\" is in days.\n");
    print STDERR ("\nRun Modes:\n\n");
    print STDERR ("'-c':  (Re)creates the configfile.  <host> is the ",
                  "traceroute target,\n");
    print STDERR ("       monitor.  The <host> is always monitored.\n");
    print STDERR ("'-d':  Run in daemon mode.  Refreshes the configfile on ",
                  "init if you\n");
    print STDERR ("       specify the other commandline args (which look ",
                  "quite a lot\n");
    print STDERR ("       like the ones for '-c' mode).\n");
    print STDERR ("'-b':  Run in one-shot ping mode.  Checks one or two ",
                  "destination hosts,\n");
    print STDERR ("       as required by MRTG.\n");
    print STDERR ("<no-option>:\n");
    print STDERR ("       Returns the last throughput check from an ",
                  "instance of this script\n");
    print STDERR ("       already running in '-d' mode.  Like '-b' mode, ",
                  "returns the throughput \n");
    print STDERR ("       for one or two targets, as required by MRTG.  The ",
                  "<target#> is the\n");
    print STDERR ("       list index of the IPs/hosts being monitored.  ",
                  "So, if you ran '-c'\n");
    print STDERR ("       with the hop-list '3,5,6,11', then <target#>==3 ",
                  "would return the\n");
    print STDERR ("       throughput of hop-#6, while <target#>==5 would ",
                  "return the\n");
    print STDERR ("       throughput of the target host.\n");
    print STDERR ("'-r':  Identical to the previous mode, but will start a ",
                  "daemon if one\n");
    print STDERR ("       isn't already running.\n");

    print STDERR ("\nTo kill a daemonized instance, use:\n\t",
                  "kill \$(\< ", $_DaemonPIDFile, ")\n");
    print STDERR ("\nTo list the througput of all targets, in order, ",
                  "use:\n\t",
                  "cat ", $_DataFile, "\n");
    exit 1;
}


############
#
# Main
#
############


# This is a really crude script.  Since it only exists to be run by MRTG, I
# don't want too much overhead in it.
#
my $check_bandwidth=0;
my $update_hop_ips=0;
my $daemonize=0;
my $pingAfterDaemonizing=0;
if ($ARGV[0] eq "-b") {
    shift(@ARGV);
    $check_bandwidth=1;
} elsif ($ARGV[0] eq "-c") {
    shift(@ARGV);
    $update_hop_ips=1;
} elsif ($ARGV[0] eq "-d") {
    shift(@ARGV);
    $daemonize = 1;
    if (scalar(@ARGV) > 1) {
        $update_hop_ips=1;
    }
} elsif ($ARGV[0] eq "-r") {
    shift(@ARGV);
    $daemonize=1;
    $pingAfterDaemonizing=1;
} elsif ($ARGV[0] =~ m/^-/) {
    usage();
}

if (($ARGV[0] eq "") && !$daemonize) {
    print STDERR ("Missing args.\n");
    usage();
}


#
# -b : Run single-shot.
#
if ($check_bandwidth) {
    my $rate1 = bandwidth_ping(shift(@ARGV));
    if ($rate1 < 0) { exit 1; }
    my $rate2 = $rate1;
    if (scalar(@ARGV)) {
        $rate2 = bandwidth_ping(shift(@ARGV));
        if ($rate2 < 0) { exit 1; }
    }
    printf "%d\n%d\n", $rate1, $rate2;
    exit 0;
}

#
# Read the configuration.
# (Generate a new configfile when run with '-c' or '-d'.)
#
my $remote_host;
my @hop_numbers;
my @measurement_targets;
if ($update_hop_ips) {
    @hop_numbers = split(/,/, shift(@ARGV));
    $remote_host = shift(@ARGV);
    @measurement_targets = update_config($remote_host, @hop_numbers);
    exit 0 unless ($daemonize);
} else {
    read_config($remote_host, @hop_numbers, @measurement_targets);
}

#
# If we reach this point, then we were run with either the '-d' or no flags at
# all.  The former starts a running daemon.  The latter requires one.
# So, check for one.
#
my $noDaemonRunning = no_running_daemon();

if ($daemonize) {
    if ($noDaemonRunning) {
        start_daemon($pingAfterDaemonizing,
                     @measurement_targets, $remote_host, @hop_numbers);

        # If we return from start_daemon(), we're the parent.  Let's sleep for
        # a bit for the daemon to start up before going on (and getting the
        # ping data).
        sleep($_TieAttempts*$_TieWait + $_PostDaemonizeWait);

    } elsif (!$pingAfterDaemonizing) {
        # Don't do anything more.
        print ("Daemonized instance already running.  Examine \n\"",
               $_DaemonPIDFile, "\" for its PID.\n\n",
               "To restart $0, do the following:\n",
               "\tkill \$(\< ", $_DaemonPIDFile, ");\n",
               "\t$0 -d\n");
        exit 0;
    }

    # else:  We want to ping whether or not we daemonize.
} elsif ($noDaemonRunning && !$daemonize) {
    print ("No daemonized instance running.  Rerun \n",
           "$0 with the '-d' option.\n\n",
           "Cowardly refusing to continue.\n");
    exit 2;
}


#
# no flags:  Normal run mode.  Retrieve desired measurements from the daemon.
#
my $hop_target1 = shift(@ARGV);
my $hop_target2 = $hop_target1;
if (scalar(@ARGV)) {
    $hop_target2 = shift(@ARGV);
}
my @rates = retrieve_rates($hop_target1, $hop_target2);
printf ("%.0f\n%.0f\n", $rates[0], $rates[1]);


#################
#
#  End
