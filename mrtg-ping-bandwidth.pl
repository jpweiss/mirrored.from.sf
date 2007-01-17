#!/usr/bin/perl 
#
# Copyright (C) 2006-2007 by John P. Weiss
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
use bytes;           # Overrides Unicode support


############
#
# Main: This is a Trivial script
#
############


if ($ARGV[0] eq "") {
    print STDERR "usage: ", $_MyName, " <hostname>\n";
    exit 1;
}
my $host = $ARGV[0];

my $pingcmd="/bin/ping -A -w 2 ";
$pingcmd .= $host;
$pingcmd .= " 2>&1 |";
unless (open(PINGFH, $pingcmd)) {
    print STDERR ("FATAL: Can't run command: ", $pingcmd, 
                  "\nReason: \"", $!, "\"\n");
    exit 1;
}

my $bytes = 0;
my $msecs = 0;
while (<PINGFH>) {
    if (m/(\d+) bytes from .* time=([[:digit:].]+) ms/) {
        $bytes += $1;
        $msecs += $2;
    }
}
close(PINGFH);

my $rate = $bytes;
if ($msecs) { 
    $rate /= $msecs;
    $rate *= 1000;
} else { 
    $rate = 0; 
}
printf "%d\n%d\n", $rate, $rate;


#################
#
#  End
