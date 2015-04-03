#!/usr/bin/perl
#
# Copyright (C) 2006-2015 by John P. Weiss
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
# $Id$
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
my $_DaemonPIDFile = "/var/run/mrtg-ping-bandwidth.pid";
my $_DaemonLog = "/var/log/mrtg-ping-bandwidth.log";
my $_LatencyNoConnection = 0;
my $_ProbeInterval = 5*60;
my $_ConfigUpdateInterval = 7;
my $_Verbose=1;


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
use Fcntl qw(O_RDONLY);  # For readonly 'tie'
use POSIX qw(nice setsid);


############
#
# Other Global Variables
#
############


# The '-U' option overrides the old, creaky method of hitting "unused" UDP
# ports and instead hits the UDP-DNS port (which should always be an error).
# We could also use the '-I' option to do ICMP, but '-U' will always work
# through a firewall.
my $_TracerouteCmd = "traceroute -4 -n -w 1 -N 1 -U ";
# WARNING:  A packet size above 1k will not work with all hosts.
my $_PingCmd = "/bin/ping -A -n -c 5 -w 5 -s 1024 ";
my @g_Measurements;
my $g_refDataTieObj;


# Stash the defaults of certain config variables.
my $dfl_DataFile = $_DataFile;
my $dfl_DaemonPIDFile = $_DaemonPIDFile;
my $dfl_DaemonLog = $_DaemonLog;


############
#
# Functions
#
############


#
# Basic Utilities
#


sub log2stderr(@) {
    if ($_Verbose) {
        print STDERR @_;
    }
}


sub getErrInfo() {
    my $errno = 0;
    my $errReason = "";
    if (defined($!)) {
        $errno = $! + 0;
        $errReason = "\nReason: \"".$!."\"";
    }

    my $exitVal = ($? >> 8);
    my $sigNum = ($? & 0x7F);
    my $hasCoredump = ($? & 0x80);

    return ($errno, $errReason, $exitVal, $sigNum, $hasCoredump);
}


#
# Ping/Traceroute
#

sub ping_derived_stats($) {
    my $host = shift();

    my $pingcmd=$_PingCmd;
    $pingcmd .= $host;
    $pingcmd .= " 2>&1 |";
    #log2stderr("#DBG#  Running:  $pingcmd\n");
    unless (open(PINGFH, $pingcmd)) {
        print STDERR ("FATAL: Can't run command: ", $pingcmd,
                      "\nReason: \"", $!, "\"\n");
        return (-1, $_LatencyNoConnection);
    }
    my @pingLines = <PINGFH>;
    close(PINGFH);

    my $bytes = 0;
    my $msecs = 0;
    my $n_pings = 0;
    foreach (@pingLines) {
        if (m/(\d+) bytes from .* time=([[:digit:].]+) ms/) {
            $bytes += $1;
            $msecs += $2;
            ++$n_pings;
        }
    }

    my $latency = $_LatencyNoConnection;
    my $rate = $bytes;
    if ($msecs && $n_pings) {
        $latency = $msecs / $n_pings;
        $rate /= $msecs;
        $rate *= 1000;
    } else {
        $rate = 0;
    }

    return ($rate, $latency);
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

    while (<TRTFH>) {
        chomp;
        next unless (m/^\s*\d+\s/);
        my @fields = split();
        if ($fields[1] =~ m/\*/) {
             $hops[$fields[0]] = undef();
        } else {
             $hops[$fields[0]] = $fields[1];
        }
    }

    my $closedOk = close(TRTFH);
    my @errInfo = getErrInfo();
    my $check4DataErrs = 0;
    unless($closedOk && ($errInfo[0] != 10)) {
        my ($errno, $errReason, $exitVal, $sigNum) = @errInfo;
        unless($exitVal == 0) {
            log2stderr("Error closing pipe to command:\n\t",
                       $cmd, $errReason,
                       "\n[Command exit value==", $exitVal, "]\n");
            if ($sigNum < 64) {
                log2stderr("[Command died from signal-", $sigNum, "]\n");
                return ();
            } else {
                log2stderr("\nWarning:  Command died from unknown ",
                           "signal:  ", $sigNum, ".   Attempting\n",
                           "to continue...\n");
                $check4DataErrs = 1;
            }
        }
    }

    if ($check4DataErrs) {
        my $maxHopNum = (sort({$b <=> $a} @$ref_hop_numbers))[0];
        if (scalar(@hops) <= $maxHopNum) {
            log2stderr("Data missing.  Cowardly refusing to return ",
                       "incomplete data.\n");
            return ();
        }
        # N.B.  The caller, 'update_config()' handles 'undef' hop-IPs, reusing
        # the existing value.  So there's no need to check that there are
        # enough defined items in '@hops'.  Missing IPs are even logged.
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


sub read_config(\$\@\@\@;$) {
    my $ref_remote_host = shift();
    my $ref_hop_numbers = shift();
    my $ref_measurement_targets = shift();
    my $ref_show_latency = shift();
    my $isRereading = (scalar(@_) ? shift() : 0);


    build_cfgfile_name();

    my %options=();
    my $array_option="";

    if ($isRereading) {
        log2stderr("Rereading config file:  ", $_ConfigFile, "\n");
    }

    open(IN_FS, "$_ConfigFile")
        or die("Unable to open file for reading: \"$_ConfigFile\"\n".
               "Reason: \"$!\"\n");

    while (<IN_FS>) {
        my $line = $_;
        chomp $line; # Remove newline
        study $line;

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

    #log2stderr("#DBG# ", Dumper(\%options), "\n");

    $$ref_remote_host = $options{"remote_host"};
    @$ref_hop_numbers = @{$options{"hop_numbers"}};
    @$ref_measurement_targets = @{$options{"measurement_targets"}};
    if (exists($options{"show_latency"})) {
        @$ref_show_latency = @{$options{"show_latency"}};
    } else {
        @$ref_show_latency = (0) x scalar(@$ref_measurement_targets);
    }
    if (exists($options{"ProbeInterval"})) {
        $_ProbeInterval = $options{"ProbeInterval"};
    }
    if (exists($options{"ConfigUpdateInterval"})) {
        $_ConfigUpdateInterval = $options{"ConfigUpdateInterval"};
    }
    if (exists($options{"Latency_noConnection"})) {
        $_LatencyNoConnection = $options{"Latency_noConnection"};
    }
    if (exists($options{"VerboseLogging"})) {
        $_Verbose = $options{"VerboseLogging"};
    }
    if (exists($options{"DaemonLog"})) {
        $_DaemonLog = $options{"DaemonLog"};
    }
    if (exists($options{"_DataFile"})) {
        $_DataFile = $options{"_DataFile"};
    }
    if (exists($options{"_DaemonPIDFile"})) {
        $_DaemonPIDFile = $options{"_DaemonPIDFile"};
    }

    if ($isRereading) {
        log2stderr("\tFinished rereading configuration.\n");
        log2stderr("\tNew values:\n");
        foreach my $k (keys(%options)) {
            log2stderr("\t\t", $k, " = ");
            if (ref($options{$k})) {
                log2stderr("(\n\t\t\t",
                           join("\n\t\t\t", @{$options{$k}}),
                           "\n\t\t)\n");
            } else {
                log2stderr("\"", $options{$k}, "\"\n");
            }
        }
    }
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
        $targAdded = -1;
        $min_n = $#{$ref_new};
    }

    my $noTargsChanged = 1;
    foreach my $targ_idx (0 .. $min_n) {
        if ($ref_old->[$targ_idx] ne $ref_new->[$targ_idx]) {
            log2stderr("Target #", $targ_idx + 1, " Changed:\t",
                       $ref_old->[$targ_idx],
                       "   -->   ",
                       $ref_new->[$targ_idx], "\n");
            $noTargsChanged = 0;
        }
    }

    foreach my $targ_idx (($min_n+1) .. $max_n) {
        log2stderr("Target #", $targ_idx + 1, " ",
                   $targChangetypeMsg, ":\t",
                   ( ($targAdded > 0)
                     ? $ref_new->[$targ_idx]
                     : $ref_old->[$targ_idx] ),
                   "\n");
    }

    if ($noTargsChanged && ($targAdded == 0)) {
        log2stderr("No Target hosts changed.  No configuration ",
                   "update needed.\n");
    }
}


sub write_config($\@\@\@) {
    my $remote_host = shift();
    my $ref_hop_numbers = shift();
    my $ref_measurement_targets = shift();
    my $ref_show_latency = shift();

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
    print CFGFH ("show_latency = (\n\t",
                 join("\n\t", @$ref_show_latency),
                 "\n)\n");
    print CFGFH ("ProbeInterval = ", $_ProbeInterval, "\n");
    print CFGFH ("ConfigUpdateInterval = ", $_ConfigUpdateInterval, "\n");
    print CFGFH ("Latency_noConnection = ", $_LatencyNoConnection, "\n");
    print CFGFH ("VerboseLogging = ", $_Verbose, "\n");

    # For the next 3 settings, save it to the configfile *only* if it's
    # changed from the default.

    if ($_DaemonLog ne $dfl_DaemonLog) {
        print CFGFH ("DaemonLog = ", $_DaemonLog, "\n");
    }
    if ($_DaemonPIDFile ne $dfl_DaemonPIDFile) {
        print CFGFH ("_DaemonPIDFile = ", $_DaemonPIDFile, "\n");
    }
    if ($_DataFile ne $dfl_DataFile) {
        print CFGFH ("_DataFile = ", $_DataFile, "\n");
    }

    close CFGFH;
    return 1;
}


sub update_config($\@\@;\@) {
    my $remote_host = shift();
    my $ref_hop_numbers = shift();
    my $ref_show_latency = shift();
    my $ref_orig_targets = (scalar(@_) ? shift() : undef());

    unless (($remote_host ne "") && are_numbers(@$ref_hop_numbers)) {
        usage();
    }

    log2stderr("Updating configuration file with route changes...\n");
    my @measurement_targets = get_hop_ips($remote_host, @$ref_hop_numbers);

    my $errmsg = "";
    my $warnStart = 1;
    if (scalar(@measurement_targets)) {
        foreach my $idx (0 .. $#measurement_targets) {
            unless (defined($measurement_targets[$idx])) {
                if ($warnStart) {
                    log2stderr("Failed to retrieve all hops from host: ",
                               $remote_host, "\n");
                    $warnStart = 0;
                }
                log2stderr("\tMissing hop \#",
                           $ref_hop_numbers->[$idx]);
                if (defined($ref_orig_targets->[$idx])) {
                    log2stderr(".  Reusing:  ",
                               $ref_orig_targets->[$idx]);
                }
                else {
                    log2stderr(".");
                }
                log2stderr("\n");
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
        write_config($remote_host, @$ref_hop_numbers,
                     @measurement_targets, @$ref_show_latency);
        log2stderr("Configuration update complete.\n");
    } else {
        log2stderr($errmsg, "\n");
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
        $ref_tied = tie(@measurements, 'Tie::File', $_DataFile,
                        mode => 'O_RDONLY');
        if (!defined($ref_tied) && (($! ne "") || ($@ ne ""))) {
            $failureReason = $!;
            if (($failureReason ne "") && ($@ ne "")) {
                $failureReason .= "\n";
            }
            $failureReason .= $@;
        }
        ++$attempts;
    } while ((!defined($ref_tied) || !scalar(@measurements)) &&
             ($attempts < $_TieAttempts));

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

    # Cleanup
    undef($ref_tied);
    untie(@measurements);

    # //Now// we can return.
    return @result;
}


#
# Daemon-related
#


sub daemonize(;$) {
    my $keepParentRunning = (scalar(@_) ? shift() : 0);

    defined(my $pid = fork) or die "Can't fork: $!";
    if ($pid) {
        if ($keepParentRunning) {
            return 1;
        } else {
            exit 0;
        }
    }
    # else:  We're the child, which we'll use to create the daemon.

    chdir "/tmp"            or die "Can't chdir to /tmp: $!";
    open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
    open STDOUT, ">>$_DaemonLog"
        or die "Can't write to $_DaemonLog: $!";
    open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";

    defined(my $pid = fork) or die "Can't fork: $!";
    exit 0 if ($pid);
    #else:  We're the (grand)child;

    setsid                  or die "Can't start a new session: $!";
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


sub check_for_no_running_daemon($) {
    my $daemonPIDFile = shift();

    # Check that the PID file exists.
    return 1 unless (-e $daemonPIDFile);

    # Check if the process is running.
    open(PIDFH, "<", $daemonPIDFile) or return 1;
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
    #return 0 if (scalar(@match));
    ## Don't use "system()", as it discards the output.

    print STDERR ("Process '", $daemonPid, "' not found.\n");
    print STDERR ("Check for dead/stale PID file:  \"", $daemonPIDFile,
                  "\"\n");
    return 1;
}


sub no_running_daemon() {
    my $notRunning = check_for_no_running_daemon($_DaemonPIDFile);
    if ($dfl_DaemonLog ne $_DaemonPIDFile) {
        # We need to check for both PID files, regardless what the first check
        # returned.  (There might be a dead PID file with the default name
        # kicking around, after all.)
        my $dflCheck = check_for_no_running_daemon($dfl_DaemonPIDFile);
        # We MUST do this seperately, to avoid the side-effects of the '&&'
        # operator.
        $notRunning = $notRunning && $dflCheck;
    }
    return $notRunning;
}


sub daemon_sig_cleanup {
    my $killsig=shift();

    untie(@g_Measurements);
    undef($g_refDataTieObj);
    unlink($_DaemonPIDFile, $_DataFile);

    if (($killsig == 1) || ($killsig == 2) || ($killsig == 15)) {
        exit 0;
    } # else
    exit $killsig;
}


sub daemon_main(\@$\@\@) {
    my @measurement_targets = @{shift()};
    my $remote_host = shift();
    my @hop_numbers = @{shift()};
    my @show_latency = @{shift()};

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
        } elsif ($signame =~ m/USR1/) {
            # Use a closure to define the "reload-the-configfile" handler.
            $SIG{$signame} = sub {
                read_config($remote_host, @hop_numbers,
                            @measurement_targets, @show_latency, 1);
            };
        } else {
            $SIG{$signame} = \&daemon_sig_cleanup;
        }
    }

    # Tie an array to the data file, retrying as needed.
    #
    $g_refDataTieObj = tie(@g_Measurements, 'Tie::File', $_DataFile);
    if (!defined($g_refDataTieObj) && (($! ne "") || ($@ ne ""))) {
        my $failureReason = $!;
        if (($failureReason ne "") && ($@ ne "")) {
            $failureReason .= "\n";
        }
        $failureReason .= $@;
        print STDERR ("Failed to tie array to file: \"", $_DataFile, "\".\n",
                      "Reason: \"", $failureReason, "\"\n");
    }
    $g_refDataTieObj->autodefer(0);  # Don't guess when to cache writes.

    #
    # The Main Loop
    #

    my $configUpdateInterval_secs = $_ConfigUpdateInterval * 24 * 3600;
    my $nextConfigUpdate = time() + $configUpdateInterval_secs;
    my ($rate, $latency);
    while (1) {
        my $probe_duration = -time();
        my $network_state = 1;
        foreach my $idx (0 .. $#measurement_targets) {
            ($rate,
             $latency) = ping_derived_stats($measurement_targets[$idx]);
            $g_Measurements[$idx] = ($show_latency[$idx] ? $latency : $rate);
            $network_state *= $g_Measurements[$idx];
        }

        # Rebuild the config from time to time.
        #
        if (($network_state != 0) && (time() > $nextConfigUpdate)) {
            @measurement_targets = update_config($remote_host,
                                                 @hop_numbers,
                                                 @show_latency,
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


sub start_daemon($\@$\@\@) {
    my $keepParentRunning = shift();
    my $ref_measurement_targets = shift();
    my $remote_host = shift();
    my $ref_hop_numbers = shift();
    my $ref_show_latency = shift();

    # daemonize() either exits the parent process or returns 0.
    daemonize($keepParentRunning) or return 0;

    # We're the child process if we reach this point.
    renice_self();
    daemon_main(@$ref_measurement_targets, $remote_host,
                @$ref_hop_numbers, @$ref_show_latency);
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
    print STDERR ("In the configfile, \"ProbeInterval\" is in seconds, ",
                  "while\n\"ConfigUpdateInterval\" is in days.\n");
    print STDERR ("\nRun Modes:\n\n");
    print STDERR ("'-c':  (Re)creates the configfile.  <host> is the ",
                  "traceroute target\n");
    print STDERR ("       to monitor.  The <host> is always monitored.\n");
    print STDERR ("       Using this option completely overwrites any ",
                  "existing\n");
    print STDERR ("       configuration file.  So save a copy of your ",
                  "current settings\n");
    print STDERR ("       first, then and merge in the new 'remote_host', ",
                  "'hop_numbers',\n");
    print STDERR ("       and 'measurement_targets' (and possibly ",
                  "'show_latency', if you\n");
    print STDERR ("        never customized it).\n");
    print STDERR ("'-d':  Run in daemon mode.  Refreshes the configfile on ",
                  "init if you\n");
    print STDERR ("       specify the other commandline args (which behave ",
                  "just like\n");
    print STDERR ("       the ones for '-c' mode and will overwrite any ",
                  "existing configfile).\n");
    print STDERR ("'-b':  Run in one-shot ping mode.  Checks one or two ",
                  "destination hosts,\n");
    print STDERR ("       as required by MRTG.\n");
    print STDERR ("       The results (both throughput and latency)  are ",
                  "returned in a\n");
    print STDERR ("       human-readable format.\n");
    print STDERR ("<no-option>:\n");
    print STDERR ("       Returns the last throughput/latency check from an ",
                  "instance of this\n");
    print STDERR ("       script already running in '-d' mode.  Returns the ",
                  "throughput or\n");
    print STDERR ("       latency for the specified targets.  The ",
                  "<target#> is the\n");
    print STDERR ("       list index of the IPs/hosts being monitored.  ",
                  "So, if you ran '-c'\n");
    print STDERR ("       with the hop-list '3,5,6,11', then <target#>==3 ",
                  "would return the\n");
    print STDERR ("       throughput (or latency) of hop-#6, while ",
                  "<target#>==5 would\n");
    print STDERR ("       return the throughput (or latency) of the target",
                  "host.\n");
    print STDERR ("'-r':  Identical to the previous mode, but will start a ",
                  "daemon if one\n");
    print STDERR ("       isn't already running.\n");

    print STDERR ("\nTo kill a daemonized instance, use:\n\t",
                  "kill \$(\< ", $_DaemonPIDFile, ")\n\n",
                  "Use a '-USR1' signal to reread the configuration file.\n");
    print STDERR ("\nTo list the througput of all targets, in order, ",
                  "use:\n\t",
                  "cat ", $_DataFile,
                  "\n...or whatever you've set \"_DataFile\" to in the ",
                  "configuration file.\n");
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
    my @rate1 = ping_derived_stats(shift(@ARGV));
    if ($rate1[0] < 0) { exit 1; }
    my @rate2 = @rate1;
    if (scalar(@ARGV)) {
        @rate2 = ping_derived_stats(shift(@ARGV));
        if ($rate2[0] < 0) { exit 1; }
    }
    printf "(%d kB/s, %d ms)\n(%d kB/s, %d ms)\n", @rate1, @rate2;
    exit 0;
}

#
# Read the configuration.
# (Generate a new configfile when run with '-c' or '-d'.)
#
my $remote_host;
my @hop_numbers;
my @measurement_targets;
my @show_latency;
if ($update_hop_ips) {
    # Note:  If run with the '-d' option, we'll only reach here if there were
    # other args following the '-d'.
    @hop_numbers = split(/,/, shift(@ARGV));
    $remote_host = shift(@ARGV);
    my @no_latency = (0) x (scalar(@hop_numbers) + 1);
    @measurement_targets = update_config($remote_host,
                                         @hop_numbers,
                                         @no_latency);
    exit 0 unless ($daemonize);
} else {
    read_config($remote_host, @hop_numbers,
                @measurement_targets, @show_latency);
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
                     @measurement_targets, $remote_host,
                     @hop_numbers, @show_latency);

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
