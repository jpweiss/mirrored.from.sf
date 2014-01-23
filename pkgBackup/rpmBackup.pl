#!/usr/bin/perl
#
# Copyright (C) 2003-2010 by John P. Weiss
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
# Precompilation Init
#
############


my $_WrapperRunPath='.';
BEGIN {
    if ($0 =~ m|\A(.*)/([^/]+\Z)|) {
        if ($1 ne ".") {
            $_WrapperRunPath = $1;
            push @INC, $1;
        }
    }
}


############
#
# Includes/Packages Specific to this Wrapper
#
############


use rpmUtils;
use tarBackupUtils;


############
#
# Extra Functions
#
############


sub pkgUtils_setVerbose($$) {
    $rpmUtils::_Verbose = shift;
    $rpmUtils::_UnitTest = shift;
};


############
#
# Run the Common Script
#
############


require "pkgBackup.pl";


#################
#
#  End
