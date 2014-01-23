#!/usr/bin/perl
#
# Copyright (C) 2004-2010 by John P. Weiss
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


my $t_ArPath="/usr/local/BACKUP";
my $t_ArFile="tloen-backup";
my $t_ManifestFile=$t_ArFile."-ts";


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
use Getopt::Long;
use tarBackupUtils;
use jpwTools;


############
#
# Other Global Variables
#
############




############
#
# Functions
#
############


sub usage {
#    print "usage: $_MyName -", join(" -", @_), "\n";
    exit 1;
}


############
#
# Main
#
############


sub main {
    $tarBackupUtils::_UnitTest = 1;
    $tarBackupUtils::_NoExec = 1;

    do_incremental_filelist_backup($t_ArPath, $t_ArFile, $t_ManifestFile);
    do_full_filelist_backup($t_ArPath, $t_ArFile, $t_ManifestFile)
}


main;
exit 0;

#################
#
#  End
