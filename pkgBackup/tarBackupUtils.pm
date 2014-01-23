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


package tarBackupUtils;
require 5;
use strict;

BEGIN {
    use Exporter ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # if using RCS/CVS, this may be preferred
    $VERSION = do { my @r = (q$Revision: 1401 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

    @ISA         = qw(Exporter);

    # Default exports.
    @EXPORT = qw(write_archive_filelist do_full_pathlist_backup
                 do_full_filelist_backup do_incremental_filelist_backup
                 verify_listfile_archive
                 do_full_gtar_backup do_incremental_gtar_backup);
    # Permissable exports.
    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK = qw($_Verbose $_UnitTest $_NoExec);

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
our $_NoExec; $_NoExec = 0;


############
#
# Internal Variables
#
############


# Constants
my $_TarSuffix=".tar.bz2";
my $_BackupStateFile_Suffix=".state";
my $_FullBakInfix="-full";
my $_IncrBakInfix="-incr";
my $_PathBakInfix="-paths";
my $_tar_bin="/bin/tar";
my %_Statefile_Syntax = ("Last.Full" => "",
                         "Last.Incremental" => "",
                         "All.Incremental" => "ARRAY");


############
#
# Internal Functions
#
############


sub read_backup_dates($) {
    my $statefile=shift;

    if ($_UnitTest && $_NoExec) {
        print "#UT# Would read: \"$statefile\".  ".
            "Returning fixed date instead.\n";
        return ("Last.Full" => "20040102",
                "Last.Incremental" => "20040603",
                "All.Incremental" => ["20040103",
                                      "20040202",
                                      "20040304",
                                      "20040403",
                                      "20040506",
                                      "20040603"]);
    }

    return read_options($statefile, %_Statefile_Syntax);
}


sub write_backup_dates($$;@) {
    my $statefile=shift;
    my $lastFull=shift;
    my @allIncrementals=@_;

    # Must always have a "lastFull".
    if ($lastFull eq "") {
        print STDERR ("Call to write_backup_dates():  ",
                      "no date/time specified for last\n",
                      "full backup.\nNo changes made to \"$statefile\".\n");
        return;
    }

    if ($_UnitTest && $_NoExec) {
        print "#UT# Would write: \"$statefile\"\n";
        return;
    }

    chmod(0664, $statefile);
    open(OFS, ">$statefile")
        or failedOpenDie($statefile, 'writing');
    # File header.
    print OFS ('#'x79, "\n#\n");
    print OFS ("# Backup State File.\n#\n");
    print OFS ("# Created by module \"tarBackupUtils\".  DO NOT MODIFY.\n");
    print OFS ("#\n", '#'x79, "\n\n");

    # Print the data
    print OFS ("Last.Full=", $lastFull, "\n\n");
    if (scalar(@allIncrementals) > 0) {
        print OFS ("Last.Incremental=", $allIncrementals[0], "\n\n");
        print OFS ("All.Incremental=(\n");
        foreach (@allIncrementals) { print OFS ($_, "\n"); }
    } else {
        print OFS ("Last.Incremental=\n\n");
        print OFS ("All.Incremental=(\n");
    }
    print OFS (")\n\n");

    # File footer.
    print OFS ("\n", '#'x10, "\n# End\n#\n");
    close OFS;
    chmod(0444, $statefile);
}


sub make_listfile_tar_args($$$$$;@) {
    # dest-dir is the first arg.
    my $tarball = shift;
    if ($tarball eq "") { $tarball="."; }
    if ($tarball !~ m|/$|) { $tarball .= "/"; }
    # Next is the archive name prefix.  Trim leading '/', since it's not
    # needed.
    $_[0] =~ s|^/||;
    $tarball .= shift;
    my $archive_file_pre=$tarball;
    # next is the archive name infix.
    $tarball .= shift;
    # The remainder are standalone args.
    my $archive_label = shift;
    my $tar_filelist = shift;

    # Append tarball suffix.
    $tarball .= $_TarSuffix;
    if ($_Verbose) {
        return ($archive_file_pre, "-v", "-jcp", "--file=$tarball",
                 "--label=$archive_label",
                 "--files-from=$tar_filelist",
                @_);
    } # else
    return ($archive_file_pre, "-jcp", "--file=$tarball",
            "--label=$archive_label",
            "--files-from=$tar_filelist",
            @_);
}


sub make_gtar_backup_args($$$\@) {
    my $ref_excludelist=pop;
    my ($is_full,
        $ar_dir,
        $ar_name) = @_;

    my $today = datestamp();
    my $ar_infix = $_IncrBakInfix;
    if($is_full) {
        $ar_infix .= $_FullBakInfix;
    }
    $ar_infix .= "-$today";

    my @excludeopts = map({ "--exclude='" . $_ . "'"
                            } @$ref_excludelist);

    my @tarargs = make_listfile_tar_args($ar_dir, $ar_name,
                                         $ar_infix,
                                         ("backup-" . $today),
                                         "none",
                                         "--ignore-opts",
                                         @excludeopts);

    # Pull out the --files-from arg.  We don't use it here.
    if($_Verbose) {
        splice(@tarargs, 5, 1);
    } else {
        splice(@tarargs, 4, 1);
    }

    # Add snarfile option (listed-incremental).
    my $snarfile = shift(@tarargs);
    $snarfile .= ".snar";
    push(@tarargs, "--listed-incremental=".$snarfile);

    # For full backups, we nuke the old snarfile
    if($is_full) {
        unlink $snarfile;
    }

    return @tarargs;
}


sub exec_tar(@) {
    my @tar_args=@_;

    # In case some of the files in the manifest have disappeared since the
    # manifest was created.
    push(@tar_args, "--ignore-failed-read");

    print "Archiving with command: \"$_tar_bin @tar_args\"\n"
        if ($_UnitTest || $_Verbose);
    # This can return errors when deleted files are still in the archive
    # list.
    unless ($_UnitTest && $_NoExec) {
        system($_tar_bin, @tar_args);
        check_syscmd_status("tar");
        print("\"$_tar_bin\" returned with exit code $?\n")
            if ($_UnitTest || $_Verbose);
    }
}


############
#
# Exported Functions
#
############


sub write_archive_filelist($@) {
    my $filename = shift;
    my @speclist = @_;
    my @dummyarr=();

    if ($_UnitTest && $_NoExec) {
        print "#UT# Would write: \"$filename\"\n";
        return;
    }

    chmod(0660, $filename);
    open(OFS, ">$filename")
        or failedOpenDie($filename, 'writing');
    # File has no header/footer.  Tar expects only filenames or typeglobs
    foreach (sort(@speclist)) { print OFS ($_, "\n"); }
    close OFS;
    chmod(0440, $filename);
}


# Since the arguments to this command don't have separate variables, I'll
# outline them:
#
#     do_full_pathlist_backup(<arfile_path>, <arfile_name_prefix>,
#                             <ar_specfile>));
#
# ...where "<ar_specfile>" is the name of a file containing the list of paths
# to backup.
sub do_full_pathlist_backup($$$) {
    my $today = datestamp();
    my @tar_args=make_listfile_tar_args($_[0], $_[1],
                                        ($_PathBakInfix
                                         . $_FullBakInfix
                                         . "-"
                                         . $today
                                         ),
                                        ("all" . $_PathBakInfix .
                                         "-backup-" . $today),
                                        $_[2],
                                        "--no-recursion");

    # Pull the path-delimited archive file prefix off of the front of the
    # arglist.  Throw it away, since we don't need it here.
    shift(@tar_args);

    exec_tar(@tar_args);
}


# Since the arguments to this command don't have separate variables, I'll
# outline them:
#
#     do_full_filelist_backup(<arfile_path>, <arfile_name_prefix>,
#                             <ar_specfile>));
#
# ...where "<ar_specfile>" is the name of a file containing the list of files
# to backup.
sub do_full_filelist_backup($$$) {
    my $today = datestamp();
    my @tar_args=make_listfile_tar_args($_[0], $_[1],
                                        $_FullBakInfix."-".$today,
                                        ("backup-" . $today), $_[2]);

    # Pull the path-delimited archive file prefix off of the front of the
    # arglist.
    my $statefile = shift(@tar_args);
    $statefile .= $_BackupStateFile_Suffix;

    exec_tar(@tar_args);

    # Write the full backup date to the state-file, overwriting its original
    # contents.
    write_backup_dates($statefile, $today);
}


# Since the arguments to this command don't have separate variables, I'll
# outline them:
#
#     do_incremental_filelist_backup(<arfile_path>, <arfile_name_prefix>,
#                                    <ar_specfile>));
#
# ...where "<ar_specfile>" is the name of a file containing the list of files
# to backup.
sub do_incremental_filelist_backup($$$) {
    my $today = datestamp();
    my @tar_args=make_listfile_tar_args($_[0], $_[1],
                                        $_IncrBakInfix."-".$today,
                                        ("backup-" . $today), $_[2]);

    # Pull the path-delimited archive file prefix off of the front of the
    # arglist.
    my $statefile = shift(@tar_args);
    $statefile .= $_BackupStateFile_Suffix;

    # Read the state file
    my %backup_state = read_backup_dates($statefile);

    # Determine the date after which we backup files.
    my $incremental_arg = "--newer=";
    if (not_empty($backup_state{"Last"}{"Incremental"})) {
        $incremental_arg .= $backup_state{"Last"}{"Incremental"};
    } else {
        $incremental_arg .= $backup_state{"Last"}{"Full"};
    }

    # Run the backup.
    exec_tar(@tar_args, $incremental_arg);

    # Write the full backup date to the state-file, using "today" for the new
    # "latest incremental backup" time.
    write_backup_dates($statefile,
                       $backup_state{"Last"}{"Full"},
                       $today,
                       @{$backup_state{"All"}{"Incremental"}});
}


sub verify_listfile_archive($$$) {
    my $tarball=shift;
    my $tar_dirList_file=shift;
    my $tar_fileList_file=shift;
    my %omission_set=();
    my @surplus_list=();
    my $tar_cmd=$_tar_bin;
    $tar_cmd .= "-jtf " . $tarball;

    my $tar_list_file = $tar_fileList_file;
    if ($tarball =~ m/$_PathBakInfix/o) {
        $tar_list_file = $tar_dirList_file;
    }

    if ($_Verbose || $_UnitTest) {
        print "Reading files/paths from tar speclist: \"$tar_list_file\".\n";
    }

    # Begin by reading in the files/dirs originally submitted to "tar".
    open(IFS, "$tar_list_file")
        or failedOpenDie($tar_list_file, 'reading');
    # File has no header/footer.  Tar expects only filenames or typeglobs
    while (<IN_FS>) {
        my $name = $_;
        chomp $name; # Remove newline
        $omission_set{$name} = 1;
    }
    close IFS;

    if ($_Verbose || $_UnitTest) {
        print "Comparing to listing of archive: \"$tarball\".\n";
    }

    open(TBV_IN, "$tar_cmd |");
    my $tar_label = <TBV_IN>; # Skip this.
    while (<TBV_IN>) {
        my $file = "/" . $_;
        chomp $file;
        if (defined($omission_set{$file})) {
            delete $omission_set{$file};
        }
        else {
            # Odd... it's in the list, but not in the tarball...
            push(@surplus_list, $file);
        }
    }
    close TBV_IN or closePipeDie("tar -jtf");

    my @omission_list = sort(keys(%omission_set));
    my $n_omissions = scalar(@omission_list);
    my $n_surplus = scalar(@surplus_list);
    if ($n_surplus || $n_omissions) {
        print "Verification Complete.  Errors found in archive.\n";
    } else {
        print "Archive verified: No errors.\n";
        return;
    }

    if ($n_surplus) {
        print "Found files in the archive not specified ";
        print "in the listings file.\n\nsurplus_files=(\n\t";
        print join("\n\t", @surplus_list);
        print "\n)\n\n";
    }

    if ($n_omissions) {
        print "Files were omitted from the archive.";
        print "\n\nomitted_files=(\n\t";
        print join("\n\t", @omission_list);
        print "\n)\n\n";
    }
}


sub do_full_gtar_backup($$\@\@) {
    my ($ar_dir,
        $ar_name,
        $ref_excludelist,
        $ref_filelist) = @_;

    my @tar_args = make_gtar_backup_args(1, $ar_dir, $ar_name,
                                         @$ref_excludelist);

    # Run the backup.
    exec_tar(@tar_args, @$ref_filelist);
}


sub do_incremental_gtar_backup($$\@\@) {
    my ($ar_dir,
        $ar_name,
        $ref_excludelist,
        $ref_filelist) = @_;

    my @tar_args = make_gtar_backup_args(0, $ar_dir, $ar_name,
                                         @$ref_excludelist);

    # Run the backup.
    exec_tar(@tar_args, @$ref_filelist);
}


1;  # don't forget to return a true value from the file
## POD STARTS HERE ##
__END__

=head1 NAME

tarBackupUtils - Package for performing backups via GNU tar.

=head1 SYNOPSIS

=over 0

=item write_archive_filelist I<listfile_name> (I<filenames> ...)

=item do_full_pathlist_backup I<arfile_path>, I<arfile_prefix>,
I<listfile_name>

=item do_full_filelist_backup I<arfile_path>, I<arfile_prefix>,
I<listfile_name>

=item do_incremental_filelist_backup I<arfile_path>, I<arfile_prefix>,
I<listfile_name>

=item verify_listfile_archive I<tarfile>, I<listfile_dirList>,
I<listfile_dirList>

=item do_full_gtar_backup I<arfile_path>, I<arfile_prefix>,
I<@excludelist>, I<@filelist>

=item do_incremental_gtar_backup I<arfile_path>, I<arfile_prefix>,
I<@excludelist>, I<@filelist>

=back

=head1 DESCRIPTION

=over 2

=item *

write_archive_filelist I<listfile_name>, I<@filenames>

Writes the list, I<@filenames>, to the file I<listfile_name>.  The list of
files in I<listfile_name> will be archived by the other functions in this
package.

=item *

do_full_pathlist_backup I<arfile_path>, I<arfile_prefix>,
I<listfile_name>

Perform a full backup of all of the paths specified in I<listfile_name> (which
was written by an earlier call to
L<write_archive_filelist()|/"write_archive_filelist">).  I<arfile_path> is the
directory in which to create the archive.  I<arfile_prefix> is the name of the
archive, which will be appended with appropriate suffixes.

This function expects the file I<listfile_name> to contain a list of only
directories.  It will do a non-recursive, full backup.  The suffixes in the
archive's name will reflect this.

=item *

do_full_filelist_backup I<arfile_path>, I<arfile_prefix>,
I<listfile_name>

Perform a full backup of all of the files specified in I<listfile_name> (which
was written by an earlier call to
L<write_archive_filelist()|/"write_archive_filelist">).  I<arfile_path> is the
directory in which to create the archive.  I<arfile_prefix> is the name of the
archive, which will be appended with appropriate suffixes.

This function expects the file I<listfile_name> to contain a list of only
filenames, and no directories.  The suffixes in the archive's name will
reflect this, as well as the fact that this is a full backup.

=item *

do_incremental_filelist_backup I<arfile_path>, I<arfile_prefix>,
I<listfile_name>

Perform an incremental backup of all of the files specified in
I<listfile_name> (which was written by an earlier call to
L<write_archive_filelist()|/"write_archive_filelist">).  I<arfile_path> is the
directory in which to create the archive.  I<arfile_prefix> is the name of the
archive, which will be appended with appropriate suffixes.

This function expects the file I<listfile_name> to contain a list of only
filenames, and no directories.  The suffixes in the archive's name will
reflect this, and will also include a date-stamp to indicate that this is an
incremental backup.

=item *

verify_listfile_archive I<tarfile>, I<listfile_name_dirs>,
I<listfile_name_files>

Verify that the archive I<tarfile> contains all of the files or directories
specified in the files I<listfile_name_files> or
I<listfile_name_dirs>, respectively.  The function uses the name of I<tarfile>
to determine which I<listfile_*> arg to use.

Call this function after a call to
L<do_full_pathlist_backup()|/"do_full_pathlist_backup"> or
L<do_full_filelist_backup()|/"do_full_filelist_backup">
to double-check that C<tar> did indeed archive everything that you told it to.

=item *

do_full_gtar_backup I<arfile_path>, I<arfile_prefix>, I<@excludelist>,
I<@filelist>

=item *

do_incremental_gtar_backup I<arfile_path>, I<arfile_prefix>,
I<@excludelist>, I<@filelist>

Performs either an incremental or full backup of the files and directories in
I<@filelist>, creating the archive and relevant files in I<arfile_path>.  Uses
GNU tar to perform the archiving.  I<arfile_prefix> is the name of the GNU tar
archive, which will be appended with appropriate suffixes.

I<@excludelist> is a set of fileglob patterns which will be passed to the GNU
tar "--exclude" option.  The patterns are case-insensitive.

=back

=head2 Miscellaneous notes on GNU C<tar>

=over 2

=item *

The `--gzip' (`--gunzip', `--ungzip', `-z') option does not work
with the `--multi-volume' (`-M') option, or with the `--update' (`-u'),
`--append' (`-r'), `--concatenate' (`--catenate', `-A'), or `--delete'
operations.

=item *

'--listed-incremental' and '--newer' do not work together.

=item *

The "--listed-incremental" option overrides the "--no-recursion"
option.  You should, therefore, not place directories in the file you pass to
the  '--files-from' unless you want ALL of that directories' contents in
the archive.

=item *

'--file-from' plus '--exclude' does weird things.

=back

=cut

#################
#
#  End
