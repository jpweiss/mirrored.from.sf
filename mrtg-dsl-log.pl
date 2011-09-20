#!/usr/bin/perl
#
# Copyright (C) 2011 by John P. Weiss
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
# Configurable Variables
#
############


my $_ConfigFile = undef();
my $_UpdateInterval = 5*60;
my $_DaemonLog = "/tmp/mrtg-dsl-log.log";
my $_DataFile = "/dev/shm/mrtg-dsl-log.dat";
my $_DaemonPIDFile = "/var/run/mrtg-dsl-log.pid";
my $_GetURLVia = 'curl';
my $_DropCountInterval = 3600;
my $_TieAttempts = 5;
my $_TieWait = 1;
my $_PostDaemonizeWait = 5;


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
use Date::Parse;
use Term::ReadKey;
use Tie::File;
use Fcntl qw(O_RDONLY O_APPEND O_CREAT);  # For use with 'tie'
use POSIX qw(nice setsid);
use Data::Dumper;


############
#
# Other Global Variables
#
############


my %_WebGet = ( 'curl' => { 'cmd' => "/usr/bin/curl",
                            'args' => " -4 -s ",
                            'user_arg' => " -u ",
                            'passwd_arg' => ":"
                          },
                'wget' => { 'cmd' => "/usr/bin/wget",
                            'args' => " -4 -q -O - ",
                            'user_arg' => " -user ",
                            'passwd_arg' => " -passwd "
                          }
              );

# Constants used in the time-format hash.  Prevents inconsistencies due to
# typos.
my $c__tfmt_common_ddmmyyyyAMPM
    = '(\d\d.\d\d.\d\d\d\d\s+\d\d:\d\d:\d\d\s+[AP]M)';
my $c__tfmt_common_yyyymmdd = '(\d\d\d\d.\d\d.\d\d\s+\d\d:\d\d:\d\d)';
my $c__tfmt_common_yyyymmddAMPM
     = '(\d\d\d\d.\d\d.\d\d\s+\d\d:\d\d:\d\d\s+[AP]M)';
my %_TimeFormats = ( 'yyyy-mm-dd HH:MM:SS' => $c__tfmt_common_yyyymmdd,
                     'yyyy/mm/dd HH:MM:SS' => $c__tfmt_common_yyyymmdd,
                     'yyyy-mm-dd HH:MM:SS AM' => $c__tfmt_common_yyyymmddAMPM,
                     'yyyy-mm-dd HH:MM:SS PM' => $c__tfmt_common_yyyymmddAMPM,
                     'yyyy/mm/dd HH:MM:SS AM' => $c__tfmt_common_yyyymmddAMPM,
                     'yyyy/mm/dd HH:MM:SS PM' => $c__tfmt_common_yyyymmddAMPM,
                     'dd/mm/yyyy HH:MM:SS AM' => $c__tfmt_common_ddmmyyyyAMPM,
                     'dd/mm/yyyy HH:MM:SS PM' => $c__tfmt_common_ddmmyyyyAMPM,
                     'dd-mm-yyyy HH:MM:SS AM' => $c__tfmt_common_ddmmyyyyAMPM,
                     'dd-mm-yyyy HH:MM:SS PM' => $c__tfmt_common_ddmmyyyyAMPM,
                   );

my @_Measurements;
my $_refDataTieObj;

my $c_tsIdx = 0;
my $c_HRT_Idx = 1;
my $c_UpDownIdx = 2;
my $c_nDropsIdx = 3;


############
#
# Functions
#
############


# Forward decls.
sub updateMRTGdata(\@$$);


#
# Utilities
#


sub checkForErrors_tie($$$$) {
    my $errnoName = shift();
    my $reason = shift();
    my $ref_tied = shift();
    my $datafile = shift();

    if (!defined($ref_tied) && (($errnoName ne "") || ($reason ne ""))) {
        my $failMessage = "Failed to tie array to file: \"";
        $failMessage .= $datafile;
        $failMessage .= "\".\nReason: \"";
        $failMessage .= $errnoName;
        $failMessage .= "\"";
        if ($reason ne "") {
            $failMessage .= "\n";
        }
        $failMessage .= $reason;
        $failMessage .= "\n";
        return $failMessage;
    } # else
    return undef;
}


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


sub convert2secs($) {
    my $timeStr = shift();

    my $secs = 0;

    # Process any units-suffix:
    if ($timeStr =~ m/^(.*)\s*s$/) {
        # Units of seconds.  Nothing to do to the number.
        $secs = $1;
    }
    elsif ($timeStr =~ m/^(.*)\s*([mh])$/) {
        $secs = $1;
        if ($2 eq "h") {
            $secs *= 60;
        }
    }
    # Convert min. to sec.
    $secs *= 60;

    return $secs;
}


sub t2DropCountInterval($;$) {
    my $t = shift();
    my $returnIntervalEnd = (scalar(@_) ? shift() : 0);

    my $timeUptdInterval = $t - ($t % $_DropCountInterval);
    if ($returnIntervalEnd) {
        $timeUptdInterval += $_DropCountInterval;
    }
    return $timeUptdInterval;
}


#
# Configfile Processing
#


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


sub validate_options(\%) {
    my $ref_options = shift();

    if (exists($ref_options->{"MRTG_LogDir"})) {
        unless ((-d $ref_options->{"MRTG_LogDir"}) &&
                (-w $ref_options->{"MRTG_LogDir"}))
        {
            print STDERR ("ERROR:  Parameter 'MRTG_LogDir' set to ",
                          "bad value.\n",
                          "Not a directory or not writeable:  \"",
                          $ref_options->{"MRTG_LogDir"},
                          "\"\n\n",
                          "Cowardly refusing to continue.\n");
            exit 2;
        }
    } else {
        print STDERR ("ERROR:  Configuration file parameter 'MRTG_LogDir' ",
                      "not set.\n\n",
                      "Cowardly refusing to continue.\n");
        exit 2;
    }

    if (exists($ref_options->{"Our_MRTG_DataFile"})) {
        my $mrtg_log_file = $ref_options->{"MRTG_LogDir"};
        unless ($mrtg_log_file =~ m|/$|) {
            $mrtg_log_file .= '/';
        }
        $mrtg_log_file .= $ref_options->{"Our_MRTG_DataFile"};
        unless ((-e $mrtg_log_file) && (-w $mrtg_log_file)) {
            print STDERR ("ERROR:  Parameter 'Our_MRTG_DataFile' set to ",
                          "bad value.\n",
                          "File doesn't exist or isn't writeable:  \"",
                          $mrtg_log_file, "\"\n\n",
                          "Cowardly refusing to continue.\n");
            exit 2;
        }

        # Constructed Options:
        $ref_options->{"_MRTG_Data_"} = $mrtg_log_file;
        $ref_options->{"_MRTG_Updated_Data_"} = $mrtg_log_file;
        $ref_options->{"_MRTG_Updated_Data_"} .= '-new'
    } else {
        print STDERR ("ERROR:  Configuration file parameter ",
                      "'Our_MRTG_DataFile' not set.\n\n",
                      "Cowardly refusing to continue.\n");
        exit 2;
    }
}


sub read_config(\%;$) {
    my $ref_options = shift();
    my $isRereading = (scalar(@_) ? shift() : 0);


    build_cfgfile_name();

    %$ref_options = ();
    my $array_option = "";

    if ($isRereading) {
        print STDERR ("Rereading config file:  ", $_ConfigFile, "\n");
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
            push @{$ref_options->{$array_option}}, $line;
            next;
        }

        # Get the option name and value, trimming whitespace on either side of
        # the delimiter characters.  Also trim any quotes that are around the
        # value.
        $line =~ m/^(\S+)\s*[:=]\s*(.*)$/;
        my $optname = $1;
        my $val = $2;
        for ($val) {
            s/^['"]//;
            s/['"]$//;
        }

        # Special handling:
        # This is the start of an array parameter.
        if ($val eq "(") {
            $array_option = $optname;
            $ref_options->{$array_option} = [ ];
            next;
        }

        # Regular option processing
        $ref_options->{$optname} = $val;
    }
    close IN_FS;

    #print STDERR ("#DBG# ", Dumper($ref_options), "\n");

    #
    # Process Options & Compute Params (not requiring validation) 
    #

    if (exists($ref_options->{"UpdateInterval"})) {
        $_UpdateInterval = convert2secs($ref_options->{"UpdateInterval"});
    }

    unless (exists($_TimeFormats{$ref_options->{"TimeFormat"}})) {
        print STDERR ("ERROR:  Bad value:  \"",
                      $ref_options->{"TimeFormat"}, "\"\n",
                      "Parameter 'TimeFormat' must be set to ",
                      "one of the following:\n",
                      "\t\"", join("\"\n\t\"", keys(%_TimeFormats)),
                      "\"\n\n",
                      "Cowardly refusing to continue.\n");
        exit 2;
    }
    $ref_options->{"_Time_Regexp_"}
        = $_TimeFormats{$ref_options->{"TimeFormat"}};

    if (exists($ref_options->{"_DaemonLog"})) {
        $_DaemonLog = $ref_options->{"_DaemonLog"};
    }

    # Advanced Config Options:
    if (exists($ref_options->{"_DataFile"})) {
        $_DataFile = $ref_options->{"_DataFile"};
    }
    if (exists($ref_options->{"_DaemonPIDFile"})) {
        $_DaemonPIDFile = $ref_options->{"_DaemonPIDFile"};
    }
    if (exists($ref_options->{"_GetURLVia"})) {
        $_GetURLVia = $ref_options->{"_GetURLVia"};
        unless (exists($_WebGet{$_GetURLVia})) {
            print STDERR ("ERROR:  Parameter '_GetURLVia' must be set to ",
                          "one of the following:\n",
                          "\t", join("\n\t", keys(%_WebGet)),
                          "\n\n",
                          "Cowardly refusing to continue.\n");
            exit 2;
        }
    }


    if ($isRereading) {
        # Only validate the options in daemon-mode.  Since rereading only
        # happens during daemon-mode, we can call
        # 'validate_options()' here.
        validate_options(%$ref_options);

        print STDERR ("    Finished rereading configuration.\n");
        print STDERR ("    New values:\n");
        foreach my $k (sort(keys(%$ref_options))) {
            print STDERR ("\t", $k, " = ");
            if (ref($ref_options->{$k})) {
                print STDERR ("(\n\t\t",
                              join("\n\t\t", @{$ref_options->{$k}}),
                              "\n\t)\n");
            } else {
                print STDERR ("\"", $ref_options->{$k}, "\"\n");
            }
        }
    }

    return 1;
}


sub readSilent($)
{
    my $msg = shift();

    print $msg, "> ";
    ReadMode('cbreak');
    my $val1='';
    my $c = ReadKey(0);
    while ($c ne "\n") {
        print "*";
        $val1 .= $c;
        $c = ReadKey(0);
    }
    print "\n";

    print "Verify:  re-enter what you just typed> ";
    my $val2='';
    $c = ReadKey(0);
    while ($c ne "\n") {
        print "*";
        $val2 .= $c;
        $c = ReadKey(0);
    }
    print "\n";

    ReadMode('normal');

    if ($val1 eq $val2) {
        return $val1;
    } #else:  Error
    print "Typo:  Values do not match.\n";
    return undef;
}


#
# Parsing & Processing "Web Pages" from the  DSL Modem
#


sub parse_syslog($$$$$$$\@) {
    my $how = shift();
    my $url = shift();
    my $user = shift();
    my $passwd = shift();
    my $dslUp_re = shift();
    my $dslDown_re = shift();
    my $time_re = shift();
    my $ref_dslState = shift();

    # Build the command string separately from the authorization credentials.
    my $auth = "";
    if ( ($user ne "") && ($passwd ne "") ) {
        $auth = $_WebGet{$how}{'user_arg'};
        $auth .= $user;
        $auth .= $_WebGet{$how}{'passwd_arg'};
        $auth .= $passwd;
        $auth .= " ";
    }

    my $getUrl_cmd = $_WebGet{$how}{'cmd'};
    $getUrl_cmd .= $_WebGet{$how}{'args'};
    my $http_fh;
    unless (open($http_fh, '-|', $getUrl_cmd . $auth . $url)) {
        print STDERR ("FATAL: Can't run command: ", $getUrl_cmd, $url,
                      "\nReason: \"", $!, "\"\n");
        return 0;
    }
    my @logLines = <$http_fh>;
    close($http_fh);

    my %n_dropped = ();
    my @parsedData = ();
    foreach (@logLines) {
        s/\r$//;
        chomp;
        study;

        m/$time_re/o or next;
        my $timestamp = $1;
        my $time_sec = str2time($timestamp);
        if ($time_sec == 0) {
            # Some DSL modems have their clocks set to epoch on boot.  For
            # those log entries, use the current time.
            $time_sec = time();
        }
        my $timeUptdInterval = t2DropCountInterval($time_sec);

        unless (exists($n_dropped{$timeUptdInterval})) {
            $n_dropped{$timeUptdInterval} = 0;
        }

        if (m/$dslUp_re/o) {
            push(@parsedData, [$time_sec, $timestamp,
                               1, $n_dropped{$timeUptdInterval}]);
        } elsif (m/$dslDown_re/o) {
            ++$n_dropped{$timeUptdInterval};
            push(@parsedData, [$time_sec, $timestamp,
                               0, $n_dropped{$timeUptdInterval}]);
        }
    }

    # Sort the new data, in ascending order.
    #
    @$ref_dslState = sort({ $a->[$c_tsIdx] <=> $b->[$c_tsIdx] } @parsedData);
}


sub removeDuplicatesAndAdjust(\@$$) {
    my $ref_events = shift();
    my $t_lastEvent = shift();
    my $nDropped_last = shift();

    # 'parse_syslog()' may have been called in the middle of the
    # '$_DropCountInterval'.  If the first new event is still in that
    # interval, we need to start the drop count with whatever it was at the
    # end of the last call to 'parse_syslog()'.
    my $lastEvent_UptdInterval_end = t2DropCountInterval($t_lastEvent, 1);

    my @duplicates = ();
    foreach my $idx (0 .. $#$ref_events) {
        # The last update time == $ref_events->[$idx][$c_tsIdx]
        my $t_event = $ref_events->[$idx][$c_tsIdx];
        if ($t_event <= $t_lastEvent) {
            push(@duplicates, $idx);
        } elsif ($t_event < $lastEvent_UptdInterval_end) {
            # This event is in the '$_DropCountInterval' from last time.
            # Update the event with the correct offset.
            $ref_events->[$idx][$c_nDropsIdx] += $nDropped_last;
        }
    }

    # Last, prune the duplicates.
    if (scalar(@duplicates)) {
        delete @$ref_events->[@duplicates];
    }
}


sub resetStaleDropCounts(\@$\@) {
    my $ref_newEvents = shift();
    my $currentTime = shift();
    my $ref_lastEvent = shift();

    my @event = @$ref_lastEvent;
    my $timeSinceLastEvent = $currentTime - $event[$c_tsIdx];

    # Do nothing unless the last event is older than 125% of the
    # '$_DropCountInterval'.  The extra 25% is to give the reset a buffer.
    return if ($timeSinceLastEvent <= 1.25*$_DropCountInterval);

    # If the connection is still down, do nothing.  If the connection is up,
    # but the drop-count is already 0, do nothing.
    return if ( ($event[$c_UpDownIdx] == 0) ||
                ($event[$c_nDropsIdx] == 0) );

    $event[$c_tsIdx] = $currentTime;
    $event[$c_HRT_Idx] = localtime();
    $event[$c_nDropsIdx] = 0;
    push(@$ref_newEvents, \@event);
}


#
# Functions for handling event data
#


sub printEvent($\@) {
    my $fh = shift();
    my $ref_event = shift();

    my $hrt = $ref_event->[$c_HRT_Idx];
    $hrt =~ s/\s+/ /g;
    print $fh ($hrt, ":    DSL connection ");
    print $fh ($ref_event->[$c_UpDownIdx] ? "came back up" : "went down");
    printf $fh ("\t    (%10ds)\n", $ref_event->[$c_tsIdx]);
}


sub startup_eventDefaultValue() {
    my @defaultInitialEvent = ();
    $defaultInitialEvent[$c_UpDownIdx] = 1;
    $defaultInitialEvent[$c_nDropsIdx] = 0;
    $defaultInitialEvent[$c_HRT_Idx] = localtime();
    $defaultInitialEvent[$c_tsIdx] = time();
    return \@defaultInitialEvent;
}


sub eventArray2tieArrayElement(\@) {
    my $ref_event = shift();

    my $element = '[[';
    $element .= $ref_event->[$c_UpDownIdx];
    $element .= ';|;';
    $element .= $ref_event->[$c_nDropsIdx];
    $element .= ';|;';
    # Time gets stored at the end.
    $element .= $ref_event->[$c_HRT_Idx];
    $element .= ';|;';
    $element .= $ref_event->[$c_tsIdx];
    $element .= ']]';

    return $element;
}


sub tieArrayElement2eventArray($;$) {
    my $tieElement = shift();
    my $keepTieArrayOrder = (scalar(@_) ? shift() : 0);
    study $tieElement;

    my @eventArray = (undef) x 4;
    if ( ($tieElement =~ m/^\[\[/) && ($tieElement =~ m/\]\]$/) ) {
        $tieElement =~ s/^\[\[//;
        $tieElement =~ s/\]\]$//;
        my @eventArrayTAO = split(/;\|;/, $tieElement);

        if ($keepTieArrayOrder) {
            @eventArray = @eventArrayTAO;
        } else {
            $eventArray[$c_UpDownIdx] = $eventArrayTAO[0];
            $eventArray[$c_nDropsIdx] = $eventArrayTAO[1];
            $eventArray[$c_HRT_Idx] = $eventArrayTAO[2];
            $eventArray[$c_tsIdx] = $eventArrayTAO[3];
        }
    }

    return @eventArray;
}


sub event2MRTGData_arrayref(\@) {
    my $ref_event = shift();

    ## The @MRTG_Data elements are arrayrefs with 5 elements:
    ## 0 :== timestamp
    ## 1 :== avg "in" value since the last measurement.
    ## 2 :== avg "out" value since the last measurement.
    ## 3 :== max "in" value since the last measurement.
    ## 4 :== max "out" value since the last measurement.
    ##
    ## We want to make the max & avg the same.

    my @elements = ($ref_event->[$c_tsIdx],
                    $ref_event->[$c_UpDownIdx],
                    $ref_event->[$c_nDropsIdx],
                    $ref_event->[$c_UpDownIdx],
                    $ref_event->[$c_nDropsIdx]);

    return \@elements;
}


sub retrieve_rates($$) {
    my $targ1 = (defined($_[0]) ? shift() : 0);
    my $targ2 = (defined($_[0]) ? shift() : 0);

    # Process the args
    unless (are_numbers($targ1, $targ2)) {
        usage();
    }

    # Tie an array to the data file, retrying as needed.
    my @measurements;
    my $ref_tied=undef();
    my $data_fh;
    my $attempts=0;
    my $failure = undef();
    do {
        if ($attempts) {
            sleep($_TieWait);
        }
        $ref_tied = tie(@measurements, 'Tie::File', $_DataFile,
                        'mode' => O_RDONLY);
        $failure = checkForErrors_tie($!, $@, $ref_tied, $_DataFile);
        ++$attempts;
        #print STDERR ("#DBG# TieAttempts: ",$attempts,"\n");
    } while ((!defined($ref_tied) || !scalar(@measurements)) &&
             ($attempts < $_TieAttempts));

    # Handle failed tie-attempt.
    if (defined($failure) || !scalar(@measurements)) {
        if (defined($failure)) {
            print STDERR ($failure);
        } else { #!scalar(@measurements)
            print STDERR ("No measurements present in file: \"",
                          $_DataFile, "\".\n",
                          "(Is the daemon running?)\n");
        }
        return (0, 0);
    }

    # We're ready!  Retrieve the two measurements.
    my @result = tieArrayElement2eventArray($measurements[$#measurements], 1);
    my $nMeasures = scalar(@result);
    if (($targ1 < 0) || ($targ1 > $nMeasures)) {
        $targ1 = $c_UpDownIdx;
    }
    if (($targ1 < 0) || ($targ2 > $nMeasures)) {
        $targ2 = $c_UpDownIdx;
    }

    # Cleanup
    undef($ref_tied);
    untie(@measurements);

    # Postprocessing

    foreach my $t ($targ1, $targ2) {
        # FIXME:  I should really make a set of constants for the
        # @_Measurements indices.
        next unless ($t == 1);
        my $t_UptdInterval_end = t2DropCountInterval($result[$#result], 1);
        my $now = time();
        if ($now >= $t_UptdInterval_end) {
            # The most recent data might be from an earlier
            # '$_DropCountInterval'.  If so, then we need to reset the drop
            # count.
            $result[$t] = 0;
        }
    }

    # //Now// we can return.
    return ($result[$targ1], $result[$targ2]);
}


# Utility for post-processing a log file into tied-array elements.
sub myLogfile2tieArrayElement($) {
    my $logfile = shift();

    my %ndn = ();
    my %seen = ();
    open(LFH, "$logfile")
        or die("Unable to open file for reading: \"$logfile\"\n".
               "Reason: \"$!\"\n");

    while (<LFH>) {
        study;
        if ( m/^(.+[AP]M):.+DSL connection ([^(]+)\((\d+)s/ ||
             m/^(.+):[^:]+DSL connection ([^(]+)\((\d+)s/ )
        {
            my $hrt = $1;
            my $isUp = $2;
            my $ts = $3;
            my $tsh = ($ts - ($ts%3600));

            unless (exists($ndn{$tsh})) {
                $ndn{$tsh} = 0;
            }
            $seen{$tsh} = 1;

            if ($isUp =~ m/back up/) {
                $isUp = 1;
            } else {
                $isUp = 0;
                ++$ndn{$tsh} unless($seen{$ts});
            }

            $seen{$ts} = 1;
            $seen{$tsh} = 1;

            print ("[[", $isUp, ";|;", $ndn{$tsh}, ";|;", $hrt,
                   ";|;", $ts, "]]\n");
            print;
        }
    }
    close(LFH);

    exit 0;
}


# Utility for merging a file with a recovered tie-array with the MRTG data
# log.
sub recoveredTieArray2MRTG($$) {
    my $recoveredDatafile = shift();
    my $mrtgDatafile = shift();

    die ("Cannot recover:  bad args")
        unless (($recoveredDatafile ne "") && ($mrtgDatafile ne ""));

    my $mrtgNewDatafile = $mrtgDatafile . '-nu';

    $_refDataTieObj = tie(@_Measurements, 'Tie::File', $recoveredDatafile,
                          'mode' => O_RDONLY);
    my @unsortedData = ();
    my %seen = ();
    foreach my $entryStr (@_Measurements) {
        my @event = tieArrayElement2eventArray($entryStr);
        unless (exists($seen{$event[$c_tsIdx]})) {
            $seen{$event[$c_tsIdx]} = 1;
            push(@unsortedData, \@event);
        }
    }

    # Sort the new data, in ascending order.  Free the old data (since it
    # might be quite large).
    #
    my @recoveredEvents = sort({ $a->[$c_tsIdx] <=> $b->[$c_tsIdx]
                               } @unsortedData);
    @unsortedData = ();

    updateMRTGdata(@recoveredEvents, $mrtgDatafile, $mrtgNewDatafile);
    exit 0;
}


#
# MRTG Log-Handling
#


sub findRecordsInRange(\@$$) {
    my $ref_data = shift();
    my $minTime = shift();
    my $maxTime = shift();

    # Guard check:
    return (0, 0) unless (scalar(@$ref_data));

    # The times in the MRTG data file are in descending order.

    my @record;
    # Unfortunately, the loop-variable is _always_ local to the
    # 'foreach'-loop.  So, we have to resort to while-loops.
    #
    # Note:  Starting at -1 so that we can increment at the start of the
    #        loop.  Otherwise, we have to "de-increment" $maxIdx after the
    #        loop finishes.
    my $maxIdx = -1;
    do {
        ++$maxIdx;
        @record = split(/\s/, $ref_data->[$maxIdx]);
    } while (($record[0] > $maxTime) && ($maxIdx <= $#$ref_data));

    # Begin the search for the $minIdx where the last one ended.
    #
    # Note:  Again, start the loop at 1 less than the desired position, so
    #        that the loop's first statement is the increment.  Again, this is
    #        to prevent a post-loop "de-increment".
    my $nextLoopStart = $maxIdx - 1;

    # Point $maxIdx to the record in $ref_data that bounds $maxTime "from
    # above".
    if (($record[0] < $maxTime) && ($maxIdx > 0)) {
        --$maxIdx;
    }

    my $minIdx = $nextLoopStart;
    do {
        ++$minIdx;
        @record = split(/\s/, $ref_data->[$minIdx]);
    } while (($record[0] > $minTime) && ($minIdx <= $#$ref_data));
    # "$minIdx" already points to the record in $ref_data that bounds $minTime
    # "from below".  No adjustment needed.

    # Again, the MRTG data is in descending chronological order, so
    # $maxIdx <= $minIdx.
    return ($maxIdx, $minIdx);
}


sub mergeEventsWithMRTG(\@$$\@\@) {
    my $ref_data = shift();
    my $startIdx = shift();
    my $endIdx = shift();
    my $ref_newEvents = shift();
    my $ref_merged = shift();

    # Remember:  @$ref_newEvents is in ascending-order, while @$ref_data is in
    # descending-order.  We have to iterate accordingly, and store the results
    # in descending-order.
    my $eventIdx = $#$ref_newEvents;
    my $dataIdx = $startIdx;
    ++$endIdx;

    while (($dataIdx < $endIdx) && ($eventIdx >= 0)) {
        my @record = split(/\s/, $ref_data->[$dataIdx]);
        my $ref_curEvent_record
            = event2MRTGData_arrayref(@{$ref_newEvents->[$eventIdx]});

        if ($ref_curEvent_record->[0] > $record[0]) {
            push(@$ref_merged, $ref_curEvent_record);
            --$eventIdx;
        } elsif ($ref_curEvent_record->[0] < $record[0]) {
            push(@$ref_merged, \@record);
            ++$dataIdx;
        } else {
            # They're equal.  Keep drop-events.
            if ($record[1] <= $ref_curEvent_record->[1]) {
                push(@$ref_merged, \@record);
                ++$dataIdx;
            } else {
                push(@$ref_merged, $ref_curEvent_record);
                --$eventIdx;
            }
        }
    }

}


sub projectDropCountsForward(\@\@) {
    my $ref_data = shift();
    my $ref_recentEvents = shift();

    # Determine which '$_DropCountInterval's have drop events.
    # Also find the timestamp of the most recent drop event.
    my %updtIntervalHasDropEvents = ();
    my $lastSeenDrop = 0;
    foreach my $ref_event (@$ref_recentEvents) {
        my $ev_t_updtInterval = t2DropCountInterval($ref_event->[$c_tsIdx]);
        unless (exists($updtIntervalHasDropEvents{$ev_t_updtInterval})) {
            $updtIntervalHasDropEvents{$ev_t_updtInterval} = 0;
        }
        if ($ref_event->[$c_UpDownIdx] == 0) {
            $lastSeenDrop = $ref_event->[$c_tsIdx];
        }
        if ($ref_event->[$c_nDropsIdx]) {
            $updtIntervalHasDropEvents{$ev_t_updtInterval} = 1;
        }
    }

    # Remember: @$ref_data is in descending chronological order.  So, to
    # project the drop-counts "forward" in time, we need to reverse the index
    # order (which, sadly, we can't use the '..' operator to do directly).
    foreach my $idx (reverse(0 .. ($#$ref_data -1))) {
        my $timeUptdInterval = t2DropCountInterval($ref_data->[$idx][0]);

        # Ignore data not in the update interval(s) of the new events.
        unless (exists($updtIntervalHasDropEvents{$timeUptdInterval})) {
            next if ($timeUptdInterval <= $lastSeenDrop);
            # Any '$_DropCountInterval' later than the timestamp of the last
            # drop event seen should have its count "reset" to 0.
            $updtIntervalHasDropEvents{$timeUptdInterval} = 0;
        }

        if ($updtIntervalHasDropEvents{$timeUptdInterval}) {
            # There are drop events somewhere in this '$_DropCountInterval'.
            # Extend them forward.
            if ( ($ref_data->[$idx+1][2] != 0) &&
                 ($ref_data->[$idx][2] == 0) )
            {
                $ref_data->[$idx][2] = $ref_data->[$idx+1][2];
            }
            if ( ($ref_data->[$idx+1][4] == 0) &&
                 ($ref_data->[$idx][4] == 0) )
            {
                $ref_data->[$idx][4] = $ref_data->[$idx+1][4];
            }
        } else {
            # No drop events anyplace in this '$_DropCountInterval'.  Reset
            # the count to zero (but not the max counts).
            $ref_data->[$idx][2] = 0;
            #$ref_data->[$idx][4] = 0;
        }

    }
}


sub updateMRTGdata(\@$$) {
    my $ref_newData = shift();
    my $mrtgDatafile = shift();
    my $mrtgNewDatafile = shift();

    # FIXME:  Until we have this function working 100% correctly, print the
    # new data to the log, in "tieable" form.  Later, make this part of the
    # body of the unless-statement, below.
    print STDERR (join("\n", map({ eventArray2tieArrayElement(@{$_})
                                 } @$ref_newData)), "\n");

    # Empty-case check
    return 1 unless (scalar(@$ref_newData));

    # For error messages.
    my $now = localtime();
    # Time bounds of the new data.
    my $t_firstNewEvent = $ref_newData->[0][0];
    my $t_lastNewEvent = $ref_newData->[$#$ref_newData][0];

    # Open the MRTG data log file, using 'tie'
    #
    my @MRTG_Data;
    my $ref_tied = tie(@MRTG_Data, 'Tie::File', $mrtgDatafile,
                       'mode' => O_RDONLY);
    my $failure = checkForErrors_tie($!, $@, $ref_tied, $mrtgDatafile);
    if (defined($failure)) {
        print STDERR ($now, ":  ", $failure,
                     "Cannot update MRTG data in \"", $mrtgDatafile, "\"\n",
                     "DSL State information between ", $t_firstNewEvent,
                      " and ", $t_lastNewEvent, "\n",
                      "will be lost.\n");
        return 0;
    }

    # Find where the new data should go.
    my ($mergeStartIdx,
        $mergeEndIdx) = findRecordsInRange(@MRTG_Data, $t_firstNewEvent,
                                           $t_lastNewEvent);
    # Note:  @{$MRTG_Data[0]} will always have only 3 elements, so don't use
    # it as the merge start.
    if ($mergeStartIdx < 1) {
        $mergeStartIdx = 1;
    }

    # Merge
    my @mergedData = ();
    mergeEventsWithMRTG(@MRTG_Data, $mergeStartIdx, $mergeEndIdx,
                        @$ref_newData, @mergedData);
    projectDropCountsForward(@mergedData, @$ref_newData);

    #
    # Open the file for the updated data:
    #

    unless (open(OUT_FS, ">$mrtgNewDatafile")) {
        print STDERR ($now, ":  ",
                      "Unable to open file for writing: \"",
                      $mrtgNewDatafile, "\"\n", "Reason: \"$!\"\n",
                     "Cowwardly refusing to update the MRTG data.\n");
        return 0;
    }

    # Write out the records preceding the merge region.
    #
    # Note:  We need to project the drop count from the most-recent record in
    #        '@mergedData' forward in time, into every MRTG record before the
    #        merge interval.  The best way to do it is to splice off the
    #        pre-merge records. and call projectDropCountsForward()
    my @preMergeData = map({ [ split(/\s/, $_) ]
                           } @MRTG_Data[0 .. ($mergeStartIdx - 1)]);

    # The first record requires special handling:
    my $ref_firstRecord = shift(@preMergeData);
    if ($mergeStartIdx == 1) {
        # The first record always matches the first 3 elements of the next
        # record.  If we merge in data at the top, we need to mimic this.
        @$ref_firstRecord = @{$mergedData[0]}[(0 .. 2)];
    } else {
        # Just copy the drop count from the first merge record.
        $ref_firstRecord->[2] = $mergedData[0][2];
    }
    print OUT_FS (join(' ', @$ref_firstRecord), "\n");

    # Write the subsequent pre-merge records, if any.
    if (scalar(@preMergeData)) {
        projectDropCountsForward(@preMergeData, @$ref_newData);
        foreach my $ref_record (@preMergeData) {
            print OUT_FS (join(' ', @$ref_record), "\n");
        }
    }

    # Write Merged.
    foreach my $ref_record (@mergedData) {
        print OUT_FS (join(' ', @$ref_record), "\n");
    }

    # Write out the remaining records.
    foreach my $entry (@MRTG_Data[($mergeEndIdx + 1) .. $#MRTG_Data]) {
        print OUT_FS ($entry, "\n");
    }
    close(OUT_FS);

    # Now overwrite MRTG's file with our update file.
    unless (rename($mrtgNewDatafile, $mrtgDatafile)) {
        print STDERR ($now, ":  ",
                      "Failed to update the MRTG data (could not rename\n",
                      "the updated file).\n");
        return 0;
    }

    return 1;
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
    #return 0 if (scalar(@match));
    ## Don't use "system()", as it discards the output.

    print STDERR ("Process '", $daemonPid, "' not found.\n");
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


sub daemon_main(\%) {
    my %options = %{shift()};

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
                read_config(%options, 1);
            };
        } else {
            $SIG{$signame} = \&daemon_sig_cleanup;
        }
    }

    # Tie an array to the data file, keeping any existing one.
    #
    if ( -f $_DataFile) {
        $_refDataTieObj = tie(@_Measurements, 'Tie::File', $_DataFile,
                              'mode' => O_APPEND);
    } else {
        $_refDataTieObj = tie(@_Measurements, 'Tie::File', $_DataFile);
    }
    my $failure = checkForErrors_tie($!, $@, $_refDataTieObj, $_DataFile);
    if (defined($failure)) {
        print STDERR ($failure,
                     "\nCowardly refusing to continue running.\n");
        exit 1;
    }

    #
    # The Main Loop
    #

    my @updatedDslState = ();
    my $probe_duration;
    my $ref_lastEvent = startup_eventDefaultValue();
    if (scalar(@_Measurements)) {
        $ref_lastEvent
            = tieArrayElement2eventArray($_Measurements[$#_Measurements]);
    } else {
        # We must have some initial event in case parse_syslog returns
        # nothing.
        push(@_Measurements,
             eventArray2tieArrayElement(@$ref_lastEvent));
    }

    while (1) {
        my $now = time();
        my $probe_duration = -$now;

print STDERR ("\n\n###DBG### ", $now, " Reading DSL modem log.\n");

        parse_syslog($_GetURLVia, $options{'SyslogUrl'},
                     $options{'userid'}, $options{'passwd'},
                     $options{'DslUp_expr'}, $options{'DslDown_expr'},
                     $options{'_Time_Regexp_'}, @updatedDslState);

print STDERR ("####DBG#### ", time(), " Removing duplicates...\n");
        removeDuplicatesAndAdjust(@updatedDslState,
                                  $ref_lastEvent->[$c_tsIdx],
                                  $ref_lastEvent->[$c_nDropsIdx]);
        resetStaleDropCounts(@updatedDslState, $now, @$ref_lastEvent);
print STDERR ("####DBG#### ", time(), " Storing...\n");

        # Output:
        foreach my $ref_event (@updatedDslState) {
            # 'push' on a tied-array always flushes.
            push(@_Measurements,
                 eventArray2tieArrayElement(@$ref_event));
            # Log the event, as well (at least for now).
            printEvent(\*STDERR, @$ref_event);
            # Update the last-event holder.
            $ref_lastEvent = $ref_event;
        }
print STDERR ("####DBG#### ", time(), " updateMRTGdata()...\n");

        # Build the new MRTG data log file & rotate it in.
        updateMRTGdata(@updatedDslState,
                       $options{'_MRTG_Data_'},
                       $options{'_MRTG_Updated_Data_'});

print STDERR ("####DBG#### ", time(), " Done.  Sleeping.\n");
        $probe_duration += time();
        if ($_UpdateInterval < $probe_duration) {
            sleep($_UpdateInterval);
        } else {
            sleep($_UpdateInterval - $probe_duration);
        }
    }
}


sub start_daemon($\%) {
    my $keepParentRunning = shift();
    my $ref_options = shift();

    # daemonize() either exits the parent process or returns 0.
    daemonize($keepParentRunning) or return 0;

    # We're the child process if we reach this point.
    renice_self();
    daemon_main(%$ref_options);
    # Should never reach here.
    exit 127;
}


sub usage() {
    print STDERR ("usage: ", $_MyName, " -n\n");
    print STDERR (" "x7, $_MyName, " -d\n");
    print STDERR (" "x7, $_MyName,
                  " [-r] <target#> [<target#>]\n\n");
    print STDERR (" "x7, $_MyName, " -c <hop#>[,<hop#>[,...]] <host>\n");
    print STDERR ("<target#> is 0-offset.\n\n");
    print STDERR ("In the configfile, \"UpdateInterval\" is normally in ",
                  "seconds.  You can\n",
                  "change these units by using the suffixes \"h\", \"m\", ",
                  "or \"s\" on the\n",
                  "number that you specify.\n");
    print STDERR ("\nRun Modes:\n\n");
    print STDERR ("'-n':  Run now, printing every DSL up/down event ",
                  "currently  in the DSL\n",
                  " "x7, "modem's log.\n");
    print STDERR ("'-d':  Run in daemon mode.\n");
    print STDERR ("<no-option>:\n",
                  " "x7, "Returns the most recent DSL connection ",
                  "information from the instance\n",
                  " "x7, "of this script already running in '-d' mode.  ",
                  "Returns the requested\n",
                  " "x7, "statistics by ID number:\n",
                  " "x11, "0 :== The last connection event seen by the ",
                  "daemon.\n",
                  " "x11, "1 :== The (human-readable) time of the last ",
                  "connection event.\n",
                  " "x11, "2 :== Like '1', but as seconds-since-epoch ",
                  "(i.e. Unix time).\n");
    print STDERR ("'-r':  Identical to the previous mode combined with '-d'.",
                  "  Starts a daemon\n");
    print STDERR (" "x7, "if one isn't already running, then returns the ",
                  "requested statistics.\n");

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
my $daemonize=0;
my $targetName='';
my $checkNow=0;
my $reportAfterDaemonizing=0;
if ($ARGV[0] eq "-d") {
    shift(@ARGV);
    $daemonize = 1;
    $targetName = shift(@ARGV);
} elsif ($ARGV[0] eq "-r") {
    shift(@ARGV);
    $daemonize=1;
    $reportAfterDaemonizing=1;
    $targetName = shift(@ARGV);
} elsif ($ARGV[0] eq "-n") {
    shift(@ARGV);
    $checkNow=1;
} elsif ($ARGV[0] eq "--l2t") {
    # For recovery only.
    shift(@ARGV);
    myLogfile2tieArrayElement($ARGV[0]); # This fn. exits.
} elsif ($ARGV[0] eq "--recover2mrtg") {
    # For recovery only.
    shift(@ARGV);
    recoveredTieArray2MRTG($ARGV[0], $ARGV[1]); # This fn. exits.
} elsif ($ARGV[0] eq "--keep-in-foreground") {
    # For Debugging Purposes Only:
    my %dbgO;
    print STDERR ("Ignore the 'Rereading' bit in the next message.  We're\n",
                  "using the sighanlder to read the configuration and\n",
                  "validate in one go, and that's what it spits out.\n");
    read_config(%dbgO, 1);
    daemon_main(%dbgO);
    exit 127;  #Should never reach here.
} elsif ($ARGV[0] =~ m/^-/) {
    print STDERR ("Unknown option:  \"", $ARGV[0], "\"\n");
    usage();
}

if (($ARGV[0] eq "") && !$daemonize && !$checkNow) {
    print STDERR ("Missing args.\n");
    usage();
} elsif ($targetName ne '') {
    print STDERR ("First arg must be the name of the target running this\n",
                 "instance of ",$_MyName, "\n",
                 "(The \"target-name\" is what you've put in the \"[]\" in\n",
                 " the MRTG config file.)\n");
    usage();
}


# Read the configuration.
#
my %options;
read_config(%options);

if ($checkNow) {
    my @recentState = ();
    print "===== Current DSL Modem Syslog: =====\n\n";
    parse_syslog($_GetURLVia, $options{'SyslogUrl'},
                 $options{'userid'}, $options{'passwd'},
                 $options{'DslUp_expr'}, $options{'DslDown_expr'},
                 $options{'_Time_Regexp_'}, @recentState);
    foreach my $ref_event (@recentState) {
        printEvent(\*STDOUT, @$ref_event);
    }
    exit 0;
} else {
    my $noDaemonRunning = no_running_daemon();
    if ($daemonize) {
        # Only validate the options in daemon-mode.
        validate_options(%options);

        if ($noDaemonRunning) {
            start_daemon($reportAfterDaemonizing, %options);

            # If we return from start_daemon(), we're the parent.  Let's sleep
            # for a bit for the daemon to start up before going on (and
            # getting the ping data).
            sleep($_TieAttempts*$_TieWait + $_PostDaemonizeWait);

        }
        elsif (!$reportAfterDaemonizing) {
            # Don't do anything more.
            print ("Daemonized instance already running.  Examine \n\"",
                   $_DaemonPIDFile, "\" for its PID.\n\n",
                   "To restart $0, do the following:\n",
                   "\tkill \$(\< ", $_DaemonPIDFile, ");\n",
                   "\t$0 -d\n");
            exit 0;
        }

        # else:  We want to ping whether or not we daemonize.
    }
    elsif ($noDaemonRunning && !$daemonize) {
        print ("No daemonized instance running.  Rerun \n",
               "$0 with the '-d' option.\n\n",
               "Cowardly refusing to continue.\n");
        exit 2;
    }
}


# No Flags or '-r' Option:  Retrieve desired measurements from the daemon.
#
my $statistic1 = undef;
if (scalar(@ARGV)) {
    $statistic1 = shift(@ARGV);
}
my $statistic2 = undef;
if (scalar(@ARGV)) {
    $statistic2 = shift(@ARGV);
}
# FIXME:  These aren't rates anymore.  Rename everything accordingly.
#         We don't need a printf anymore, either.
my @rates = retrieve_rates($statistic1, $statistic2);
printf ("%.0f\n%.0f\n", $rates[0], $rates[1]);

# TODO:
#
# Need to make sure that there's no collission between MRTG and the data file
# update.  Whether this goes in the client-mode or the daemon, I don't know
# yet.
#
# Password "encryption" ... or at least creative obfuscation.
# - Should also include a '-p' mode for entering the password.
#   + Should also Echo '*' for each char.
#   + Would append the encrypted passwd to the configfile, and print it out.
#   + {
#      use Term::Readkey;
#      ReadMode('noecho');
#      my $passwd='';
#      my $c = ReadKey(0);
#      while ($c != "\n") {
#          print '*';
#          $passwd .= $c;
#      }
#      print "\n";
#      ReadMode('normal');
#     }
#   + The code above might not quite work; the ReadKey() call may expect a
#     <Return> before it reads the char (like the Perl 'getc' fn. does).  If
#     this is the case, ditch the entire while-loop and just call
#     'ReadLine(0)' to get the password, Unix-style.  You won't get '*'
#     echoed, but Oh Well.
#   + An alternative would be the following:
#     {
#      use Term::Readkey;
#      ReadMode('cbreak');
#      my $passwd='';
#      my $c = ReadKey(0);
#      while ($c != "\n") {
#          print "\b*";
#          $passwd .= $c;
#      }
#      print "\n";
#      ReadMode('normal');
#     }
#     But, there's no guarantee that Perl will flush immediately, or even fast
#     enough, to keep the characters truly invisible.
#   + Ask for the password twice.
#
# Logfile size and *.dat file size.
# - I'm not even so sure that I /need/ to keep everything in the *.dat file.
#   The client, right now, is only reading the last entry in the file.  That's
#   probably all that I need.
#   + If I do this, then *always* preserve the *.dat file between runs.
#   + But this will require some kinda algo to determine whether or to use it,
#     given how long this script hasn't been running.
#
# Carrying forward the connection state:
#
# The basic idea - if an MRTG record falls in-between two new events, the MRTG
# record's connection-state values should match that of the preceding
# record. So, we may have to perform this operation at merge time.


#################
#
#  End
