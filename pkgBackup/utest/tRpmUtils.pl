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
use rpmUtils;
use jpwTools;


############
#
# Other Global Variables
#
############


my $_SkipModifiedPkgfiles_re
    ='/(?:dev|usr/(?:doc|man|s(?:hare/(?:doc|man)|rc)))';
my $_MasterIncludeDirs_re='/(?:etc|root)';
my $_installTime_delta=5;


############
#
# Functions
#
############


sub usage {
    print "usage: $_MyName -", join(" -", @_), "\n";
    exit 1;
}


############
#
# Main
#
############


sub main {
    my $argc = scalar(@ARGV);
    my $help = 0;

    my %optmap=('help' => \$help,
                'h' => \$help);
    my @valid_opts=('get_pkglist',
                    'get_modified_pkgfiles',
                    'scan_modified_pkgfiles',
                    'get_changed_since_install',
                    'read_pkgset',
                    'write_pkgset');
    @valid_opts = sort(@valid_opts, keys(%optmap));

    unless ( ($argc > 0) &&
             (GetOptions(\%optmap, @valid_opts)) ) {
        print "Invalid commandline.\n";
        usage @valid_opts;
    }
    if ($help) {
        usage @valid_opts;
    }

    # Set the package-global vars
    $rpmUtils::_UnitTest = 1;
    $rpmUtils::_Verbose = 1;

    if (exists $optmap{'get_pkglist'}) {
        my %pkgs=();
        %pkgs = get_pkglist;
        print_hash("Packages", %pkgs);
        exit 0;
    }

    if (exists $optmap{'get_modified_pkgfiles'}) {
        my @diffpkg = ();
        my %pkgs=();
        my %dirs=( 'none' => 0 );
        %pkgs = get_pkglist;
        #@diffpkg = get_modified_pkgfiles(%pkgs, %dirs,
        #                                 $_SkipModifiedPkgfiles_re);
        print "( @diffpkg )\n";
        exit 0;
    }

    if (exists $optmap{'scan_modified_pkgfiles'}) {
        my %diffpkg = ();
        my %pkgs=();
        %pkgs = get_pkglist;
        #%diffpkg = scan_modified_pkgfiles(%pkgs, $_SkipModifiedPkgfiles_re);
        print_hash("ModifiedPackages", %diffpkg);
        exit 0;
    }

    if (exists $optmap{'get_changed_since_install'}) {
        my %diffpkg = ();
        my %pkgs=();
        my %dirs=( 'none' => 0 );
        my %files = %dirs;
        %pkgs = get_pkglist;
        %diffpkg = get_changed_since_install(%pkgs, %files, %dirs,
                                             $_MasterIncludeDirs_re,
                                             $_SkipModifiedPkgfiles_re,
                                             $_installTime_delta);
        print_hash("ModifiedPackages", %diffpkg);
        exit 0;
    }

    if (exists $optmap{'write_pkgset'}) {
        my %pkgs=();
        %pkgs = get_pkglist;
        write_pkgset "/tmp/test.pkgs", %pkgs, $_MyName;
        exit 0;
    }

    if (exists $optmap{'read_pkgset'}) {
        my %pkgs=();
        read_pkgset "/tmp/test.pkgs", %pkgs;
        print_hash("Packages", %pkgs);
        exit 0;
    }
}


main;
exit 0;

#################
#
#  End
