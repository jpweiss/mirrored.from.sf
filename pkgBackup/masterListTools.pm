#!/usr/bin/perl
#
# Copyright (C) 2003-2012 by John P. Weiss
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
# Std. Package Boilerplate
#
############


package masterListTools;
require 5;
use strict;

BEGIN {
    use Exporter ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # if using RCS/CVS, this may be preferred
    $VERSION = do { my @r = (q$Revision: 1401 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

    @ISA         = qw(Exporter);

    # Default exports.
    @EXPORT = qw(build_master_lists update_master_lists
                 read_master_fileset write_master_fileset);
    # Permissable exports.
    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK = qw($_Verbose $_UnitTest
                    @_Exclude_fs);

    # Tagged groups of exports.
    %EXPORT_TAGS = qw();
}
our @EXPORT_OK;

# Other Imported Packages/requirements.
use jpwTools;


############
#
# Global Variables
#
############


our $_Verbose;  $_Verbose = 0;
our $_UnitTest; $_UnitTest = 0;
our @_Exclude_fs; @_Exclude_fs=("proc",
                                "iso9660",
                                "nfs",
                                "afs",
                                "usbdevfs",
                                "devpts");


############
#
# Internal Variables
#
############


my $_find_bin="/usr/bin/find";
my $_TestPath = "/lib";


############
#
# Internal Functions
#
############


sub myFinder(\%\%$@) {
    # Why I'm not using File::Find:
    #
    # I wanted to.  I really did.  Unfortunately, File::Find must use stat()
    # or lstat() to determine filesystem types.  Those two builtin Perl
    # functions both return a numeric code for the device (i.e. filesystem)
    # type.  "rpm" & "dpkg" work on multiple platforms and OS's.  I only have
    # a Linux i386 to play with.  There goes making this backup script
    # platform/OS-independent.
    #
    # GNU find, on the other hand, uses filesystem names and does the
    # translating for you.  We all know that it runs on many platforms/OS's.
    # Why should I duplicate the FSF's fine work?
    my $ref_fileset = shift;
    my $ref_dirset = shift;
    my $findopts = shift;
    unless ( (ref($ref_fileset) eq "HASH") &&
             (ref($ref_dirset) eq "HASH") ) {
        die "Syntax Error: Incorrect function call";
    }
    my $doErase=1;
    if (scalar(@_) > 0) {
        $doErase=0;
    }
    my $findcmd;

    if ($_UnitTest) {
        $findcmd = "$_find_bin $_TestPath $findopts";
        print "Searching filesystem with command: \"$findcmd\"\n";
    } else {
        $findcmd = "$_find_bin / $findopts";
    }
    if($_UnitTest || $_Verbose) {
        print "Starting filesystem search...\t\t";
    }

    if ($doErase) {
        %$ref_fileset = ();
        %$ref_dirset = ();
    }
    open(FIND_IN, "$findcmd |");
    while (<FIND_IN>) {
        my $foundfile = $_;
        chomp $foundfile; # Remove newline
        if (-d $foundfile) {
            $ref_dirset->{$foundfile} = 1;
        } else {
            $ref_fileset->{$foundfile} = 1;
        }
    }
    close FIND_IN;
    # FIXME: Spurrious search errors due to recurse of banned fstypes
    #    or closePipeDie("find");

    if ($_UnitTest || $_Verbose) {
        print "Filesystem search complete.\n";
    }
    if ($_UnitTest) {
        my $tmp=keys(%$ref_dirset);
        print "Found $tmp directories ";
        $tmp=keys(%$ref_fileset);
        print "and $tmp files.\n";
    }
}


sub write_and_diff_master_fileset($\%\%\%$$$;@) {
    my $masterFName = shift;
    my $ref_master_fileset = shift;
    my $ref_master_dirset = shift;
    my $ref_changed_pkgfiles = shift;
    my $isNewMasterList = shift;
    my $isChangedMasterList = shift;
    my $diffAgainstMaster = shift;
    my @changeTypes2Add = @_;

    # If the Master List *is* the diff between the package files and
    # the files on disk, then this and the $diff_against_master stuff are
    # both redundant.
    #
    # However, if the Master List is a listing of everything that can't be
    # restored by reinstalling a package, then we want this here.
    #
    # You'd call this from the main script, in place of
    # write_master_fileset(), like so:
    #
    # write_and_diff_master_fileset($_MasterLists_File,
    #                               %master_fileset, %master_dirset,
    #                               %changed_pkgfiles,
    #                               ($scan_rpms || $build_master_list),
    #                               $update_master_lists,
    #                               $diff_against_master,
    #                               "Contents", "Symlink",
    #                               "Permissions", "Other", '');

    if ($isNewMasterList) {
        # Add to the hash using a bulk operation.  [Note that
        # "@hashvar{@listvar}=1;" only sets one element in the slice,
        # whereas "map" repeats an operation for every element in the
        # list.]
        foreach my $key (@changeTypes2Add) {
            my $ref_typeChngFiles = $ref_changed_pkgfiles->{$key};
            my $n_typeChng = scalar(@$ref_typeChngFiles);
            next unless ($n_typeChng);
            @$ref_master_fileset{@$ref_typeChngFiles} = (1) x $n_typeChng;
        }
    }

    # Save the files.
    if ($isNewMasterList || $isChangedMasterList) {
        write_master_fileset($masterFName,
                             %$ref_master_fileset, %$ref_master_dirset);
    }

    # Lastly, print out the diff of the backed-up files vs. the master
    # list.
    if ($diffAgainstMaster) {
        my %diff_fileset = %$ref_master_fileset;
        foreach my $ref_typeChngFiles (values(%$ref_changed_pkgfiles)) {
            my $n_typeChng = scalar(@$ref_typeChngFiles);
            next unless ($n_typeChng);
            delete @diff_fileset{@$ref_typeChngFiles};
        }
        print_hash("diff_fileset", %diff_fileset);
        #return \%diff_fileset;
    }
    #return undef();
}


############
#
# Exported Functions
#
############


sub build_master_lists(\%\%) {
    my ($ref_fileset, $ref_dirset) = @_;
    my $fsarg = "\\( -fstype ";
    $fsarg .= join(' -o -fstype ', @_Exclude_fs);
    $fsarg .= " \\) -prune";

    myFinder(%$ref_fileset,
             %$ref_dirset,
             "$fsarg -o -print");

    # On pruning the @_Exclude_Dirs:
    # Originally, I had code like this in here:
    #
    #    my $prunearg="\\( -name ";
    #    $prunearg .= join(' -o -name ', (@_Exclude_Dirs, @_Include_Dirs));
    #    $prunearg .= " \\) -prune ";
    #    :
    #    :
    #    $findcmd = "$_find_bin $_TestPath $prunearg -o \\! $fsarg $printarg";
    #
    # I thought that I'd let the find command handle the "heavy
    # lifting" of removing the @_Exclude_Dirs (and the @_Include_Dirs,
    # since those files will be part of the backup regardless).  I
    # later decided that this was a bad idea.
    #
    # This particular form of backup script has a specific purpose.
    # It identifies any disk content that comes from an RPM/DEB package
    # and eliminates it from your list of Things To Backup.  The
    # @_Exclude_Dirs and @_Include_Dirs are sysadmin-fine-tuning,
    # independent of what came from an RPM/DEB package and what didn't.
    # Why tamper with that core functionality?
    #
    # A second reason has to do with flexibility.  Not everyone will
    # be backing up to a compressed tarball & burning it to CD.  Not
    # everyone will be able to fit that compressed tarball on a single
    # CD.  By separating the (@_Exclude_Dirs, @_Include_Dirs) list from
    # the "what's not in my RPM's" set, you can generate a "Master
    # List" of files just once, then create different (@_Exclude_Dirs,
    # @_Include_Dirs) sets for different backup taballs.
}


sub update_master_lists(\%\%$) {
    my ($ref_fileset, $ref_dirset, $master_fname) = @_;
    my $ndirs;
    my $nfiles;
    my $timearg = "-newer '$master_fname'";
    my $fsarg = "\\( -fstype ";
    $fsarg .= join(' -o -fstype ', @_Exclude_fs);
    $fsarg .= " \\) -prune";

    if ($_UnitTest || $_Verbose) {
        $ndirs = -scalar(values(%$ref_dirset));
        $nfiles = -scalar(values(%$ref_fileset));
    }
    myFinder(%$ref_fileset,
             %$ref_dirset,
             "$fsarg -o \\( $timearg \\) -print",
             "append");
    if ($_UnitTest || $_Verbose) {
        $ndirs += scalar(values(%$ref_dirset));
        $nfiles += scalar(values(%$ref_fileset));
        print "Added $ndirs new directories and $nfiles new files.\n";
    }
}


sub read_master_fileset($\%\%) {
    my ($filename,
        $ref_fileset,
        $ref_dirset) = @_;
    unless ( (ref($ref_fileset) eq "HASH") &&
             (ref($ref_dirset) eq "HASH") ) {
        die "Syntax Error: Incorrect function call";
    }

    # Skips any consecutive blank lines or comments surrounding blank lines
    # (which return an empty hash).
    if ($_UnitTest || $_Verbose) {
        print "Reading Master Directory and File Lists...\n";
    }
    my %optset = read_options($filename);

    unless( defined($optset{"master_dirset"}) &&
            (ref($optset{"master_dirset"}) eq "ARRAY") ) {
        die "ERROR: \"$filename\" missing Master Directory List\n".
            "       (or file is mangled).\n";
    }
    %$ref_dirset = map({ $_, 1 } @{$optset{"master_dirset"}});

    unless( defined($optset{"master_fileset"}) &&
            (ref($optset{"master_fileset"}) eq "ARRAY") ) {
        die "ERROR: \"$filename\" missing Master File List\n".
            "       (or file is mangled).\n";
    }
    %$ref_fileset = map({ $_, 1 } @{$optset{"master_fileset"}});
}


sub write_master_fileset($\%\%) {
    my ($filename,
        $ref_fileset,
        $ref_dirset) = @_;

    chmod(0660, $filename);
    open(OFS, ">$filename")
        or failedOpenDie($filename, 'writing');
    # File header.
    print OFS ('#'x79, "\n#\n");
    print OFS ("# Raw filesystem snapshot.\n#\n");
    print OFS ("# Created by $main::_MyName.  DO NOT MODIFY.\n");
    print OFS ("#\n", '#'x79, "\n\n");

    # Print the directory set.
    print OFS ("master_dirset=(\n");
    foreach (sort(keys(%$ref_dirset))) { print OFS ($_, "\n"); }
    print OFS (")\n\n", '#'x79, "\n\n");

    # Print the fileset.
    print OFS ("master_fileset=(\n");
    foreach (sort(keys(%$ref_fileset))) { print OFS ($_, "\n"); }
    print OFS (")\n");

    # File footer.
    print OFS ("\n", '#'x10, "\n# End\n#\n");
    close OFS;
    chmod(0440, $filename);
}


1;  # don't forget to return a true value from the file
## POD STARTS HERE ##
__END__

=head1 NAME

masterListTools - Package of anscillary tools for building a "Master List".

=head1 SYNOPSIS

=over 0

=item build_master_lists(I<%fileset>, I<%dirset>)

=item update_master_lists(I<%fileset>, I<%dirset>, I<$masterListFname>)

=item read_master_fileset(I<$masterListFname>, I<%fileset>, I<%dirset>)

=item write_master_fileset(I<$masterListFname>, I<%fileset>, I<%dirset>)

=back

=head1 DESCRIPTION

This module is basically baggage from an earlier version of this
tool.  It's still useful, but no longer the main set of functions.

Note:  This module expects that its "parent script" defined the global
variable C<$_MyName>.  C<$main::_MyName> should contain the name of the
script-executable.

=over 2

=item *

build_master_lists(I<%fileset>, I<%dirset>)

Scan the filesystem for everything.  Store directories in I<%dirset>,
everything else in I<%fileset>.

=item *

update_master_lists(I<%fileset>, I<%dirset>, I<$masterListFname>)

Scan the filesystem for anyting newer than the file I<$masterListFname>.
Adds the results to I<%fileset> and I<%dirset>.

=item *

write_master_fileset(I<$masterListFname>, I<%fileset>, I<%dirset>)

Writes the two hashes to I<$masterListFname> in "fileset format."

=item *

read_master_fileset(I<$masterListFname>, I<%fileset>, I<%dirset>)

Inverse of C<write_master_fileset()>.

=back

=cut

#################
#
#  End
