#!/usr/bin/perl 
#
# Copyright (C) 2004 by John P. Weiss
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


############
#
# Precompilation Init
#
############
# Before anything else, split the script's name into directory/file.  We
# want to add the script's directory to the set of include-dirs.  This way, we
# get any packages living in the script's directory.
my $_MyName;
BEGIN {
    if ($0 =~ m|\A(.*)/([^/]+\Z)|) {
        if ($1 ne ".") { push @INC, $1; }
        $_MyName = $2;
    } else { $_MyName = $0; }  # No path; only the script name.
}


############
#
# Includes/Packages
#
############


require 5;
use strict;
use Time::HiRes qw(sleep);


############
#
# Other Global Variables
#
############


#my $_MyName = $0;


############
#
# Functions
#
############


sub read_cpu_speed {
    my $cpuNumber=shift;
    # Kernel v2.4
    ##my $speedFile="/proc/sys/cpu/$cpuNumber/speed";
    # Kernel v2.6
    my $speedFile
        ="/sys/devices/system/cpu/cpu$cpuNumber/cpufreq/scaling_cur_freq";

    # Wait a teensy bit to let the system calm down after starting up perl.
    # I've been seeing a step-up in speed on my ThinkPad just due to running
    # this script.
    sleep(0.25);

    open(ICS, "$speedFile")
        or die("Unable to open file for reading: \"$speedFile\"\n".
               "Reason:\"$!\"\n");
    my $speed=<ICS>;
    close ICS;

    return $speed/1000.0;
}


sub read_cpu_temp {
    my $cpuNumber=shift;
    my $tempFile="/proc/acpi/thermal_zone/THM$cpuNumber/temperature";

    open(ICS, "$tempFile")
        or die("Unable to open file for reading: \"$tempFile\"\n".
               "Reason:\"$!\"\n");

    my $temp=<ICS>;
    close ICS;
    $temp =~ s/\s\s+/  /g;
    $temp =~ s/^t/CPU T/;
    $temp =~ s/C\s*$/°C/;
    return $temp;
}


sub read_battery_info {
    my $batteryNumber=shift;
    my $infFile="/proc/acpi/battery/BAT$batteryNumber/info";
    my $stateFile="/proc/acpi/battery/BAT$batteryNumber/state";

    open(IBI, "$infFile")
        or die("Unable to open file for reading: \"$infFile\"\n".
               "Reason:\"$!\"\n");

    my $capacity=0;
    my $max_capacity=0;
    while(<IBI>) {
        if (m/last full capacity:\s+(\d+)/) {
            $capacity=$1;
        } elsif (m/design capacity:\s+(\d+)/) {
            $max_capacity=$1;
        }
    }
    close IBI;

    open(IBS, "$stateFile")
        or die("Unable to open file for reading: \"$stateFile\"\n".
               "Reason:\"$!\"\n");

    my $isPresent=0;
    my $batteryState="";
    my $usageRate=-1;
    my $remaining=0;
    while(<IBS>) {
        if (m/charging state:\s+(\w+)/) {
            $batteryState=$1;
        } elsif (m/present rate:\s+(\d+)/) {
            $usageRate=$1;
        } elsif (m/remaining capacity:\s+(\d+)/) {
            $remaining=$1;
        } elsif (m/present:\s+yes/) {
            $isPresent=1;
        }
    }
    close IBS;

    unless ($usageRate) {
        $usageRate = $capacity;
        if ($isPresent && ($batteryState eq "unknown")) {
            if ($remaining < $capacity) {
                $batteryState = "charging";
            } else {
                $batteryState = "Charged";
            }
        }
    }
    unless ($isPresent) {
        $batteryState="Removed";
        $usageRate=-1;
        $remaining=0;
    }

    if ($batteryState =~ m/^charg/) {
        $usageRate *= -1;
        $remaining -= $capacity;
    }
    return ($batteryState, $usageRate, $remaining, $capacity, $max_capacity);
}


############
#
# Main
#
############


sub main {
    my $t_in_hrs=0;
    my $bat_n=0;
    my $cpu_n=0;
    my $showTemp=0;
    my $showCpuSpeed=0;
    while (scalar(@ARGV)) {
        my $arg = shift(@ARGV);
        if ($arg =~ m/-hr/) {
            ++$t_in_hrs;
            next;
        } # else
        if ($arg =~ m/-b/) {
            $bat_n = 0 + shift(@ARGV);
            next;
        }
        if ($arg =~ m/-t/) {
            ++$showTemp;
            next;
        }
        if ($arg =~ m/-c/) {
            ++$showCpuSpeed;
            if (scalar(@ARGV) && ($ARGV[0] !~ m/\D/)) {
                $cpu_n = 0 + shift(@ARGV);
            }
            next;
        }
        # else:  Usage
        print ("usage: ", $_MyName, 
               " [-c [cpu_num]|--hr|-b [bat_num]|-t]\n");
        exit 0;
    }

    my ($batteryState, 
        $usageRate, 
        $remaining, 
        $capacity, 
        $max_capacity) = read_battery_info($bat_n);
    unless ($capacity) { $capacity = -1; }
    unless ($usageRate) { $usageRate = -1; }

    my $hrs_remaining = int($remaining/$usageRate);
    my $min_remaining = int(($remaining/$usageRate - $hrs_remaining)*60);
    printf ("State:  %-10s  ", $batteryState);
    my $lineSpaceRemaining=80;
    if ($t_in_hrs) {
        printf ("Remaining:  %.2f hrs", $remaining/$usageRate);
    } else {
        printf ("Time Remaining:  %d:%0.2d", $hrs_remaining, $min_remaining);
    }
    $lineSpaceRemaining -= 22;
    if ($remaining < 0) {
        printf (" (%.1f%% uncharged)    ", -100.0*$remaining/$capacity);
        $lineSpaceRemaining -= 21;
    } else {
        printf (" (%d%%)    ", 100.0*$remaining/$capacity);
        $lineSpaceRemaining -= 11;
    }
    if ($lineSpaceRemaining < 25) {
        print "\n";
        $lineSpaceRemaining = 80;
    }
    if ($showCpuSpeed) {
        printf ("CPU Speed:  %dMHz    ", read_cpu_speed($cpu_n));
        $lineSpaceRemaining -= 23;
    }
    if ($lineSpaceRemaining < 25) {
        print "\n";
        $lineSpaceRemaining = 80;
    }
    if ($showTemp) {
        printf read_cpu_temp($cpu_n);
        $lineSpaceRemaining -= 23;
    }
    print "\n\n";
}


main;
exit 0;

#################
#
#  End
