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
# All of these are modifyable from a config file.  The following are merely
# defaults.
#
############


my @_AlwaysIncludeDirs=("/etc","/root");
my $_Working_Dir="";
my $_Archive_Prefix="localhost-backup";
my $_Archive_Destination_Dir="/scratch/BACKUP";
my $_InstallTime_Delta=10;


############
#
# Precompilation Init
#
############
# Unlike my other scripts, this one expects to be called from a parent, one
# that pulls in all of the specific packages.
#
# I use two scripts instead of making this a package because I want to merge
# the %main:: symbol table in this core script with the custom symbols pulled
# into %main:: by the parent script.
my $_MyName;
my $_MyRealName="pkgBackup.pl";
my $_MyPath;
BEGIN {
    if ($0 =~ m|\A(.*)/([^/]+\Z)|) {
        if ($1 ne ".") {
            $_MyPath = $1;
            push(@INC, $1);
        }
        $_MyName = $2;
    } else { $_MyName = $0; }  # No path; only the script name.
    ($0 =~ m/(?:rpm|deb)backup/i)
        or die("Cannot run as \"$0\" directly.\n".
               "It must be \"require\"-ed from the appropriate parent/".
               "wrapper script.\nAborting...\n");
}


############
#
# Includes/Packages
#
# Only the ones that aren't "customizable" go here.
# (Customizable packages would include DEB-vs-RPM or tar-vs-another archiver.)
#
############


require 5;
use strict;
use Getopt::Long;
use Pod::Usage;
use File::Basename;
use Fcntl qw(:mode);
use masterListTools;
use jpwTools;


############
#
# Other Global Variables
#
############


my $_MasterLists_File="master-files.lst";
my $_PkgLists_File="all-pkgs.lst";
my $_ModifiedPkgFLists_File="modified-pkg-files.lst";
my $_File_ArchiveManifest="tar-files-wrk.lst";
my $_Dir_ArchiveManifest="tar-dirs-wrk.lst";

# Files to skip when examining modified package files.  The files in '/dev'
# are always different, but never truly change from their packaged versions,
# so skip them.
# The other paths are ones that I moved to different partitions (specifically,
# "/usr/src"), or are documentation/manual directories.
my $_SkipModifiedPkgfiles_re
    ='/(?:dev|usr/(?:doc|man|s(?:hare/(?:doc|man)|rc)))';
my $_AlwaysIncludeDirs_re=create_regexp_group(@_AlwaysIncludeDirs);

# Internal Globals
# No User Servicable Parts Inside.

my $_UsageHdr="$_MyName:\t";
my $_UnitTest = 0;
my $_Verbose = 0;

my %_CfgfileValidations
    = ("Archive_Prefix" => "",
       "Archive_Destination_Dir" => "",
       "Working_Dir" => "",
       "ExcludeDirs.ModifiedPkgfiles" => "ARRAY",
       "AlwaysIncludeDirs" => "ARRAY",
       "ExcludeFilesystems.Master" => "ARRAY");

#
# Restore-Script Vars
# These are basically shell scripts.
#

my @_rScript_Header_Top
    =('!/bin/sh',
      '',
      'Created by '.$_MyName.' for use during a restore.',
      '',
      'Rather than waste archive space with files whose contents',
      'haven\'t changed since their parent package was installed,',
      'we\'ll use these scripts to modify the package files as',
      'follows:',
      '');
my @_rScript_Header_Bottom
    = ('',
       'The custom functions in this script may seem more complex',
       'than necessary, considering that the GNU utils will do the',
       'same in fewer steps.  However, there\'s no guarantee that',
       'you\'re running this script from a full environment.  This',
       'script is meant to run in any environment, including under',
       'Busybox, sash, or other "bundled" shells.',
       '');

my @_rScript_Core
    = ('# Mark this run in the $ERRLOG',
       'echo "" >>$ERRLOG',
       'echo "# `date`" >>$ERRLOG',
       'echo "# The following actions failed:" >>$ERRLOG',
       '',
       'check_op() {',
       '    stat_last_op=$1',
       '    shift',
       '    action="$*"',
       '    if [ $stat_last_op -ne 0 ]; then',
       '        echo "Action Failed: \`$action\'"',
       '        echo "$action" >> $ERRLOG',
       '    fi',
       '}',
       '',
       'verbose_message() {',
       '    mesg="$1"',
       '    shift',
       '    if [ -n "$3" ]; then',
       '        echo "   changing ${mesg} of \"$2\" to \"$1\""',
       '    elif [ -n "$2" ]; then',
       '        echo "   ${mesg}: \"$1\" -> \"$2\""',
       '    else',
       '        echo "   ${mesg}: \"$1\""',
       '    fi',
       '}');

my $_DeleteDefunctScript="delete-defunct.sh";
my $_DeleteDefunctScript_Purpose =
    "Remove package files that had been deleted.";
my @_DeleteDefunctScript_Body
    = ('DEFUNCT_PATH="/tmp/defunct"',
       '',
       'safe_rm() {',
       '    targ="$1"',
       '    shift',
       '    if [ ! -r $targ ]; then',
       '        echo "Cannot read \\"$targ\\"; skipping."',
       '        return 0',
       '    fi',
       '',
       '    targs_path=`dirname $targ`',
       '    dest_path="${DEFUNCT_PATH}"',
       '    case $targs_path in',
       '        \\./*|\\.\\./*)',
       '            dest_path="${DEFUNCT_PATH}/${targs_path}"',
       '            ;;',
       '        /*)',
       '            dest_path="${DEFUNCT_PATH}${targs_path}"',
       '            ;;',
       '    esac',
       '    if [ ! -d $dest_path ]; then',
       '        verbose_message "creating directory" $dest_path',
       '        mkdir -p $dest_path',
       '        stat=$?; if [ $stat -ne 0 ]; then return $stat; fi',
       '    fi',
       '',
       '    verbose_message "copying" $targ ${dest_path}/',
       '    cp -a $targ ${dest_path}/',
       '    stat=$?; if [ $stat -ne 0 ]; then return $stat; fi',
       '    verbose_message "deleting" $targ',
       '    rm -f $targ',
       '    return $?',
       '}');

my $_RestorePermsScript="restore-permissions.sh";
my $_RestorePermsScript_Purpose =
    "Restore custom permissions.";
my @_RestorePermsScript_Body
    = ('set_perms() {',
       '    targ="$1"',
       '    shift',
       '    perms="$1"',
       '',
       '    if [ ! -r $targ ]; then',
       '        echo "Cannot read \\"$targ\\"; skipping."',
       '        return 1',
       '    fi',
       '',
       '    verbose_message "permissions" "$perms" $targ 1',
       '    chmod "$perms" $targ',
       '    return $?',
       '}');

my $_RestoreOwnerScript="restore-ownership.sh";
my $_RestoreOwnerScript_Purpose =
    "Restore custom ownership.";
my @_RestoreOwnerScript_Body
    = ('set_owner() {',
       '    targ="$1"',
       '    shift',
       '    ownership="$1"',
       '',
       '    if [ ! -r $targ ]; then',
       '        echo "Cannot read \\"$targ\\"; skipping."',
       '        return 1',
       '    fi',
       '',
       '    verbose_message "owner" "$ownership" $targ 1',
       '    chown "$ownership" $targ',
       '    return $?',
       '}');

my $_RestoreSymlinksScript="restore-symlinks.sh";
my $_RestoreSymlinksScript_Purpose =
    "Recreate custom symlinks that had replaced package files.";
my @_RestoreSymlinksScript_Body
    = ('make_symlink() {',
       '    src=$1',
       '    shift',
       '    symlink_dir=$1',
       '    shift',
       '    symlink=$1',
       '    shift',
       '    ownership=$1',
       '    shift',
       '',
       '    cd $symlink_dir',
       '    stat=$?; if [ $stat -ne 0 ]; then return $stat; fi',
       '',
       '    if [ ! -r $src ]; then',
       '        echo "Cannot read \\"$src\\"; skipping."',
       '        return 1',
       '    fi',
       '',
       '    bakfile=${symlink}.orig',
       '    if [ -r $symlink ]; then',
       '        echo "File/dir in the way.  Renaming..."',
       '        if [ -r $bakfile ]; then',
       '            echo "Backup targ exists:  \\"$bakfile\\".  '.
       'Cannot continue."',
       '            return 1',
       '        fi',
       '        verbose_message "renaming" $symlink $bakfile',
       '        mv $symlink $bakfile',
       '        stat=$?; if [ $stat -ne 0 ]; then return $stat; fi',
       '    fi',
       '',
       '    verbose_message "creating symlink \\"$symlink\\" to" $src',
       '    ln -s $src $symlink',
       '    stat=$?; if [ $stat -ne 0 ]; then return $stat; fi',
       '',
       '    verbose_message "owner" "$ownership" $targ 1',
       '    chown "$ownership" $symlink',
       '    return $?',
       '}');


########################################################################
#
# Functions
#
########################################################################


sub My_pod2usage($;$$) {
    my ($exitstat, $show_usage, $errmsg) = @_;
    my %usgmap = (-output => \*STDOUT,
                  -verbose => 1+$_Verbose,
                  -exitval => $exitstat,
                  -input => $_MyPath."/".$_MyRealName);
    if ($show_usage) {
        $usgmap{"-msg"} = $_UsageHdr.$errmsg."\n";
        $usgmap{"-verbose"} = 1;
    }
    pod2usage(%usgmap);
    exit 0;
}


sub print_ut {
    if ($_UnitTest) {
        print @_;
    }
}


sub print_hash_ut(\%;$) {
    my $map_ref=shift;
    my $name = "";
    if (scalar(@_)) { $name = shift; }

    if ($_UnitTest) {
        print_hash($name, %$map_ref);
    }
}


sub create_or_update_rscript($$\@) {
    my $scriptname = $_Archive_Destination_Dir. "/";
    $scriptname .= shift;
    $scriptname =~ s|//|/|g;
    my $purpose = shift;
    my $ref_script_body = shift;

    my $how = "+<";
    my $how_mesg = "update";
    my $scriptExists = (-e $scriptname);
    my $mode = S_IRWXU|S_IRGRP|S_IXGRP;
    my $ofh;
    unless ($scriptExists) {
        # Create the file first, so we can "chmod" it next.
        open($ofh, '>', $scriptname)
            or failedOpenDie($scriptname, 'writing');
        close($ofh);
        $how_mesg = "writing";
    }

    chmod($mode, $scriptname);
    open($ofh, $how, $scriptname)
        or failedOpenDie($scriptname, $how_mesg);

    if ($scriptExists) {
        # Scan ahead until we find the marker line for the per-file actions.
        seek($ofh, 0, 0);
        while(<$ofh>) {
            last if (m/^\#\s+===Begin Actions===/);
        }
        # We now point to the line after this marker.
        seek($ofh, 0, 1);
    }
    else {
        my $fail_log="/tmp/".basename($scriptname,qr{\.sh}).".log";
        print $ofh ("\#", join("\n\# ", @_rScript_Header_Top), "\n");
        print $ofh ("\#     $purpose\n");
        print $ofh ("\#", join("\n\# ", @_rScript_Header_Bottom), "\n",
                    "\#"x78, "\n\n\n");
        print $ofh ("\#\n",
                    "\# Functions & Global Variables\n",
                    "\#\n\n\n");
        print $ofh ("ERRLOG=\"$fail_log\"\n\n");
        print $ofh (join("\n", @_rScript_Core), "\n\n");
        print $ofh (join("\n", @{$ref_script_body}), "\n\n\n");
        print $ofh ("\#"x78, "\n\#\n\# Main\n\#\n", "\#"x78, "\n\n\n");
        print $ofh ("\# ===Begin Actions===\n");
    }

    # Write an updated update-time.
    print $ofh ("\n\n\# Last Updated: ".localtime()."\n\n");
    return ($ofh, $scriptname);
}


sub rscript_print_action(\*$) {
    my $ofh = shift;
    my $action = shift;

    $action =~ s/\'/\\\'/g;
    print $ofh ($action, "\n",
                "check_op \$? '$action'\n\n");
}


sub close_rscript(\*) {
    my $ofh = shift;

    print $ofh ("\n\n");
    print $ofh ("echo \"\"\n",
                "echo \"\"\n",
                "echo \"Restore actions complete.  See ",
                "\\\"\$ERRLOG\\\"",
                " for a list of \"\n",
                "echo \"failed actions (if any).\"\n");
    print $ofh ("\n\n",
                "\#"x20, "\n",
                "\#\n",
                "\# End\n",
                "\#\n");
    # Truncate the file.
    truncate($ofh, tell($ofh));
    close $ofh;
}


sub make_deletion_rscript(\@) {
    my $ref_defunctFiles = shift;

    my ($OFH, $trueScriptname)
        = create_or_update_rscript($_DeleteDefunctScript,
                                   $_DeleteDefunctScript_Purpose,
                                   @_DeleteDefunctScript_Body);

    foreach my $file (sort(@$ref_defunctFiles)) {
        rscript_print_action(*$OFH, "safe_rm $file");
    }

    close_rscript(*$OFH);
    return $trueScriptname;
}


sub make_perms_rscript(\@) {
    my $ref_permFiles = shift;

    my ($OFH, $trueScriptname)
        = create_or_update_rscript($_RestorePermsScript,
                                   $_RestorePermsScript_Purpose,
                                   @_RestorePermsScript_Body);

    foreach my $file (sort(@$ref_permFiles)) {
        my @filestats = stat($file);
        my $perms = sprintf("%04o", S_IMODE($filestats[2]));
        rscript_print_action(*$OFH,
                             "set_perms $file \"$perms\"");
    }

    close_rscript(*$OFH);
    return $trueScriptname;
}


sub make_owner_rscript(\@) {
    my $ref_permFiles = shift;

    my ($OFH, $trueScriptname)
        = create_or_update_rscript($_RestoreOwnerScript,
                                   $_RestoreOwnerScript_Purpose,
                                   @_RestoreOwnerScript_Body);

    foreach my $file (sort(@$ref_permFiles)) {
        my @filestats = stat($file);
        my $owns = getpwuid($filestats[4]).":".getgrgid($filestats[5]);
        rscript_print_action(*$OFH,
                             "set_owner $file \"$owns\"");
    }

    close_rscript(*$OFH);
    return $trueScriptname;
}


sub make_symlink_rscript(\@) {
    my $ref_symlinks = shift;

    my ($OFH, $trueScriptname)
        = create_or_update_rscript($_RestoreSymlinksScript,
                                   $_RestoreSymlinksScript_Purpose,
                                   @_RestoreSymlinksScript_Body);

    foreach my $symlink (sort(@$ref_symlinks)) {
        my @linkstats = lstat($symlink);
        my $owns = $linkstats[4].":".$linkstats[5];
        my $src = readlink($symlink);
        next if(!defined($src));
        my ($symlink_name,
            $symlink_path,
            $symlink_suf) = fileparse($symlink, qr{\..*});
        rscript_print_action(*$OFH,
                             "make_symlink \"".$src."\" \"".
                             $symlink_path."\" \"".
                             $symlink_name.$symlink_suf."\" \"".$owns."\"");
    }

    close_rscript(*$OFH);
    return $trueScriptname;
}


sub write_modified_pkgfiles($\%) {
    my $filename = shift;
    my $ref_modmap = shift;

    chmod(0644, $filename);
    open(OFS, ">$filename")
        or failedOpenDie($filename, 'writing');
    # File header.
    print OFS ('#'x79, "\n#\n");
    print OFS ("# Modified package files.\n#\n");
    print OFS ("# Created by $_MyName.  DO NOT MODIFY.\n");
    print OFS ("#\n", '#'x79, "\n\n");

    # Print the date of the write, in seconds since epoch.
    print OFS ("date_written=", time(), "\n\n");

    foreach my $modType (sort(keys(%$ref_modmap))) {
        next if (isChangeTypeAlias($modType));
        print OFS ("$modType=(\n");
        if (scalar(@{$ref_modmap->{$modType}})) {
            print OFS (join("\n", sort(@{$ref_modmap->{$modType}})), "\n");
        }
        print OFS (")\n\n", '#'x79, "\n\n");
    }

    # File footer.
    print OFS ("\n", '#'x10, "\n# End\n#\n");
    close OFS;
}


sub read_modified_pkgfiles($\%) {
    my $filename = shift;
    my $ref_modmap = shift;

    %$ref_modmap = read_options($_ModifiedPkgFLists_File);
    my $writeDate = $ref_modmap->{'date_written'};
    delete $ref_modmap->{'date_written'};
    setChangeTypeAliases(%$ref_modmap);
    return $writeDate
}


sub load_config($) {
    my $cfgfile = shift;
    my %params = read_options($cfgfile, %_CfgfileValidations);
    print_hash_ut(%params);

    set_scalar_if_nonempty($_Archive_Prefix, %params, "Archive_Prefix");

    set_scalar_if_nonempty($_Archive_Destination_Dir,
                           %params, "Archive_Destination_Dir");

    set_array_if_nonempty(@masterListTools::_Exclude_fs,
                          %params, "ExcludeFilesystems.Master");

    # Handle some regexps.
    if (not_empty($params{"ExcludeDirs.ModifiedPkgfiles"})) {
        $_SkipModifiedPkgfiles_re
            = create_regexp_group(@{$params{"ExcludeDirs.ModifiedPkgfiles"}});
    }
    if (defined($params{"AlwaysInclude.Pkgfiles"})) {
        # This list can be empty.
        @_AlwaysIncludeDirs = @{$params{"AlwaysInclude.Pkgfiles"}};
        $_AlwaysIncludeDirs_re=create_regexp_group(@_AlwaysIncludeDirs);
    }

    # The working directory.
    set_scalar_if_nonempty($_Working_Dir, %params, "Working_Dir");

    # The installation time delta.
    # Check for correct range.
    my $_InstallTime_Delta_CfgParam = "Flex_Pkg_InstallTime";
    set_scalar_if_nonempty($_InstallTime_Delta, %params,
                           $_InstallTime_Delta_CfgParam);
    unless ( (0 <= $_InstallTime_Delta) && ($_InstallTime_Delta <= 300) ) {
        print("Error in config file:  parameter \"",
              $_InstallTime_Delta_CfgParam, "\" must be in the\n",
              "inclusive range: [0, 120] sec.\n");
        exit 1;
    }
    if ($_InstallTime_Delta > 60) {
        print("Warning:  parameter \"", $_InstallTime_Delta_CfgParam,
              "\" is greater than 1 minute.\n",
              "This is not advisable (but isn't an error).  Continuing...\n");
    }

    # Print out the parameters we've loaded.
    print_ut("_Exclude_fs=( @masterListTools::_Exclude_fs )\n",
             "_Archive_Prefix=\"$_Archive_Prefix\"\n",
             "_Archive_Destination_Dir=\"$_Archive_Destination_Dir\"\n",
             "_SkipModifiedPkgfiles_re=\"$_SkipModifiedPkgfiles_re\"\n",
             "_AlwaysIncludeDirs_re=\"$_AlwaysIncludeDirs_re\"\n");
}


sub process_options($\%@) {
    my $argc = shift;
    my $ref_optmap = shift;
    my @valid_opts = @_;
    my $help = 0;
    my $new_archive_orig=0;

    $ref_optmap->{'help'} = \$help;
    $ref_optmap->{'h'} = \$help;
    @valid_opts = sort(@valid_opts, keys(%$ref_optmap));

    unless (GetOptions($ref_optmap, @valid_opts)) {
        My_pod2usage(1, 1, "Invalid commandline.");
    }
    if ($help) {
        My_pod2usage(0);
    }

    # Read the configuration file now.
    #
    if (scalar(@ARGV)) {
        $ref_optmap->{'conf'} = shift(@ARGV);
        load_config($ref_optmap->{'conf'});
    } elsif (exists $ref_optmap->{'conf'}) {
        load_config($ref_optmap->{'conf'});
    }

    # Let's have a looksie at the options before proceeding.
    print_hash_ut(%$ref_optmap);

    # Certain options *must* be used in combination with others.  Verify this
    # by decrementing $argc, then checking what we end up with.
    if ($_UnitTest) {
        --$argc;
    }
    if ($_Verbose) {
        --$argc;
    }
    if (exists $ref_optmap->{'new_archive'}) {
        # Store the original value of the --new_archive option for use later.
        $new_archive_orig=${$ref_optmap->{'new_archive'}};
        if($new_archive_orig) {
            --$argc;
        }
    }
    if (exists $ref_optmap->{'no_update'}) {
        --$argc;
    }
    if (exists $ref_optmap->{'conf'}) {
        --$argc;
    }
    $argc -= scalar(@ARGV); # The Remaining args.
    if ($argc < 1) {
        My_pod2usage(2, 1, "Missing action option.");
    }

    # Special Unit Testing Options.  They run their appointed tests, then
    # exit.
    #
    if ($_UnitTest) {
        if (exists $ref_optmap->{'build_master_lists'}) {
            my %dirlist=();
            my %filelist=();
            build_master_lists(%filelist, %dirlist);
            print_hash_ut(%dirlist);
            print_hash_ut(%filelist);
            exit 0;
        }
        if (exists $ref_optmap->{'update_master_lists'}) {
            my %dirlist=();
            my %filelist=();
            update_master_lists(%filelist, %dirlist, $_MasterLists_File);
            print_hash_ut(%dirlist);
            print_hash_ut(%filelist);
            exit 0;
        }
        if (exists $ref_optmap->{'write_master_fileset'}) {
            my %dirlist=();
            my %filelist=();
            build_master_lists(%filelist, %dirlist);
            write_master_fileset("./test.fs", %filelist, %dirlist);
            exit 0;
        }
        if (exists $ref_optmap->{'read_master_fileset'}) {
            my %dirlist=();
            my %filelist=();
            read_master_fileset("./test.fs", %filelist, %dirlist);
            print_hash_ut(%dirlist);
            print_hash_ut(%filelist);
            exit 0;
        }
        if (exists $ref_optmap->{'restore_scripts'}) {
            $_Archive_Destination_Dir="./";
            my @dummyBody = ("no_op() {", "x=\$1", "}");
            create_or_update_rscript("utest-createUpdtRestore.sh",
                                     "Unit-tests functionality.",
                                     @dummyBody);
            $_DeleteDefunctScript="utest-delRestore.sh";
            my @utestFilelist = ("/etc/syslog.conf",
                                 "/usr/share/man/man1/bash.1.gz",
                                 "/sbin/service",
                                 "/usr/bin/tclsh");
            make_deletion_rscript(@utestFilelist);
            $_RestorePermsScript="utest-permsRestore.sh";
            make_perms_rscript(@utestFilelist);
            $_RestoreOwnerScript="utest-ownerRestore.sh";
            make_owner_rscript(@utestFilelist);
            my @utestSymlinks = ("/lib/libc.so.6",
                                 "/usr/X11R6/lib/X11/XF86Config",
                                 "/dev/cdrom",
                                 "/dev/mouse");
            $_RestoreSymlinksScript="utest-symlinkRestore.sh";
            make_symlink_rscript(@utestSymlinks);
            exit 0;
        }
    } #end if(unit test)

    # Options needing special processing.
    if (exists $ref_optmap->{'full'}) {
        ${$ref_optmap->{'build_package_list'}} = 1;
        ${$ref_optmap->{'update_package_list'}} = 0;
        ${$ref_optmap->{'scan_pkgfiles'}} = 1;
        ${$ref_optmap->{'write_archive_manifest'}} = 1;
        ${$ref_optmap->{'do_backup'}} = 1;
        ${$ref_optmap->{'new_archive'}} = 1;
    }
    elsif (exists $ref_optmap->{'incremental'}) {
        ${$ref_optmap->{'build_package_list'}} = 0;
        ${$ref_optmap->{'update_package_list'}} = 1;
        ${$ref_optmap->{'scan_pkgfiles'}} = 0;
        ${$ref_optmap->{'write_archive_manifest'}} = 1;
        ${$ref_optmap->{'do_backup'}} = 1;
        ${$ref_optmap->{'new_archive'}} = 0;
    }

    # Some options act as overrides for others, and must override the behavior
    # of --full & --incremental
    if (exists $ref_optmap->{'no_update'}) {
        ${$ref_optmap->{'update_package_list'}} = 0;
    }
    if ($new_archive_orig) {
        ${$ref_optmap->{'new_archive'}} = 1;
    }

    # Set any package-global vars to their main-global equivalents.
    pkgUtils_setVerbose($_Verbose, $_UnitTest);
    $tarBackupUtils::_Verbose = $_Verbose;
    $masterListTools::_Verbose = $_Verbose;
    $tarBackupUtils::_UnitTest = $_UnitTest;
    $masterListTools::_UnitTest = $_UnitTest;
}


sub handle_special_global_params() {
    if ($_Working_Dir eq "") {
        $_Working_Dir = $_Archive_Destination_Dir;
    }
    $_MasterLists_File = $_Working_Dir."/".$_MasterLists_File;
    $_PkgLists_File = $_Working_Dir."/". $_PkgLists_File;
    $_ModifiedPkgFLists_File = $_Working_Dir."/".$_ModifiedPkgFLists_File;
    $_File_ArchiveManifest = $_Working_Dir."/".$_File_ArchiveManifest;
    $_Dir_ArchiveManifest = $_Working_Dir."/".$_Dir_ArchiveManifest;

    print_ut("_Working_Dir=\"$_Working_Dir\"\n",
             "_MasterLists_File=\"$_MasterLists_File\"\n",
             "_PkgLists_File=\"$_PkgLists_File\"\n",
             "_TarFileList_File=\"$_File_ArchiveManifest\"\n",
             "_TarDirList_File=\"$_Dir_ArchiveManifest\"\n");
}


########################################################################
#
# Main
#
########################################################################


sub main {
    my $argc = scalar(@ARGV);
    if ($argc < 1) {
        My_pod2usage(2, 1, "Missing action option.");
    }
    my $build_pkg_list = 0;
    my $update_pkg_list = 0;
    my $scan_pkgs = 0;
    my $write_arManifest = 0;
    my $do_backup = 0;
    my $new_archive = 0;
    my $build_master_list = 0;
    my $update_master_list = 0;

    my %optmap=('verbose' => \$_Verbose,
                'build_package_list' => \$build_pkg_list,
                'update_package_list' => \$update_pkg_list,
                'build_master_list' => \$build_master_list,
                'update_master_list' => \$update_master_list,
                'scan_pkgfiles' => \$scan_pkgs,
                'write_archive_manifest' => \$write_arManifest,
                'do_backup' => \$do_backup,
                'new_archive' => \$new_archive,
                'unit_test' => \$_UnitTest);
    my @optspec=('verbose|v',
                 'build_package_list|build_pkglist|bpkgl',
                 'update_package_list|update_pkglist|upkgl',
                 'build_master_list|build_master|bml',
                 'update_master_list|update_master|bml',
                 'diff_master_list|diff_master|dml',
                 'scan_pkgfiles|check_pkgfiles|scan_rpms|scan_debs',
                 'write_archive_manifest|make_manifest|write_manifest',
                 'do_backup|archive',
                 'new_archive',
                 'conf|c=s',
                 'verify=s',
                 'unit_test|unitTest',
                 'build_master_lists',
                 'update_master_lists',
                 'write_master_fileset',
                 'read_master_fileset',
                 'restore_scripts',
                 'no_update',
                 'full',
                 'incremental');

    # Process options.
    process_options($argc, %optmap, @optspec);
    handle_special_global_params();

    #
    # The backup code proper:
    #

    # Retrieve package list.
    my %distro_pkgs = ();
    my %newPkgsSinceDate = ();
    my $gotNewPkgs = 0;
    if ($build_master_list || $build_pkg_list) {
        # New pkglist.
        %distro_pkgs = get_pkglist();
        write_pkgset($_PkgLists_File, %distro_pkgs, $_MyName);
        $gotNewPkgs = 1;
    } else {
        # Update an existing one.
        my $writeDate = read_pkgset($_PkgLists_File, %distro_pkgs);
        if ($update_pkg_list) {
            print "Updating package list: ";
            %newPkgsSinceDate = get_pkglist($writeDate);
            print_hash_ut(%newPkgsSinceDate, "\%newPkgs");
            # If there are any new packages, merge with the existing list and
            # save.
            $gotNewPkgs = scalar(keys(%newPkgsSinceDate));
            if ($gotNewPkgs) {
                while (my ($key, $value) = each(%newPkgsSinceDate)) {
                    $distro_pkgs{$key} = $value;
                }
                write_pkgset($_PkgLists_File, %distro_pkgs, $_MyName);
            }
        }
    }
    print_hash_ut(%distro_pkgs, "\%distro_pkgs");

    my %master_fileset = ();
    my %master_dirset = ();
    my %changed_pkgfiles = ();

    # ACTION:  Master List.
    #
    if ($build_master_list) {
        # Build a new master list, or
        build_master_lists(%master_fileset, %master_dirset);
        # Pruning will happen naturally in the next step.
    } elsif ($update_master_list) {
        # Read in an earlier list and update it (maybe).
        read_master_fileset($_MasterLists_File,
                            %master_fileset, %master_dirset);
        update_master_lists(%master_fileset, %master_dirset,
                            $_MasterLists_File);
    }

    # ACTION: Scan
    #
    # Scan the disk and the package manifest, building a picture of which
    # package member files have changed (and how they've changed) since the
    # package was installed.
    #
    # At the same time, prune package member files from the Master Lists.
    #
    if ($scan_pkgs || $build_master_list) {
        # Here, add back any files that are part of a package, but have
        # changed.  Once a file is on this list, it stays on the list until the
        # next full backup.  However, new files can be added to the list at a
        # later date, a process that still requires the full package check.
        #
        # N.B.:  The two hashes, %master_fileset and %master_dirset, can be
        # empty; "get_changed_since_install()" will work either way.
        %changed_pkgfiles
            = get_changed_since_install(%distro_pkgs,
                                        %master_fileset, %master_dirset,
                                        $_AlwaysIncludeDirs_re,
                                        $_SkipModifiedPkgfiles_re,
                                        $_InstallTime_Delta);

        # Store in config-file format, making each key a variable in the
        # config file.
        write_modified_pkgfiles($_ModifiedPkgFLists_File, %changed_pkgfiles);
    } else {
        # Load in an older version.
        read_modified_pkgfiles($_ModifiedPkgFLists_File, %changed_pkgfiles);
        # Scan any new packages.
        $gotNewPkgs = scalar(keys(%newPkgsSinceDate));
        if ($gotNewPkgs) {
            print "Scanning new packages: ";
            my %newPkgs_changedFiles
                = get_changed_since_install(%newPkgsSinceDate,
                                            %master_fileset, %master_dirset,
                                            $_AlwaysIncludeDirs_re,
                                            $_SkipModifiedPkgfiles_re,
                                            $_InstallTime_Delta);
            print_hash_ut(%newPkgs_changedFiles, "\%newPkgs_changedFiles");
            # Merge anything new with the existing change map.
            my $foundChanges = 0;
            while (my ($key, $ref_fList) = each(%newPkgs_changedFiles)) {
                next unless (scalar(@$ref_fList));
                next if (isChangeTypeAlias($key));
                my %mergeSet = ();
                @mergeSet{ @{$changed_pkgfiles{$key}} } = ();
                @mergeSet{ @$ref_fList } = ();
                $changed_pkgfiles{$key} = [ sort(keys(%mergeSet)) ];
                ++$foundChanges;
            }
            # If we made changes, save.
            if ($foundChanges) {
                write_modified_pkgfiles($_ModifiedPkgFLists_File,
                                        %changed_pkgfiles);
            }
        }
    }

    # ACTION: Perform "Master Lists" Operations
    #
    if ($build_master_list || $update_master_list) {
        print_hash_ut(%master_dirset);
        print_hash_ut(%master_fileset);

        # At this point, we save the files.  Note that we only need to save
        # if we've rebuilt the lists or checked for modified package files.
        if ($scan_pkgs || $build_master_list || $update_master_list) {
            write_master_fileset($_MasterLists_File,
                                 %master_fileset, %master_dirset);
        }
    }#end Master List Ops.


    # ACTION: Archive Manifest
    #
    if ($write_arManifest || $do_backup) {
        if ($_UnitTest || $_Verbose) {
            print "Creating manifest(s) for archiver...";
        }

        my @restoreScripts = ();

        # Create the restoration script for pruning files...
        if ( isSupportedChangeType("Deleted") &&
             scalar(@{$changed_pkgfiles{"Deleted"}}) )
        {
            push(@restoreScripts,
                 make_deletion_rscript(@{$changed_pkgfiles{"Deleted"}})
                 );
        }

        # ...for the file permissions...
        if ( isSupportedChangeType("Permissions") &&
             scalar(@{$changed_pkgfiles{"Permissions"}}) )
        {
            push(@restoreScripts,
                 make_perms_rscript(@{$changed_pkgfiles{"Permissions"}})
                 );
        }

        # ...for the file ownership...
        if ( isSupportedChangeType("Ownership") &&
             scalar(@{$changed_pkgfiles{"Ownership"}}) )
        {
            push(@restoreScripts,
                 make_owner_rscript(@{$changed_pkgfiles{"Ownership"}})
                 );
        }

        # ...and for custom symlinks.
        if ( isSupportedChangeType("Symlink") &&
             scalar(@{$changed_pkgfiles{"Symlink"}}) )
        {
            push(@restoreScripts,
                 make_symlink_rscript(@{$changed_pkgfiles{"Symlink"}})
                 );
        }

        # Save the results.
        # Don't forget the directories whose contents we will always archive.
        write_archive_filelist($_File_ArchiveManifest,
                               @restoreScripts,
                               @_AlwaysIncludeDirs,
                               @{$changed_pkgfiles{"Contents"}},
                               @{$changed_pkgfiles{"Other"}});

        if ($_UnitTest || $_Verbose) {
            print "\tDone.\n";
        }
    }

    # ACTION:  Backup
    #
    if ($do_backup) {
        if ($_UnitTest || $_Verbose) {
            print "Starting backup...\n";
        }

        if ($new_archive) {
            do_full_filelist_backup($_Archive_Destination_Dir,
                                    $_Archive_Prefix,
                                    $_File_ArchiveManifest);
        } else {
            do_incremental_filelist_backup($_Archive_Destination_Dir,
                                           $_Archive_Prefix,
                                           $_File_ArchiveManifest);
        }

        if ($_UnitTest || $_Verbose) {
            print "Backup complete.\n";
        }
    }

    # ACTION:
    # Performs a simple verification of the archive by comparing the archive's
    # list of files to the fileset used to create the backup.
    #
    if ($optmap{'verify'}) {
        my $tarball=$optmap{'verify'};
        verify_listfile_archive($tarball,
                                $_Dir_ArchiveManifest,
                                $_File_ArchiveManifest);
    }
    exit 0;
}

main;
exit 0;


## POD STARTS HERE ##
__END__

=head1 NAME

pkgBackup - A Perl script for selectively backing up an
    RPM-based or DEB-based system.

=head1 SYNOPSIS

=over 1

=item debBackup.pl <options> [cfgfile] ...

=item rpmBackup.pl <options> [cfgfile] ...

=back

=head1 OPTIONS

At least one of the following action options must be present:

=over 4

=item B<--help>

Prints this message.

=item B<--full>

Shortcut:  has the same effect as specifying the options:
C<--build_package_list --scan_pkgfiles --write_archive_manifest --do_backup
--new_archive>

=item B<--incremental>

Shortcut:  has the same effect as specifying the options:
C<--update_package_list --write_archive_manifest --do_backup>

=item B<--build_package_list>

=item B<--build_pkglist>

=item B<--bpkgl>

Builds the list of all installed RPM/DEB packages.  This is a required first
step of any new full backup.

When this option is not specified, a previously saved version of the package
list is loaded.  The program will abort with an error if no such version
exists.

=item B<--update_package_list>

=item B<--update_pkglist>

=item B<--upkgl>

Reads the previously saved version of the package list and the time at which
that list was built.  Adds any packages installed since that time to the list.

=item B<--scan_pkgfiles>

=item B<--check_pkgfiles>

=item B<--scan_rpms>

=item B<--scan_debs>

Scans the RPM/DEB package database for files that are part of an installed
package, but have since changed.  Any files that have changed are
automatically added to the backup list.  When the check finishes, the backup
list is saved.

When this option is not specified, a previously saved version of the backup
list is loaded.  The program will abort with an error if no such version
exists.

Use this option whenever you have installed new RPM/DEB packages between
backups.

Because this option scans the entire filesystem I<and> the entire RPM/DEB
package database, it is very load-intensive and takes some time to complete.

=item B<--write_archive_manifest>

=item B<--make_manifest>

=item B<--write_manifest>

Using the results of an earlier C<--scan_rpms>,  write a manifest of files to
backup.  This manifest is handed to the C<--files-from> option of the
C<archive> action (see below).

One can also specify directories to exclude from and explicitly include in the
manifest.

The C<--do_backup> option and its aliases (see below) imply this option.

=item B<--do_backup>

=item B<--archive>

As the names imply, these options all begin the backup process.

=item B<--verify>=I<archive_name>

Performs a simple verify by comparing the contents of the file I<archive_name>
with the most recent output of the C<--write_archive_manifest> option.  Note
that this does not verify the (GNU-C<tar>, C<cpio>, etc.) archive itself for
errors; it's for verifying the results of this script.

=back

=head1 OTHER OPTIONS

You may also include the following modifier options (they are not required):

=over 4

=item B<--verbose>

Print out extra info while doing the backup.  Also passes the C<--verbose>
option to the archive command called by the C<--do_backup> action.

=item B<-c> I<cfgfile>

=item B<--conf> I<cfgfile>

=item I<cfgfile> (plain commandline arg)

Read certain parameters from the configuration file I<cfgfile>.  The comments
in the out-of-the-box configuration file describe the file syntax and the
options.  If this option isn't specified, a set of sane builtin defaults are
used instead.  (I.e. no configuration file is read.)

Note that you can also specify the name of the configuration file as a plain
commandline argument.

=item B<--no_update>

Disables C<--update_package_list>, including implicit ones.  Use this with the
C<--incremental> option to skip the "Update Package List" phase and restrict
the backup to modified files only.

=item B<--new_archive>

Force C<--do_backup> to do a full backup.  Only affects the C<--do_backup>
option and its aliases.  This is the default behavior if the backup archive
doesn't exist.

Use this with the C<--incremental> option to override its default
(which is to have C<--do_backup> do an incremental backup).

=back

You may also use the following additional action options (they are not
required, but exist for convenience):

=over 4

=item B<--build_master_list>

=item B<--update_master_list>

=back

They are documented in greater detail in the DESCRIPTION section of the full
manpage.

=head1 DESCRIPTION

=head2 Motivation

Most backup systems assume that you will be archiving all (or nearly all) of
the files on your filesystem to some form of tape drive.  This is a reasonable
assumption for corporate environments or large servers, but what about the
"home" Linux user?  Most home/hobby users will not have a high-capacity tape
jukebox, let alone a single-tape 10Gb tape backup drive.  They will usually
have a CD-RW drive.  Faced with daunting task of backing up 3Gb or more to
multiple CDs, these home/hobby users simply ignore the chore of backing up
their system.

And why should these users back up their systems?  Aside from the contents of
"/home" and "/tmp", little else on the filesystem will have changed since they
installed the software from the packages.  To compound the problem, users
migrating from the Winblows world have long since given up all hope of backing
up software configurations.  Consider, too, that reinstalling packages takes
about as much time as restoring a backup from a CD-R.

Nevertheless, these home & hobby users still should do backups.  With current
Linux packaging software, there's no reason why they can't.

This Perl script contains a modular set of tools for backing up files on your
system:

=over 4

=item *

That were not installed from an RPM/DEB package; OR

=item *

Were installed from an RPM/DEB package but have since been modified.

=back

=head2 The Action Options

The aforementioned "modular set of tools" are the action options, described in
the L<"OPTIONS">.  Each action has certain dependencies on others.
Additionally, the script performs the actions in a specific sequence.  The
order in which you specify the action options on the commandline has no
bearing on their execution order.

This is the order in which the action options execute.  Listed with them are
the operations that take place as part of that option, or as an alternative,
if any:

=over 4

=item 1.

Get the list of packages.

=over 4

=item 1a.

C<--build_package_list>

=over 4

=item 1a.(i)

Build the list of packages.

=item 1a.(ii)

Write the package list to a file.

=back

=item 1b.

Read and update the list of packages

=over 4

=item 1b.(i)

Read package list from disk (written there by previous run of this script).

=item 1b.(ii)

C<--update_package_list>

Get a list of all packages installed since the package list was written to the
file just read in.

=back

=back


=item 2.

Get the Master List (see L<"Utility Actions"> for details).

=over 4

=item 2a.

C<--build_master_list>

Build the Master List

=item 2b.

C<--update_package_list>

Read the Master List from disk (written there by previous run of this script).
Then, update the Master List.

=back


=item 3.

Retrieve the set of files installed from a package, and altered since the
package's install date.

=over 4

=item 3a.

C<--scan_rpms>

(Also does this if the C<--build_master_list> option is specified.)

=over 4

=item 3a.(i)

Scan all packages for modified files.  Build a fileset that describes how
each file changed.

=item 3a.(ii)

Write the sets of modified package files to disk.

=back

=item 3b.

Read and update the list of modified package-member-files.

=over 4

=item 3b.(i)

Read the sets of modified package files from disk (written there by previous
run of this script).

=item 3b.(ii)

If C<--update_package_list> found any new packages, scan each of them for
modified member files.

=item 3b.(iii)

If the previous step yielded any new modified package-member-files, merge the
results in with the sets read from disk.  Then, write these new results to
disk.

=back

=back


=item 4.

If either C<--build_master_list> or C<--update_package_list> was used,
save the Master List to a file.

=item 5.

C<--write_archive_manifest>

=over 4

=item 5a.

Create the restore-scripts (which are C</bin/sh> scripts) for files not
requiring full archiving.

=item 5b.

Write a manifest for use by the archiver (i.e. a list of files to backup).
The restore-scripts will be on this manifest.

=back

=item 6.

C<--do_backup>

Call the archiver.  Performs a full backup if C<--new_archive> was specified.
Otherwise, the backup is incremental.

Presently, the archiver is the GNU C<tar> program with C<bzip2> compression.
One can easily use a different archiver by creating a new module and loading
it in place of C<tarBackupUtils.pm>.

=item 7.

C<--verify>

Verifies against the appropriate C<--write_archive_manifest> file, based on
the specified archive name.

=back

Each option depends on the successful completion of the previous one.  Some
have even stronger interdependencies.  Specifically:

=over 4

=item *

C<--build_master_list> requires C<--scan_rpms>

=item *

C<--do_backup> requires C<--write_tarlists>

=back

To make life easier on you, forgetting these requirements doesn't generate an
error.  Instead, specifying an action option also activates any action options
it requires.

=head2 Utility Actions

Some other action options:

=over 4

=item B<--build_master_list>

=item B<--bml>

Builds the "Master List," a list of files that are not part of any installed
RPM/DEB packages This option searches the entire filesystem, starting at "/",
and skips certain filesystem types (such as "proc", "iso9660", "nfs").  When
the search is completed, the Master List is saved to a file.

This option implies the C<--scan_rpms> option.  (I.e. it acts as if you
also specified C<--scan_rpms>, whether you did or not.)

When this option is not specified, a previously saved version of the Master
List is loaded.  The program will abort with an error if no such version
exists.

Because this option scans the entire filesystem I<and> the entire RPM/DEB
package database, it is very load-intensive and takes some time to complete.

=item B<--update_master_list>

=item B<--uml>

Updates the "Master List" by searching for files created or modified since the
last time the Master List changed.  This option also begins searching at "/"
and skips the same filesystem types skipped by C<--build_master_list>.  After
the update, the Master List is saved to a file.

=back

This option does nothing when C<--build_master_list> (or one of its aliases) is
specified.

=cut

#################
#
#  End
