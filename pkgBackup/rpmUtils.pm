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
# Configuration Variables
#
# (Adjust for your system as needed.)
#
############


# Deduced empirically from the size and install time of the "tetex" package
# and the mtime of the symlink "/usr/bin/latex".
#
# A faster or slower hard drive may need a different value here.  Ditto for
# slower CPUs.
my $_PkgInstall_BytesPerSec = 300000;


############
#
# Std. Package Boilerplate
#
############


package rpmUtils;
require 5;
use strict;

BEGIN {
    use Exporter ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # if using RCS/CVS, this may be preferred
    $VERSION = do { my @r = (q$Revision: 1401 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

    @ISA         = qw(Exporter);

    # Default exports.
    @EXPORT = qw(get_pkglist
                 isChangeTypeAlias setChangeTypeAliases
                 isSupportedChangeType
                 get_changed_since_install
                 read_pkgset write_pkgset);
    # Permissable exports.
    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK = qw($_Verbose $_UnitTest);

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


############
#
# Internal Variables
#
############


my $_rpm_bin="/bin/rpm";
my %_UnsupportedChangeTypeSet = ("Unknown" => 1,
                                 #"Other" => 1,
                                 );


############
#
# Internal Functions
#
############


sub process_pkgspec(\%$;$$) {
    my $ref_pkgset = shift;
    my $spec_txt = shift;
    my $updatedSince = ((scalar(@_)) ? shift() : -1);
    my $hasSize = ((scalar(@_)) ? shift() : 0);

    my @pkgspecs = split("[\t\n]", $spec_txt);
    return if (($updatedSince > 0) && ($updatedSince > $pkgspecs[4]));

    # Add an approximated "install duration", based on the package size, to
    # the installation time.  This will (hopefully) move the install time
    # closer to the time that the installation completed.
    if ($hasSize && exists($pkgspecs[5])) {
        my $pkgSize = pop(@pkgspecs);
        $pkgspecs[4] += int($pkgSize / $_PkgInstall_BytesPerSec);
        if ($_UnitTest && $_Verbose) {
            print ($pkgspecs[0], ":\tEstimated Install Duration: ",
                   int($pkgSize / $_PkgInstall_BytesPerSec),
                   "\n");
        }
    }

    # We use a hash of hashes of array-refs to handle multiple versions of the
    # same package installed at the same time.
    my $pkgName = $pkgspecs[0];
    my $pkgVer = $pkgspecs[1];
    $ref_pkgset->{$pkgName}{$pkgVer} = \@pkgspecs;
}


sub set_if_older(\%$$$) {
    my $ref_fileset = shift;
    my $filename = shift;
    my $t_state = shift;
    my $pkgInstallTime = shift;

    if ($_UnitTest && $_Verbose) {
        print ("'$filename'; $t_state; $pkgInstallTime; delta=",
               $t_state-$pkgInstallTime,"\n");
    }

    # If this was already set with a time, we'll override it.
    my $has_priorTime = defined($ref_fileset->{$filename});

    if ($t_state > $pkgInstallTime) {
        unless ( $has_priorTime &&
                 ($pkgInstallTime < $ref_fileset->{$filename}) )
        { # I.e. unless(curInstallTime < previousInstallTime)
            $ref_fileset->{$filename} = $pkgInstallTime;
        }
        return 1; #Something's been set.
    } # else

    # When ($t_state <= $pkgInstallTime), we want to leave
    # $ref_fileset->{$filename} undefined.
    #
    # If an earlier call to this function set $ref_filesetVal, compare our
    # present install time to the one stored earlier.
    if ( $has_priorTime &&
         ($pkgInstallTime > $ref_fileset->{$filename}) )
    {
        # This install time is later than both the previous one and the file's
        # $t_state.  Nuke the old setting.
        delete($ref_fileset->{$filename});
        # Note:  May want to return 0 here.  Yes, we've modified the fileset,
        # but we've also unset the entry.
        #return 1;
    }

    return 0; # Nothing set.
}


############
#
# Exported Functions
#
############


sub get_pkglist(;$) {
    my $updatedSince = 0;
    if (scalar(@_)) {
        $updatedSince = shift;
        --$updatedSince; # Make the cutoff 1 second before this date
    }

    my %pkgset = ();
    my $fmt='%{NAME}\t%{VERSION}\t%{RELEASE}\t%{SERIAL}\t%{INSTALLTIME}'.
        '\t%{SIZE}\n';
    if($_UnitTest || $_Verbose) {
        print "Retrieving RPM package list...";
    }

    open(RPM_IN, "$_rpm_bin -qa --qf \"$fmt\" |");
    while (<RPM_IN>) {
        process_pkgspec(%pkgset, $_, $updatedSince, 1);
    }
    close RPM_IN
        or closePipeDie("rpm -qa");

    if($_UnitTest || $_Verbose) {
        print "\t\tDone.\n";
    }
    return %pkgset;
}


sub isChangeTypeAlias($) {
    my $key = shift;
    return ($key eq "Ownership");
}


sub setChangeTypeAliases(\%) {
    my $ref_changeMap = shift;
    $ref_changeMap->{"Ownership"} = $ref_changeMap->{"Permissions"};
}


# DEVEL. NOTES:
#
# Could you use "rpm -V" instead of the "do it by hand" algorithm used in
# get_changed_since_install()?  Here's what "rpm -V" does:
#
# - Calls "lstat()" on files.  Does something else on URL's.
# - 5 runs an md5sum on the file and compares it to "--qf='%{FILEMD5S}'".
#   It also sets the lstat.st_size field equal to the number of bytes it
#   read while computing the md5sum (on the off-chance, I suppose, that
#   the filesystem was somehow wrong...).
#   Can be replaced with the "Unknown" flag.
# - L compares the symlink's target to "--qf='%{FILELINKTOS}'".
#   Can be replaced with the "Unknown" flag.
# - The "Unknown" flag means that rpm failed to read the file.
# - S compares lstat.st_size to "--qf='%{FILESIZES}'".
#   If a '?' (the "Unknown" flag) appears in place of the '5', you
#   should ignore this flag, since lstat.st_size will have been changed
#   to an invalid size.
# - U compares lstat.st_uid to "--qf='%{FILEUSERNAME}'".
# - G compares lstat.st_gid to "--qf='%{FILEGROUPNAME}'".
# - T compares lstat.st_mtime to "--qf='%{FILEMTIMES}'".
# - D (RDev) checks lstat.st_mode against "--qf='%{FILEMODES}'" for
#   device-type consistency (are they both block devices, both char
#   devices, or both not a device?).
# - M (Mode) compares sb.st_mode to "--qf='%{FILEMODES}'".
#   This means that if the D check fails, then the M check will, as well.
#
# So, you *could* use "rpm -V", but you'll have a good deal of post-processing
# to do given the interdependencies of the different flags.  You'll also be at
# the mercy of internal behavior changes in the "rpm" package software.
#
# Finally ... and worst of all ... the "installation time" recorded by rpm is
# the time that the install *began*.  So, for large packages, most of the
# member files will *always* be marked as modified, even though they're not.


sub get_changed_since_install(\%\%\%$$$) {
    my $ref_pkgset = shift;
    my $ref_fileset = shift;
    my $ref_dirset = shift;
    my $alwaysIncludeDirs_re = shift;
    my $skipModifiedPkgfiles_re = shift;
    my $installTime_delta = shift;

    my @pkgset = sort(keys(%$ref_pkgset));
    my %modified_files = ();
    my $rpm_cmd = "$_rpm_bin -ql";

    my ($n_dirs, $n_files);
    if ($_Verbose) { $n_dirs=keys(%$ref_dirset);
                     $n_files=keys(%$ref_fileset); }

    my $force_included_later_re = qr<^$alwaysIncludeDirs_re>o;
    # If there's no forced-includes, create a bogus regexp that will
    # never match.
    if ($alwaysIncludeDirs_re eq "") {
        $force_included_later_re = qr<^$>o;
    }

    my $skip_re;
    # If there's nothing to skip, create a bogus regexp that will
    # never match.
    if ($skipModifiedPkgfiles_re eq "") {
        $skip_re = qr<^$>o;
    } else {
        # Here, we only skip certain files that we know never truly change,
        # even though RPM thinks they have.
        $skip_re = qr<^$skipModifiedPkgfiles_re>o;
    }

    # Process one package at a time instead of 'rpm -a'.
    if ($_UnitTest || $_Verbose) {
        print "Comparing package contents to actual disk files.\n";
    }

    # Flatten the package hash into one array of arrays.
    my @all_pkgspecs = ();
    foreach my $pkg (@pkgset) {
        my @vers = keys(%{$ref_pkgset->{$pkg}});
        push(@all_pkgspecs, @{$ref_pkgset->{$pkg}}{@vers});
    }

    # Use tmp hashes to ensure list uniqueness.
    my %mf_Permissions = ();
    my %mf_Contents = ();
    my %mf_Symlink = ();
    my %mf_Deleted = ();
    my %mf_Other = ();

    # *Now* iterate over all package names...
    foreach my $ref_pkgspecs (@all_pkgspecs) {
        my $pkg = @$ref_pkgspecs[0] . "-" . @$ref_pkgspecs[1];
        # Since we're using the package install time as a threshold, we can
        # get away with just adding the delta to it.  ($installTime_delta ==
        # the user-provided "Flex_Pkg_InstallTime" option).
        my $pkgInstallTime = @$ref_pkgspecs[4] + $installTime_delta;
        if ($_UnitTest || $_Verbose) {
            print "\tchecking package: $pkg\n";
        }
        open(PKGL_IN, "$rpm_cmd $pkg |");
        while (<PKGL_IN>) {
            my $fn = $_;
            chomp $fn; # Remove newline
            study $fn;

            # Trim whitespace from either side, using Perl idiom
            for ($fn) { s/^\s+//; s/\s+$//; }

            # Skip anything that isn't a filename with an absolute path.
            next if ( ($fn eq "") ||
                      ($fn !~ m<^/>) );

            # Flags used in processing:
            my $isSkippable = ($fn =~ m<$skip_re>);
            my $isIncludedLater = ($fn =~ m<$force_included_later_re>);

            # Skip any files that we are forcibly including into the
            # archive later on.
            unless ($isIncludedLater) {
                # Otherwise, prune it from the appropriate set.
                if (defined( $ref_dirset->{$fn})) {
                    delete $ref_dirset->{$fn};
                }
                elsif (defined($ref_fileset->{$fn})) {
                    delete $ref_fileset->{$fn};
                }
            }

            # At this point, if it's skippable or we're going to include it
            # later, do the next iter.
            next if ($isSkippable || $isIncludedLater);

            # Missing files: check for those first.
            if (! -e $fn) {
                if ($_UnitTest && $_Verbose) {
                    print "\t\tFile no longer exists: '$fn'\n";
                }
                $mf_Deleted{$fn} = 1;
                next;
            }

            # Status flags:
            my $isFile = (-f $fn);
            # Dir flag is masked out by the "isFile" one.
            my $isDir = (-d $fn) && !$isFile;
            my $isSymLink = (-l $fn);
            # Symlink flag masks out the other two:
            $isDir = $isDir && !$isSymLink;
            $isFile = $isFile && !$isSymLink;

            # Examine non-skippable package members for age.
            my @fstats;
            if ($isSymLink) {
                @fstats = lstat($fn);
            } else {
                @fstats = stat($fn);
            }
            if (!scalar(@fstats)) {
                warn "\t\tCannot stat file: $fn.\n";
                next;
            }

            # mtime/ctime/atime use on Linux:
            #
            # The field st_atime (==fstats[8]) is changed by file accesses,
            # e.g. by execve, mknod, pipe, utime and read (of more than zero
            # bytes).  Guaranteed to change, it's not very useful for making a
            # decision about backing up.

            #
            # The field st_mtime (==fstats[9]) is changed by file
            # modifications, e.g. by mknod, truncate, utime and write (of more
            # than zero bytes).  Moreover, st_mtime of a directory is changed
            # by the creation or deletion of files in that directory.  The
            # st_mtime field is not changed for changes in owner, group, hard
            # link count, or mode.
            #
            # The field st_ctime (==fstats[10] is changed by writing or by
            # setting inode information (i.e., owner, group, link count, mode,
            # etc.).  Additionally, the st_ctime of a directory also changes
            # when a file is created or deleted in that directory.

            # Handle dirs first:
            if ($isDir) {
                # This attempts to fix unwanted behavior:  unmodified
                # directories in the %mf_Permissions list.  It doesn't catch
                # every unaltered pkgdirectory, but it gets most.
                next if ($fstats[9] == $fstats[10]);
                # Only modifications we track for directories are permission
                # changes.
                if ($_UnitTest && $_Verbose) {
                    print "\t\tDir ctime: ";
                }
                set_if_older(%mf_Permissions, $fn,
                             $fstats[10], $pkgInstallTime);
                next;
            }

            # Contents modification trumps all others.
            if ($isFile) {
                if ($_UnitTest && $_Verbose) {
                    print "\t\tFile mtime: ";
                }
                unless (set_if_older(%mf_Contents, $fn,
                                     $fstats[9], $pkgInstallTime)) {
                    if ($_UnitTest && $_Verbose) {
                        print "\t\tFile ctime: ";
                    }
                    set_if_older(%mf_Permissions, $fn,
                                 $fstats[10], $pkgInstallTime);
                }
                next;
            }

            # Is this a symlink older than the install date?
            if ($isSymLink) {
                if ($_UnitTest && $_Verbose) {
                    print "\t\tSymLink mtime: ";
                }
                unless (set_if_older(%mf_Symlink, $fn,
                                     $fstats[9], $pkgInstallTime)) {
                    if ($_UnitTest && $_Verbose) {
                        print "\t\tSymLink ctime: ";
                    }
                    set_if_older(%mf_Symlink, $fn,
                                 $fstats[10], $pkgInstallTime);
                }
                next;
            }

            # Are we some other type of file that's changed since the install
            # date?
            if ($_UnitTest && $_Verbose) {
                print "\t\tOther mtime: ";
            }
            unless (set_if_older(%mf_Other, $fn,
                                 $fstats[9], $pkgInstallTime)) {
                if ($_UnitTest && $_Verbose) {
                    print "\t\tOther ctime: ";
                }
                set_if_older(%mf_Other, $fn,
                             $fstats[10], $pkgInstallTime);
            }
        } #end PKGL_IN
        close PKGL_IN;
        my $exitStat = check_syscmd_status({'ignore' => [1],
                                            'warn' => 1,
                                            'no_stacktrace' => 1,
                                            'close_pipe' => 1},
                                           "$rpm_cmd $pkg");
        if ($exitStat) {
            print ("Skipping \"$pkg\".  Is it still installed?\n",
                   "Consider updating the package list and rerunning.\n");
        }
    } #end foreach $pkg

    if ($_UnitTest) {
        my $tmp=keys(%$ref_dirset);
        print "Not part of a package: $tmp directories ";
        $tmp=keys(%$ref_fileset);
        print "and $tmp files.\n";
    }
    if ($_Verbose && $n_dirs && $n_files) {
        print "Pruned ";
        if ($n_dirs) {
            my $dels = $n_dirs - scalar(keys(%$ref_dirset));
            print ("$dels directories (out of $n_dirs total, or ",
                   (100*($dels/$n_dirs)),"\%)");
            if ($n_files) {
                print "\nand ";
            }
        }
        if ($n_files) {
            my $dels = $n_files - scalar(keys(%$ref_fileset));
            print ("$dels files (out of $n_files total, or ",
                   (100*($dels/$n_files)), "\%)");
        }
        print ".\n";
    }

    # Sort before bundling up for return.
    $modified_files{"Permissions"} = [ sort(keys(%mf_Permissions)) ];
    $modified_files{"Contents"} = [ sort(keys(%mf_Contents)) ];
    $modified_files{"Unknown"} = [ ]; # Unused.
    $modified_files{"Symlink"} = [ sort(keys(%mf_Symlink)) ];
    $modified_files{"Deleted"} = [ sort(keys(%mf_Deleted)) ];
    $modified_files{"Other"} = [ sort(keys(%mf_Other)) ];
    setChangeTypeAliases(%modified_files);
    return %modified_files;
}


sub isSupportedChangeType($) {
    my $key = shift;
    return !exists($_UnsupportedChangeTypeSet{$key});
}


sub read_pkgset($\%) {
    my $filename = shift;
    my $ref_pkgset = shift;
    my %tmp_pkgset=();

    if ($_UnitTest || $_Verbose) {
        print "Reading package list...\n";
    }
    my %tmp_pkgset = read_options($filename);
    my $write_date = $tmp_pkgset{'date_written'};

    # This is the preferred list.
    if ( defined($tmp_pkgset{"pkgset"}) &&
         (ref($tmp_pkgset{"pkgset"}) eq "ARRAY") ) {
        foreach (@{$tmp_pkgset{"pkgset"}}) {
            process_pkgspec(%{$ref_pkgset}, $_);
        }
        return $write_date;
    }

    # This is the fallback list.
    unless ( defined($tmp_pkgset{"pkgname_set"}) &&
             (ref($tmp_pkgset{"pkgname_set"}) eq "ARRAY") ) {
        %$ref_pkgset = map({ $_, 1 } @{$tmp_pkgset{"pkgname_set"}});
    }
    return $write_date;
}


sub write_pkgset($\%;$) {
    my $filename = shift;
    my $ref_pkgset = shift;
    my $myName;

    if (scalar(@_)) {
        $myName = shift;
    } else {
        $myName = "rpmUtils::write_pkgset()";
    }

    chmod(0660, $filename);
    open(OFS, ">$filename")
        or failedOpenDie($filename, 'writing');
    # File header.
    print OFS ('#'x79, "\n#\n");
    print OFS ("# List of Installed RPM Packages.\n#\n");
    print OFS ("# Created by $myName.  DO NOT MODIFY.\n");
    print OFS ("#\n", '#'x79, "\n\n");

    # Print the date of the write, in seconds since epoch.
    print OFS ("date_written=", time(), "\n\n");

    # Print the RPM list.
    print OFS ("pkgname_set=(\n");
    foreach (sort(keys(%$ref_pkgset))) { print OFS ($_, "\n"); }
    print OFS (")\n\n", '#'x79, "\n#\n");

    print OFS ("# The previous list contained package names only.\n#\n");
    print OFS ("# It's provided as a convenience so that you know which ");
    print OFS ("packages\n# you need to reinstall.\n#\n");
    print OFS ("# What follows is the package list used by\n");
    print OFS ("# $myName.  Its format is as follows:\n#\n#\n");
    print OFS ("# NAME\\tVERSION\\tRELEASE\\tSERIAL\\tINSTALLTIME\n");
    print OFS ("#\n", '#'x79, "\n\n");

    # Print the entire hash.  Don't forget that a hash can only contain
    # scalars or references.  Hence the list dereference here.
    print OFS ("pkgset=(\n");
    foreach my $k1 (sort(keys(%$ref_pkgset))) {
        foreach my $k2 (reverse(sort(keys(%{$ref_pkgset->{$k1}})))) {
            print OFS (join("\t", @{$ref_pkgset->{$k1}{$k2}}), "\n");
        }
    }
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

rpmUtils - Package for interacting with installed RPM packages.

=head1 SYNOPSIS

=over 0

=item $rpmUtils::_Verbose

=item $rpmUtils::_UnitTest

=item I<%packages> = get_pkglist()

=item I<$flag> = isChangeTypeAlias(I<$changeCategory>)

=item setChangeTypeAliases(I<%changeMap>)

=item I<%h> = get_changed_since_install(I<%packages, %files, %directories,
includedLaterRegexp, skipPkgRegexp, $installTime_delta>)

=item I<$date> = read_pkgset(I<filename, %packages>)

=item write_pkgset(I<filename, %packages>)

=back

=head1 DESCRIPTION

=over 2


=item *

$rpmUtils::_Verbose

"Boolean" integer variable, set to 0 by default.  Set to 1 to enable verbose
messages from the functions in this package.

=item *

$rpmUtils::_UnitTest

"Boolean" integer variable, set to 0 by default.  Set to 1 when performing
unit tests on the functions in this package.

=item *

I<%packages> = get_pkglist()

Returns a hash containing information about all of the installed packages on
this system.  I<%packages> is keyed by the package name.  Each value is an
array ref containing the following information:

=over 2

=item ->[0]: The package name (again).

=item ->[1]: The installed package's version number.

=item ->[2]: The installed package's release number.

=item ->[3]: The installed package's serial number.

This will usually be the string, "(null)".

=item ->[4]: The installation date/time, in seconds since the Epoch.

=item ->[5]: The package size.

=back

Note that the first four elements are strings, while the last one is an
integer.

For RPM packages, the package's recorded installation time indicates when
installation I<began>, so the member files' C<mtime> (or C<ctime>) may be
later than the recorded install time by several seconds.  To compensate,
C<get_pkglist()> uses the package size to estimate how long the package took
to install.  This estimated duration is added to the recorded install
date/time and returned in the last array element.

=item *

I<$flag> = isChangeTypeAlias(I<$changeCategory>)

Returns 1 if I<$changeCategory> is an "alias key", 0 otherwise.

C<get_changed_since_install()> returns a hash of arrayrefs.  Some of the keys
in that hash point to the same arrayref in memory.

=item *

setChangeTypeAliases(I<%changeMap>)

Creates the "alias keys" described in C<isChangeTypeAlias>, modifying
I<%changeMap>.  C<get_changed_since_install()> calls this function.

=item *

I<%h> = get_changed_since_install(I<%packages, %files, %directories,
includedLaterRegexp, skipPkgRegexp, $installTime_delta>)

This function uses a package's installation timestamp to find its modified
member files.  As it loops through each package, it ignores any filename
matching the regexp, I<skipPkgRegexp>.  It also ignores filenames matching
I<includedLaterRegexp>, assuming that you will add them or their parent
directory later.

During an earlier design of this module, there were two separate functions
that scanned the manifest (the list of files it installs) of each package in
I<%packages> to find the modified member files.  Furthermore, it used features
of the packaging tool to determine which member files had changed.  Due to
quirks in the packaging tool (or my lack of understanding of it), it didn't
capture all of the changed files, nor did it correctly see certain types of
changes.

Unlike its predecessors, this function specifically uses C<stat()> to directly
determine how a package member file has changed.

The returned hash contains references to arrays of filenames.  The key to each
file list identifies how it has been modified:

=over 4

=item "Contents"

The file's C<mtime> is later than the parent package's installation time.  The
file is a regular file (not a symlink, device, socket, etc.).

=item "Deleted"

The file no longer exists on disk.

=item "Symlink"

The file is a symlink with an C<mtime> I<or> C<ctime> later than the parent
package's installation time.

=item "Permissions"

=item "Ownership"

The file I<or> directory has a C<ctime> later than the parent
package's installation time.

These keys point to array refs with identical contents (they may even point to
the same array).

This is also the only array ref containing both files and directories.  All
others contain only files.

=item "Unknown"

Unused

=item "Other"

The file is neither a directory, symlink or regular file, and has an C<mtime>
I<or> C<ctime> later than the parent package's installation time.

=back

The documentation for both versions of C<stat> (C<perdoc -f stat>; C<man 2
stat>) describe what C<ctime> means.

The parameter I<$installTime_delta> is a fixed adjustment, in seconds, to the
package installation time returned by C<get_pkglist()>.  Since
C<get_pkglist()> must estimate when the package's installation completed, the
value of I<$installTime_delta>, reflects an upper-limit on the error in this
estimate.

(Note that I<$installTime_delta> affects all packages.  For the occasional
package that takes a very long time to install, you could instead specifically
omit its static member files using the I<skipPkgRegexp> parameter.)

=item *

I<$date> = read_pkgset(I<filename, %packages>)

Inverse operations to C<write_pkgset> (below).  Reads a package list from the
specified I<filename>, storing the results in I<%packages>.  The I<%packages>
hash has the same structure as the one returned by C<get_pkglist>.
Returns the date (in seconds since epoch) when the file was written.

=item *

write_pkgset(I<filename, %packages>)

Writes the package information in I<%packages> to the specified I<filename>.
The I<%packages> hash has the same structure as the one returned by
C<get_pkglist>.

=back

=cut


#################
#
#  End
