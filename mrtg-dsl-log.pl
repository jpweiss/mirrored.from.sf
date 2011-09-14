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
# Configuration Variables
#
############


my $_ConfigFile = undef();
my $_DataFile = "/dev/shm/mrtg-dsl-log.dat";
my $_GetURLVia = 'curl';
my $_TieAttempts = 5;
my $_TieWait = 1;
my $_PostDaemonizeWait = 5;
my $_DaemonPIDFile = "/var/run/mrtg-dsl-log.pid";
my $_UpdateInterval = 5*60;
my $_DaemonLog = "/tmp/mrtg-dsl-log.log";
my $_DropCountInterval = 3600;
# FIXME:  #DBG#  For Debugging Purposes Only:
$_DataFile = "/home/candide/tmp/mrtg-tst/mrtg-dsl-log.dat";
$_DaemonPIDFile = "/home/candide/tmp/mrtg-tst/mrtg-dsl-log.pid";
$_DaemonLog = "/home/candide/tmp/mrtg-tst/mrtg-dsl-log.log";


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
use Date::Parse;
use Tie::File;
use Fcntl qw(O_RDONLY O_APPEND O_CREAT);  # For use with 'tie'
use POSIX qw(nice setsid);


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


sub valiate_options(\%) {
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

    if (exists($ref_options->{"UpdateInterval"})) {
        $_UpdateInterval = $ref_options->{"UpdateInterval"};
        # Process any units-suffix:
        if ($_UpdateInterval =~ m/^(.*)\s*s$/) {
            # Units of seconds.  Nothing to do to the number.
            $_UpdateInterval = $1;
        } elsif ($_UpdateInterval =~ m/^(.*)\s*([mh])$/) {
            $_UpdateInterval = $1;
            if ($2 eq "h") {
                $_UpdateInterval *= 60;
            }
        }
        # Convert min. to sec.
        $_UpdateInterval *= 60;
    }

    if (exists($ref_options->{"DaemonLog"})) {
        $_DaemonLog = $ref_options->{"DaemonLog"};
    }

    if ($isRereading) {
        # Only validate the options in daemon-mode.  Since rereading only
        # happens during daemon-mode, we can call 'valiate_options()' here.
        valiate_options(%$ref_options);

        print STDERR ("\tFinished rereading configuration.\n");
        print STDERR ("\tNew values:\n");
        foreach my $k (keys(%$ref_options)) {
            print STDERR ("\t\t", $k, " = ");
            if (ref($ref_options->{$k})) {
                print STDERR ("(\n\t\t\t",
                              join("\n\t\t\t", @{$ref_options->{$k}}),
                              "\n\t\t)\n");
            } else {
                print STDERR ("\"", $ref_options->{$k}, "\"\n");
            }
        }
    }

    return 1;
}


#
# Parsing & Processing the DSL Modem Log
#


sub parse_log($$$$$$$\@) {
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
        my $timeUptdInterval = $time_sec - ($time_sec % $_DropCountInterval);

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
    @$ref_dslState = sort({ $a->[0] <=> $b->[0] } @parsedData);
}


sub removeDuplicatesAndAdjust(\@$$) {
    my $ref_events = shift();
    my $t_lastEvent = shift();
    my $nDropped_last = shift();

    # 'parse_log()' may have been called in the middle of the
    # '$_DropCountInterval'.  If the first new event is still in that
    # interval, we need to start the drop count with whatever it was at the
    # end of the last call to 'parse_log()'.
    my $lastEvent_UptdInterval_end = ($t_lastEvent
                                      - ($t_lastEvent % $_DropCountInterval)
                                      + $_DropCountInterval);

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


sub tieArrayElement2eventArray($) {
    my $tieElement = shift();
    study $tieElement;

    my @eventArray = (undef) x 4;
    if ( ($tieElement =~ m/^\[\[/) && ($tieElement =~ m/\]\]$/) ) {
        $tieElement =~ s/^\[\[//;
        $tieElement =~ s/\]\]$//;
        @eventArray = split(/;\|;/, $tieElement);
    }

    return @eventArray;
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
    my @result = tieArrayElement2eventArray($measurements[$#measurements]);
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


sub projectDropCountsForward(\@) {
    my $ref_data = shift();

    # Project forward, but only within the same '$_DropCountInterval'.
    my %seen_UptdInterval = ();
    # *sigh*  You can't use the range operator on a descending list.
    foreach my $idx (reverse(0.. ($#$ref_data - 1))) {
        my $timeUptdInterval = $ref_data->[$idx][0]
            - ($ref_data->[$idx][0] % $_DropCountInterval);

        if (exists($seen_UptdInterval{$timeUptdInterval})) {
            # Still in the same '$_DropCountInterval'
            if ($ref_data->[$idx][2] == 0) {
                $ref_data->[$idx][2] = $ref_data->[$idx+1][2];
            }
            if ($ref_data->[$idx][4] == 0) {
                $ref_data->[$idx][4] = $ref_data->[$idx+1][4];
            }
        } else {
            $seen_UptdInterval{$timeUptdInterval} = 1;
        }

    }
}


sub updateMRTGdata(\@$$) {
    my $ref_newData = shift();
    my $mrtgDatafile = shift();
    my $mrtgNewDatafile = shift();

    # FIXME:  Until we have this function working 100% correctly, print the
    # new data to the log, in "tieable" form.
    print STDERR (join("\n", map({ eventArray2tieArrayElement(@$_)
                                 } @$ref_newData)), "\n");

    # Empty-case check
    return 0 unless (scalar(@$ref_newData));

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
        return 1;
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
    projectDropCountsForward(@mergedData);

    #
    # Open the file for the updated data:
    #

    unless (open(OUT_FS, ">$mrtgNewDatafile")) {
        print STDERR ($now, ":  ",
                      "Unable to open file for writing: \"",
                      $mrtgNewDatafile, "\"\n", "Reason: \"$!\"\n",
                     "Cowwardly refusing to update the MRTG data.\n");
        return 1;
    }

    # Write out the records preceding the merge region.
    #
    # Note:  We need to project the drop count from the most-recent record in
    #        '@mergedData' forward in time, into every MRTG record before the
    #        merge interval.
    #        This isn't _entirely_ correct, since the drop count is really the
    #        of connection-drops in one '$_DropCountInterval'.  However, if
    #        you think about it, the data preceding '$mergeStartIdx' has to be
    #        in a single '$_DropCountInterval'.

    # The first record requires special handling:
    my @record = split(/\s/, $MRTG_Data[0]);
    if ($mergeStartIdx == 1) {
        # The first record always matches the first 3 elements of the next
        # record.  If we merge in data at the top, we need to mimic this.
        @record = @{$mergedData[0]}[(0 .. 2)];
    } else {
        # Just copy the drop count from the first merge record.
        $record[2] = $mergedData[0][2];
    }
    print OUT_FS (join(' ', @record), "\n");

    # Handle the subsequent records
    foreach my $entry (@MRTG_Data[1 .. ($mergeStartIdx - 1)]) {
        @record = split(/\s/, $entry);
        $record[2] = $mergedData[0][2];
        $record[4] = $mergedData[0][4];
        print OUT_FS (join(' ', @record), "\n");
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
        return 1;
    }

    return 0;
}


#
# Daemon-related
#


sub daemonize(;$) {
    my $keepParentRunning = (scalar(@_) ? shift() : 0);

    defined(my $pid = fork) or die "Can't fork: $!";
    if ($pid) {
        if ($keepParentRunning) {
            return 0;
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
    #return !scalar(@match);
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
    my $ref_lastEvent = [];
    if (scalar(@_Measurements)) {
        $ref_lastEvent
            = tieArrayElement2eventArray($_Measurements[$#_Measurements]);
    }

    while (1) {
        my $probe_duration = -time();

        print STDERR ("###DBG### ", time(), " Reading DSL modem log.\n");

        parse_log($_GetURLVia, $options{'LogUrl'},
                  $options{'userid'}, $options{'passwd'},
                  $options{'DslUp_regexp'}, $options{'DslDown_regexp'},
                  $options{'Time_regexp'}, @updatedDslState);

        print STDERR ("####DBG#### ", time(), " Removing duplicates...\n");
        removeDuplicatesAndAdjust(@updatedDslState,
                                  $ref_lastEvent->[$c_tsIdx],
                                  $ref_lastEvent->[$c_nDropsIdx]);
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
    daemonize($keepParentRunning) or return 1;

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
} elsif ($ARGV[0] eq "-l2t") {
    # For recovery only.
    shift(@ARGV);
    myLogfile2tieArrayElement($ARGV[0]); # This fn. exits.
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
    parse_log($_GetURLVia, $options{'LogUrl'},
              $options{'userid'}, $options{'passwd'},
              $options{'DslUp_regexp'}, $options{'DslDown_regexp'},
              $options{'Time_regexp'}, @recentState);
    foreach my $ref_event (@recentState) {
        printEvent(\*STDOUT, @$ref_event);
    }
    exit 0;
} else {
    my $noDaemonRunning = no_running_daemon();
    if ($daemonize) {
        # Only validate the options in daemon-mode.
        valiate_options(%options);

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

# FIXME:  The initial design of this tool was based on the assumption that
#         we could somehow backtrack the client and allow the daemon to update
#         at its own, separate rate.  I don't see how we can do that, short
#         of sending "traps" somehow.
#         Gotta read the MRTG manual more.
#
#         - Config Item:  Step[targ]: <N_min>
#         - Should be using 'noinfo,nopercent'.  Experiment with 'avgpeak'
#           option.
#         - See what happens if a script exits nonzero for 20 min.
#           + Still displays what you print.  Disabling the printout...


# The Plan:
#
# The daemon will maintain the info on its own (definitely daily; maybe
# fully).  The 5-minute call to this script will either (A) rotate the log; or
# (B) do nothing.  It will never print anything, though.
#
# use MRTG_lib qw(readcfg);
#  my ($configfile, @target_names, %globalcfg, %targetcfg);
#  readcfg($configfile, \@target_names, \%globalcfg, \%targetcfg);
#
#  Look in %globalcfg for 'LogDir'; check @target_names for the specified
#  targ.
#
# Hmmm... Idea:  return the current time, twice, in query mode.  Then, all we
# need to do is search the log for entries with the same number in the first 3
# fields.  We'll likely need to go one more entry past that (but check this).



#################
#
#  End
