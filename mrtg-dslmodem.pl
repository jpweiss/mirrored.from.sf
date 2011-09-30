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
# Configurable Variables
#
############


# Configurable Internals - They can also be changed from the configuration
# file, but are not standard settings.  These are their default values.
#

my $_DaemonLog = "/tmp/mrtg-dslmodem.log";
my $_DataFile = "/dev/shm/mrtg-dslmodem.dat";
my $_MaxSize_DataFile = 8*1024*1024;
my $_MaxSize_Log = 64*1024*1024;
my $_DaemonPIDFile = "/var/run/mrtg-dslmodem.pid";
my $_GetURLVia = 'curl';
my $_DebugLoggingIsActive = 0;
my $_DropCountInterval = 3600;


# Internal Variables.
#
# They're meant to be tuned for local conditions, but not designed to be set
# from a configuration file.
#

my $_ConfigFile = undef();
my $_UpdateInterval_Default = 5*60;
my $_TieAttempts = 5;
my $_TieWait = 1;
my $_PostDaemonizeWait = 5;
my @_GPG2_Binaries = ('/bin/gpg2', '/usr/bin/gpg2', '/usr/local/bin/gpg2');


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


#=============================================================================
#
# Begin:  Inlined Crypt::CipherSaber package.
#
# All code below, up until the "End" header, is based on code Copyright (C)
# 2001 - 2002 by chromatic <chromatic@wgz.org>; all rights reserved.  The
# original Crypt::CipherSaber library was released under the same license as
# Perl itself.
#
# The inlined version of Crypt::CipherSaber has been modified to crunch it
# into less space and eliminate features not used by this program.
#
############
package Crypt::CipherSaber;

use strict; use Carp; use vars qw($VERSION); $VERSION = '0.61';
sub new {
    my $class = shift; my $key = shift; my $N = shift;
    if (!(defined $N) or ($N < 1)) { $N = 1; }
    my $self = [ $key, [ 0 .. 255 ], $N ];
    bless($self, $class);
}
sub crypt {
    my $self = shift; my $iv = shift;
    my @key = map { ord } split(//, ($self->[0] . $iv));
    my $state = $self->[1]; my $j = 0; my $length = @key;
    for (1 .. $self->[2]) {
        for my $i (0 .. 255) {
            $j += ($state->[$i] + ($key[$i % $length]));
            $j %= 256; (@$state[$i, $j]) = (@$state[$j, $i]);
        }
    }
    my $message = shift; my $output; my ($i, $n); $state = $self->[1]; $j=0;
    for (0 .. (length($message) - 1 )) {
        $i++; $i %= 256; $j += $state->[$i]; $j %= 256;
        @$state[$i, $j] = @$state[$j, $i];
        $n = $state->[$i] + $state->[$j]; $n %= 256;
        $output .= chr( $state->[$n] ^ ord(substr($message, $_, 1)) );
    }
    $self->[1] = [ 0 .. 255 ];
    return $output;
}
sub encrypt {
    my $self = shift;
    my $iv; for (1 .. 10) { $iv .= chr(int(rand(256))); }
    return $iv . $self->crypt($iv, @_);
}
sub decrypt {
    my $self = shift; my ($iv, $message) = unpack("a10a*", +shift);
    return $self->crypt($iv, $message);
}

############
#
# End:  Inlined Crypt::CipherSaber
#
#=============================================================================
package main;


############
#
# Includes/Packages
#
############

require 5;
use strict;
use bytes;           # Overrides Unicode support
use Date::Parse;
use Term::ReadKey;
use Tie::File;
use Fcntl qw(O_RDONLY O_RDWR O_APPEND O_CREAT);  # For use with 'tie'
use POSIX qw(nice setsid strftime);

# Used to extract statistics from the DSL Modem.
# It will be loaded (using "require") at runtime if needed.
#use HTML::TableExtract;

# For Debugging:
use Data::Dumper;


############
#
# Other Global Variables
#
############


my $c_tsIdx = 0;
my $c_HRT_Idx = 1;
my $c_UpDownIdx = 2;
my $c_nDropsIdx = 3;

my $c_Week_Secs = 7*24*3600;

my $c_dbgTsHdr = '{;[;DebugTimestamp;];}';
my $c_myTimeFmt = '%Y/%m/%d_%T';

my $c_EndTag_re = '</[^>\s\n]+>';
my $c_Ignored_StandaloneTag_re
    = '(?:B(?:ASE(?:FONT)?|R)|COL|FRAME|HR|LINK|META)\s*/?';
my $c__Ignored1_re='[AB]|D(?:EL|IV)|EM|FO(?:RM|NT)|HTML|I(?:MG|NPUT)?|';
my $c__Ignored2_re='NOBR(?:EAK)?|S(?:PAN|TR(?:IKE|ONG)|U[BP])|TT|U';
my $c_Ignored_Tags_re
    = '/?(?:'.$c__Ignored1_re.'|'.$c__Ignored2_re.')';
my $c_TableNonCellTags='T(?:ABLE|BODY|FOOT|HEAD|R)';

# Used to warn the user when they need to rerun this script in '-p'-mode.
my $c_VerifyShhhh='9a892c8b9c83496e52591e133cc36112ac3db12d0bdee6273ea961'.
    '0fb12048bded4bfdfd4384d3fee3c57f02c07055d876ca58da0b538a889d113baefb'.
    '8161e3e64068f914bdfd5e';
my $c_ExpectedShhhh='sub shhhhh($$); my $c_ExpectedShhhh="@th350und0fth3"';
# FIXME:  Change to this at some point:
#my $c_ExpectedShhhh='sub shhhhh($$){ my $c_ExpectedShhhh="@th350und0fth3"';
my $c_VersionShhhh="# 1.0 #";


# Constants used in the time-format hashes.  Prevents inconsistencies due to
# typos.
my $c__common_tRe_mmddyyyy12
    = '(\d\d.\d\d.\d\d\d\d\s+\d\d:\d\d:\d\d\s+[AP]M)';
my $c__common_tRe_ddmmyyyy = '(\d\d.\d\d.\d\d\d\d\s+\d\d:\d\d:\d\d)';
my $c__common_tRe_yyyymmdd = '(\d\d\d\d.\d\d.\d\d\s+\d\d:\d\d:\d\d)';
my $c__common_tRe_yyyymmdd12
     = '(\d\d\d\d.\d\d.\d\d\s+\d\d:\d\d:\d\d\s+[AP]M)';

my $c__common_tFmt_USslash12 = '%m/%d/%Y %r';
my $c__common_tFmt_USdash12 = '%m-%d-%Y %r';
my $c__common_tFmt_F_r = '%F %r';
my $c__common_tFmt_slash_r = '%Y/%m/%d %r';


#
# "Constant" Arrays & Hashes
#

my @c_Hex = ('0', '1', '2', '3', '4', '5', '6', '7',
             '8', '9', 'a', 'b', 'c', 'd', 'e', 'f');

my %c_WebGet = ( 'curl' => { 'cmd' => "/usr/bin/curl",
                             'args' => " -4 -s -m 300 ",
                             'user_arg' => " -u ",
                             'passwd_arg' => ":"
                           },
                 'wget' => { 'cmd' => "/usr/bin/wget",
                             'args' => " -4 -q --connect-timeout 120 -O - ",
                             'user_arg' => " -user ",
                             'passwd_arg' => " -passwd "
                           }
               );

my %c_TimeRegexps = ( 'yyyy-mm-dd HH:MM:SS' => $c__common_tRe_yyyymmdd,
                      'yyyy/mm/dd HH:MM:SS' => $c__common_tRe_yyyymmdd,
                      'yyyy-mm-dd HH:MM:SS AM' => $c__common_tRe_yyyymmdd12,
                      'yyyy-mm-dd HH:MM:SS PM' => $c__common_tRe_yyyymmdd12,
                      'yyyy/mm/dd HH:MM:SS AM' => $c__common_tRe_yyyymmdd12,
                      'yyyy/mm/dd HH:MM:SS PM' => $c__common_tRe_yyyymmdd12,
                      'mm/dd/yyyy HH:MM:SS AM' => $c__common_tRe_mmddyyyy12,
                      'mm/dd/yyyy HH:MM:SS PM' => $c__common_tRe_mmddyyyy12,
                      'mm-dd-yyyy HH:MM:SS AM' => $c__common_tRe_mmddyyyy12,
                      'mm-dd-yyyy HH:MM:SS PM' => $c__common_tRe_mmddyyyy12,
                      'dd/mm/yyyy HH:MM:SS' => $c__common_tRe_ddmmyyyy,
                      'dd-mm-yyyy HH:MM:SS' => $c__common_tRe_ddmmyyyy,
                      'dd.mm.yyyy HH:MM:SS' => $c__common_tRe_ddmmyyyy,
                    );

my %c_TimeFormatStr = ( 'yyyy-mm-dd HH:MM:SS' => '%F %T',
                        'yyyy/mm/dd HH:MM:SS' => '%Y/%m/%d %T',
                        'yyyy-mm-dd HH:MM:SS AM' => $c__common_tFmt_F_r,
                        'yyyy-mm-dd HH:MM:SS PM' => $c__common_tFmt_F_r,
                        'yyyy/mm/dd HH:MM:SS AM' => $c__common_tFmt_slash_r,
                        'yyyy/mm/dd HH:MM:SS PM' => $c__common_tFmt_slash_r,
                        'mm/dd/yyyy HH:MM:SS AM' => $c__common_tFmt_USslash12,
                        'mm/dd/yyyy HH:MM:SS PM' => $c__common_tFmt_USslash12,
                        'mm-dd-yyyy HH:MM:SS AM' => $c__common_tFmt_USdash12,
                        'mm-dd-yyyy HH:MM:SS PM' => $c__common_tFmt_USdash12,
                        'dd/mm/yyyy HH:MM:SS' => '%d/%m/%Y %T',
                        'dd-mm-yyyy HH:MM:SS' => '%d-%m-%Y %T',
                        'dd.mm.yyyy HH:MM:SS' => '%d.%m.%Y %T',
                      );

#
# Globals
# (These must be global because they're used by the sighandlers.)
#

my @g_Measurements;
my $g_refDataTieObj;


############
#
# Functions
#
############


# Forward decls.
sub updateMRTGdata(\@$$);


#----------
# Utilities
#----------


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


sub printErr(@) {
    my $first = shift();
    if ($first eq $c_dbgTsHdr) {
        print STDERR ("#DBG# [",
                      strftime($c_myTimeFmt, localtime()), "]  ", @_);
    } elsif (($first =~ m/^\n+$/) && !scalar(@_)) {
        print STDERR ($first);
    } else {
        print STDERR (strftime($c_myTimeFmt, localtime()), " --  ", @_);
    }
}


sub printDbg(@) {
    return 1 unless ($_DebugLoggingIsActive);
    printErr($c_dbgTsHdr, @_);
}


sub convert2secs(\$) {
    my $ref_var = shift();

    my $timeStr = $$ref_var;
    my $secs = undef;

    # Process any units-suffix:
    if ($timeStr =~ m/^(.*)\s*s$/) {
        # Units of seconds.  Nothing to do to the number.
        $secs = $1;
    }
    elsif ($timeStr =~ m/^(.*)\s*([mh])$/) {
        $secs = $1;
        if ($2 eq "h") {
            $secs *= 60;
        }
    } else {
        # Don't modify $$ref_var.
        return undef;
    }

    # Convert min. to sec.
    $secs *= 60;

    $$ref_var = $secs;
    return $secs;
}


sub convert2bytes(\$) {
    my $ref_var = shift();

    my $valStr = $$ref_var;
    my $bytes = undef;

    # Process any units-suffix:
    if ($valStr =~ m/^(\d+)\s*([BbKkMm])$/) {
        $bytes = $1;
        my $unit = lc($2);
        if ($unit eq "m") {
            $bytes *= 1024;
        }
        if ($unit ne "b") {
            # ==> units are either 'k' or 'm'.
            $bytes *= 1024;
        }
        $$ref_var = $bytes;
        return $bytes;
    } #else

    # Don't modify $$ref_var.
    return undef;
}


sub t2DropCountInterval($;$) {
    my $t = shift();
    my $returnIntervalEnd = (scalar(@_) ? shift() : 0);

    my $timeUptdInterval = $t - ($t % $_DropCountInterval);
    if ($returnIntervalEnd) {
        $timeUptdInterval += $_DropCountInterval;
    }
    return $timeUptdInterval;
}


sub init_DST_vars(\$\$) {
    my $ref_inDST = shift();
    my $ref_currentWeek_endTs = shift();

    my @timeParts = localtime();

    # The week counter will start on Sunday, 4:00:00am.  This way, it will
    # reset each week at about this time, letting us capture DST changes
    # (almost) immediately.
    my $thisWeek_start = time();
    $thisWeek_start -= $thisWeek_start % 3600;
    my $hr = $timeParts[2];
    if ($hr != 4) {
        $thisWeek_start -= ($hr - 4)*3600;
    }
    my $dayNumber = $timeParts[6];
    if ($dayNumber) {
        $thisWeek_start -= $dayNumber*24*3600;
    }

    $$ref_currentWeek_endTs = $thisWeek_start + $c_Week_Secs;

    # Now check and see if we're in DST.
    $$ref_inDST = $timeParts[8];
}


#----------
# Configfile Processing
#----------


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


sub read_config(\%) {
    my $ref_options = shift();

    build_cfgfile_name();

    %$ref_options = ();
    my $array_option = "";

    open(IN_FH, "$_ConfigFile")
        or die("Unable to open file for reading: \"$_ConfigFile\"\n".
               "Reason: \"$!\"\n");

    while (<IN_FH>) {
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
    close IN_FH;

    #print STDERR ("#DBG# ", Dumper($ref_options), "\n");
}


sub read_fromGPG($\%) {
    my $gpgFile = shift();
    my $ref_auth = shift();

    # Must be able to read this files.
    return 0 unless (-r $gpgFile);

    # Search for the GPG-2 binary, and prefer it if found.
    my $gpgCmd = 'gpg';
    foreach my $binfile (@_GPG2_Binaries) {
        if (-x $binfile) {
            $gpgCmd = $binfile;
            last;
        }
    }
    $gpgCmd .= " --batch -d ";
    $gpgCmd .= $gpgFile;

    open(C_FH, '-|', $gpgCmd)
        or die("Unable to read \"" . $gpgFile . "\".\n" . "Reason:\"$!\"\n");
    my @lines = <C_FH>;
    close(C_FH) or die("Unable to process \"" . $gpgFile . "\".\n" .
                       "Reason:\"$!\"\n");

    my %nuOpts = ();
    foreach (@lines) {
        chomp; study;
        next if (m/^\s*$/); next if (m/^\#/);
        next unless m/^\s*(\S+)\s*[:=]\s*(.*)\s*$/;
        my $o = $1; my $v = $2;
        if ($v =~ m/^['"](.*)['"]/) { $v = $1; }
        $nuOpts{$o} = $v;
    }

    foreach my $o ('userid', 'passwd') {
        next unless (exists($nuOpts{$o}));
        next unless ($nuOpts{$o});
        $ref_auth->{$o} = $nuOpts{$o};
    }

    return 1;
}


sub readSilent($) {
    my $msg = shift();

    print $msg, "> ";
    ReadMode('cbreak');
    my $val1='';
    my $c = ReadKey(0);
    while ($c ne "\n") {
        print "*";
        $val1 .= $c;
        $c = ReadKey(0);
    }
    print "\n";

    print "Verify:  re-enter what you just typed> ";
    my $val2='';
    $c = ReadKey(0);
    while ($c ne "\n") {
        print "*";
        $val2 .= $c;
        $c = ReadKey(0);
    }
    print "\n";

    ReadMode('normal');

    if ($val1 eq $val2) {
        return $val1;
    } #else:  Error
    print "Typo:  Values do not match.\n";
    return undef;
}


sub my_codeval() {
    open(IN_FH, '<', $0) or die("Unable to open file for reading.\n".
                                "Reason: \"$!\"\n");
    my @octets = ();
    my $nc = 0;
    my $iVal = 0;
    my $hVal = 0;
    while (my $line=<IN_FH>) {
        next if ($line =~ m/^#\s+\$Id:.+\s+\$/);
        foreach (split(//, $line)) {
            if (($nc % 4) == 0) { $hVal ^= $iVal; $iVal = ord; }
            else { $iVal <<= 8; $iVal |= ord; }
            # Increment now so that the first iteration isn't caught by the
            # use of the '%' operator below.
            ++$nc;
            if (($nc % 0x10) == 0) { $hVal %= 0x2AAAAAAB; }
            if (($nc % 0xAAB) == 0) {
                while ($hVal) {
                    push(@octets, chr($hVal & 0xFF)); $hVal >>= 8;
                }
                $hVal = ( ($#octets > 73) ? shift(@octets) : 0);
            }
        }
    }
    close(IN_FH);

    # FIXME:  Remove once this script has stabilized.
    #print (join('', map({ my $v=ord;
    #                      if (($v < 0x20) || ((0x7E < $v) && ($v < 0xA0)))
    #                      { $v += 0x40; '^'.chr($v); } else { $_; }
    #                    } @octets)), "\n");
    @octets = ('n<Õ¾L^ßé^Æ^¿ÿ^X^Í-ê^O^Þ)Ë§ö1 ^Û^ZY¶Þµ%',
               'i=p1Ùzµ^X^\êåkÌYf>^Þº~/§(h7÷^Ô^Î^S^^IÖ^R^Q½^@-^@^H^J^Mç',
               'Î¾2^PóV^ZÖÿØ^R');

    return join('', @octets);
}


sub shhhhh($$$) {
    my $thing = shift();
    my $prghsh = shift();
    my $fwd = shift();

    return undef unless ($thing);

    my $cs = Crypt::CipherSaber->new($prghsh);
    my $retval = "";
    if ($fwd) {
        $thing .= '|;|'; $thing .= $c_VersionShhhh;
        foreach my $octet (map(ord, split(//, $cs->encrypt($thing)))) {
            $retval .= $c_Hex[((0xF0 & $octet) >> 4)];
            $retval .= $c_Hex[(0x0F & $octet)];
        }
    } else {
        die("Invalid input passed for decryption:\n\t\"".$thing."\"\n")
            unless ( ((length($thing) % 2) == 0) &&
                     ($thing =~ m/^[0-9a-fA-F]+$/) );
        my @nibbles = map( { (($_ < 10) ? $_ : ($_ - 0x27) ) }
                           map( { (ord() & 0xFF) - 0x30 }
                                split(//, lc($thing)) ) );
        my $octets = '';
        do {
            $octets .= chr( (shift(@nibbles) << 4) | shift(@nibbles) );
        } while (scalar(@nibbles));
        my @parts = split(/\|;\|/, $cs->decrypt($octets));
        $retval = ($parts[1] eq $c_VersionShhhh ? $parts[0] : undef);
    }
    return $retval;
}


sub set_or_warn(\$$$$@) {
    my $ref_var = shift();
    my $newVal = shift();
    my $what = shift();
    my $why = shift();

    if (defined($newVal) && $newVal) {
        $$ref_var = $newVal;
        return;
    } # else:  Error

    print STDERR("Error:  ", $why, " in setting:  \"", $what, "\"\n", @_);
}


sub validate_auth_only(\%\%) {
    my $ref_options = shift();
    my $ref_auth = shift();

    return 1 unless (exists($ref_options->{"passwd"}));

    if (exists($ref_options->{"GPG_SettingsFile"})) {
        return read_fromGPG($ref_options->{"GPG_SettingsFile"}, %$ref_auth);
    }

    my $perms = (stat($_ConfigFile))[2] & 07077;
    die("\nFATAL ERROR:\n\n".
        "Incorrect file permissions on configuration file:\n\t\"".
        $_ConfigFile."\"\n".
        "It should have no 'group' or 'other' permissions and not special ".
        "flags set.\n\n".
        "Cowardly refusing to continue with an insecure configuration file.".
        "\n\n"
       ) unless ($perms == 0);

    my $prghsh = my_codeval();
    my $test = shhhhh($c_VerifyShhhh, $prghsh, 0);
    die ("\nFATAL ERROR:\n\n".
         "Someone or something has changed this script!  All authentication".
         "\n".
         "information created with the \"-p\" option is now invalid and will".
         "\n".
         "no longer be used.\n\n".
         "You should change the authentication information on your DSL modem".
         "\n".
         "and delete this copy of \"".$_MyName."\".  (Replace it".
         "\n".
         "with a known valid copy from a reliable site.)".
         "\n\n".
         "Cannot continue.".
         "\n\n"
        ) unless ($test eq $c_ExpectedShhhh);

    $ref_auth->{"userid"} = $ref_options->{"userid"};
    $ref_auth->{"passwd"} = shhhhh($ref_options->{"passwd"}, $prghsh, 0);
    unless (defined($ref_auth->{"passwd"})) {
        print STDERR ("\nFatal Error:\n\n",
                      "This script has been upgraded, invalidating all ",
                      "authentication information\n",
                      "in your configuration file.\n",
                      "You must rerun:\n\t\"", $_MyName, " -p\"\n",
                      "to update your configuration file.\n\n",
                      "Cannot continue.", "\n\n");
        exit 3;
    }
}


sub validate_options(\%\%) {
    my $ref_options = shift();
    my $ref_auth = shift();

    validate_auth_only(%$ref_options, %$ref_auth);

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


sub processConfigFile(\%) {
    my $ref_options = shift();

    read_config(%$ref_options);

    #
    # Process/Compute Options Not Requiring Validation
    #

    # 'UpdateInterval' and '_UpdateInterval_sec_'
    #
    if (exists($ref_options->{"UpdateInterval"})) {
        my $rawUI = $ref_options->{"UpdateInterval"};
        convert2secs($rawUI);
        set_or_warn($ref_options->{"_UpdateInterval_sec_"}, $rawUI,
                    "UpdateInterval",
                    "Invalid time value",
                    "It must be a time value with the one of the optional ",
                    "unit markers\n'h', 'm' or 's'.  The default units are ",
                    "minutes.");
    } else {
        $ref_options->{"_UpdateInterval_sec_"} = $_UpdateInterval_Default;
    }

    # 'TimeFormat' and '_Time_Regexp_'
    #
    unless (exists($c_TimeRegexps{$ref_options->{"TimeFormat"}})) {
        print STDERR ("ERROR:  Bad value:  \"",
                      $ref_options->{"TimeFormat"}, "\"\n",
                      "Parameter 'TimeFormat' must be set to ",
                      "one of the following:\n",
                      "\t\"", join("\"\n\t\"", keys(%c_TimeRegexps)),
                      "\"\n\n",
                      "Cowardly refusing to continue.\n");
        exit 2;
    }
    $ref_options->{"_Time_Regexp_"}
        = $c_TimeRegexps{$ref_options->{"TimeFormat"}};
    $ref_options->{"_strftime_Format_"}
        = $c_TimeFormatStr{$ref_options->{"TimeFormat"}};

    #
    # Set some sane defaults:
    #

    unless (exists($ref_options->{'ModemAdjustsForDST'})) {
        $ref_options->{'ModemAdjustsForDST'} = 1;
    }

    unless (exists($ref_options->{'ExtraTimeOffset'})) {
        $ref_options->{'ExtraTimeOffset'} = 0;
    }

    #
    # Advanced Config Options:
    #

    if (exists($ref_options->{"_DebugLoggingIsActive"})) {
        $_DebugLoggingIsActive = $ref_options->{"_DebugLoggingIsActive"};
        if ($_DebugLoggingIsActive =~ m/(?:y(?:es)?|t(?:rue)?)/i) {
            $_DebugLoggingIsActive = 1;
        } elsif ($_DebugLoggingIsActive =~ m/(?:n(?:o)?|f(?:alse)?)/i) {
            $_DebugLoggingIsActive = 0;
        }
    }
    if (exists($ref_options->{"_DaemonLog"})) {
        $_DaemonLog = $ref_options->{"_DaemonLog"};
    }
    if (exists($ref_options->{"_DataFile"})) {
        $_DataFile = $ref_options->{"_DataFile"};
    }
    if (exists($ref_options->{"_DaemonPIDFile"})) {
        $_DaemonPIDFile = $ref_options->{"_DaemonPIDFile"};
    }
    if (exists($ref_options->{"_MaxSize_DataFile"})) {
        convert2bytes($ref_options->{"_MaxSize_DataFile"});
        set_or_warn($_MaxSize_DataFile, $ref_options->{"_MaxSize_DataFile"},
                    "_MaxSize_DataFile",
                    "Invalid size value",
                    "It must be a size with the one of the required ",
                    "unit-suffixes \"B\", \"K\",\n",
                    " or \"M\".  (There are no units for gigabytes.)");
    }
    if (exists($ref_options->{"_MaxSize_Log"})) {
        convert2bytes($ref_options->{"_MaxSize_Log"});
        set_or_warn($_MaxSize_Log, $ref_options->{"_MaxSize_Log"},
                    "_MaxSize_Log",
                    "Invalid size value",
                    "It must be a size with the one of the required ",
                    "unit-suffixes \"B\", \"K\",\n",
                    " or \"M\".  (There are no units for gigabytes.)");
    }
    if (exists($ref_options->{"_GetURLVia"})) {
        $_GetURLVia = $ref_options->{"_GetURLVia"};
        unless (exists($c_WebGet{$_GetURLVia})) {
            print STDERR ("ERROR:  Parameter '_GetURLVia' must be set to ",
                          "one of the following:\n",
                          "\t", join("\n\t", keys(%c_WebGet)),
                          "\n\n",
                          "Cowardly refusing to continue.\n");
            exit 2;
        }
    }

    return 1;
}


sub reprocessConfigFile(\%\%) {
    my $ref_options = shift();
    my $ref_auth = shift();

    print STDERR ("Rereading config file:  ", $_ConfigFile, "\n");

    processConfigFile(%$ref_options);
    validate_options(%$ref_options, %$ref_auth);

    print STDERR ("    Finished rereading configuration.\n");
    print STDERR ("    New values:\n");
    foreach my $k (sort(keys(%$ref_options))) {
        print STDERR ("\t", $k, " = ");
        if (ref($ref_options->{$k})) {
            print STDERR ("(\n\t\t",
                          join("\n\t\t", @{$ref_options->{$k}}),
                          "\n\t)\n");
        }
        else {
            print STDERR ("\"", $ref_options->{$k}, "\"\n");
        }
    }
}


sub appendSecret2ConfigFile() {
    build_cfgfile_name();

    my $val = shhhhh(readSilent("Enter the DSL Modem's ".
                                "status-access password"), my_codeval(), 1);

    unless ($val) {
        print STDERR ("Unable to continue.\n\n");
        exit 1;
    }

    open(OUT_FH, ">>$_ConfigFile")
        or die("Unable to open file for writing: \"$_ConfigFile\"\n".
               "Reason: \"$!\"\n");
    print OUT_FH ("passwd = ", $val, "\n");
    close(OUT_FH);
    chmod(0600, $_ConfigFile);

    print("Secret appended to configuration file:\n\t\"", $_ConfigFile,
          "\"\n",
          "Be sure to edit this file to clean it up to your liking.\n\n");
    exit 0;
}


#----------
# Parsing & Processing the Syslog from the DSL Modem
#----------


sub parse_syslog($$\%$$$\@) {
    my $how = shift();
    my $url = shift();
    my $ref_auth = shift();
    my $dslUp_re = shift();
    my $dslDown_re = shift();
    my $time_re = shift();
    my $ref_dslState = shift();

    # Build the command string separately from the authorization credentials.
    my $auth = "";
    if ( exists($ref_auth->{'userid'}) && exists($ref_auth->{'passwd'}) &&
         ($ref_auth->{'userid'} ne "") && ($ref_auth->{'passwd'} ne "") )
    {
        $auth = $c_WebGet{$how}{'user_arg'};
        $auth .= $ref_auth->{'userid'};
        $auth .= $c_WebGet{$how}{'passwd_arg'};
        $auth .= $ref_auth->{'passwd'};
        $auth .= " ";
    }

    my $getUrl_cmd = $c_WebGet{$how}{'cmd'};
    $getUrl_cmd .= $c_WebGet{$how}{'args'};
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
        # Skip empty lines.
        next if (m/^\s*$/);

        # The '$time_re' expression contains parens.
        next unless (m/$time_re/o);

        my $timestamp = $1;
        my $time_sec = str2time($timestamp);
        # Skip if the time stamp wasn't parsed correctly.
        next unless($time_sec);

        my $timeUptdInterval = t2DropCountInterval($time_sec);

        # Some DSL modems have their clocks set to Epoch on boot.  Ignore
        # those log entries, i.e. any within the first year of Epoch.
        next if ($time_sec <= 31556736);

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
    @$ref_dslState = sort({ $a->[$c_tsIdx] <=> $b->[$c_tsIdx] } @parsedData);
}


sub adjustBorkedTimestamps(\@$$$$) {
    my $ref_events = shift();
    my $isCurrentlyDST = shift();
    my $tsIsDSTCorrect = shift();
    my $additionalTSCorrection = shift();
    my $strftimeFmt = shift();

    return unless (!$tsIsDSTCorrect || $additionalTSCorrection);

    my $xtraTime = $additionalTSCorrection;

    if (!$tsIsDSTCorrect && $isCurrentlyDST) {
        # Adjust time forward one hour.
        $xtraTime += 3600;
        # (Sorry, Lord Howe Island, but you're the weird minority compared to
        # the rest of the world.)
    }

    return unless ($xtraTime);

    # Fix both timestamps:
    foreach my $ref_event (@$ref_events) {
        $ref_event->[$c_tsIdx] += $xtraTime;
        $ref_event->[$c_HRT_Idx]
            = strftime($strftimeFmt, localtime($ref_event->[$c_tsIdx]));
    }
}


sub removeOldEventsAndAdjust(\@$$) {
    my $ref_events = shift();
    my $t_lastEvent = shift();
    my $nDropped_last = shift();

    # No events?  Do nothing.
    return 1 unless (scalar(@$ref_events));

    # 'parse_syslog()' may have been called in the middle of the
    # '$_DropCountInterval'.  If the first new event is still in that
    # interval, we need to start the drop count with whatever it was at the
    # end of the last call to 'parse_syslog()'.
    my $lastEvent_UptdInterval_end = t2DropCountInterval($t_lastEvent, 1);

    my @idxKeep = ();
    foreach my $idx (0 .. $#$ref_events) {
        my $t_event = $ref_events->[$idx][$c_tsIdx];
        # Event already seen; ignore.
        next if ($t_event <= $t_lastEvent);
        push(@idxKeep, $idx);
        if ($t_event < $lastEvent_UptdInterval_end) {
            # This event is in the '$_DropCountInterval' from last time.
            # Update the event with the correct offset.
            $ref_events->[$idx][$c_nDropsIdx] += $nDropped_last;
        }
    }

    # Last, prune the duplicates.  Note that we can't use 'delete' since it
    # doesn't remove elements from the middle of an array (it only sets them
    # to 'undef').
    if (!scalar(@idxKeep)) {
        # ==> They're all duplicates.
        @$ref_events = ();
    } elsif (scalar(@idxKeep) != scalar(@$ref_events)) {
        @$ref_events = @$ref_events[@idxKeep];
    }
    # else:  (scalar(@idxKeep) == scalar(@$ref_events)), so there's nothing to
    # remove.
}


sub resetStaleDropCounts(\@$\@$) {
    my $ref_newEvents = shift();
    my $currentTime = shift();
    my $ref_lastEventSeen = shift();
    my $strftimeFmt = shift();

    # If there are no new events, then the connection state hasn't changed.
    # If the connection is up, then the drop count's probably stale.  So, this
    # routine still has work to do even if @$ref_newEvents is empty.

    # Use the most recent event, whether that's a new event, or the last event
    # seen.
    my @event = @$ref_lastEventSeen;
    if (scalar(@$ref_newEvents)) {
        @event = $ref_newEvents->[$#$ref_newEvents];
    }

    my $ts_latestEvent = $event[$c_tsIdx];
    my $ts_nextDropCountInterval = t2DropCountInterval($ts_latestEvent, 1);
    my $resetTime = $ts_nextDropCountInterval + int(0.02*$_DropCountInterval);

    # Do nothing unless the current time is last event is older than the last
    # event's '$_DropCountInterval'.
    return if ($currentTime < $resetTime);

    # If the connection is still down, do nothing.  If the connection is up,
    # but the drop-count is already 0, do nothing.
    return if ( ($event[$c_UpDownIdx] == 0) ||
                ($event[$c_nDropsIdx] == 0) );

    printDbg("\t    Adding drop-count-reset event.\n");

    # At this point, we know that nothing's happened since '$ts_latestEvent',
    # so make the reset-event occur at the reset time.
    $event[$c_tsIdx] = $resetTime;
    $event[$c_HRT_Idx] = strftime($strftimeFmt, localtime($event[$c_tsIdx]));
    $event[$c_nDropsIdx] = 0;
    push(@$ref_newEvents, \@event);
}


#----------
# Parsing & Processing DSL Modem's Line Statistics Page
#----------


sub read_and_clean_webpage($$\%\@) {
    my $how = shift();
    my $url = shift();
    my $ref_auth = shift();
    my $ref_cleanedLines = shift();


    # Build the command string separately from the authorization credentials.
    my $auth = "";
    if ( exists($ref_auth->{'userid'}) && exists($ref_auth->{'passwd'}) &&
         ($ref_auth->{'userid'} ne "") && ($ref_auth->{'passwd'} ne "") )
    {
        $auth = $c_WebGet{$how}{'user_arg'};
        $auth .= $ref_auth->{'userid'};
        $auth .= $c_WebGet{$how}{'passwd_arg'};
        $auth .= $ref_auth->{'passwd'};
        $auth .= " ";
    }

    my $getUrl_cmd = $c_WebGet{$how}{'cmd'};
    $getUrl_cmd .= $c_WebGet{$how}{'args'};
    my $http_fh;
    unless (open($http_fh, '-|', $getUrl_cmd . $auth . $url)) {
        print STDERR ("FATAL: Can't run command: ", $getUrl_cmd, $url,
                      "\nReason: \"", $!, "\"\n");
        return 0;
    }

    # Read in lines, splitting lines at end tags.
    #
    # The goal is to remove unnecessary tags & whitespace and break up
    # super-long lines of HTML into something a tad more manageable.
    while (<$http_fh>) {
        chomp;
        study;
        # Trim crap off of the ends.
        s¦\r$¦¦; s¦^\s+¦¦; s¦\s+$¦¦;

        # Remove inlined comments
        s¦<!--(?:[^-\n]|-[^-\n])+-->¦¦g;

        # Remove intra-tag spaces, which will make the subsequent regexps
        # simpler.
        s¦/\s+>¦/>¦g;
        s¦\s+/?>¦$1>¦g;
        s¦(</?)\s+¦$1¦g;

        # Remove all of the attributes from the tags.  We don't need them.
        # Because of maximal munch, we need to make sure that we don't
        # accidentally include nested tags.
        s¦<(\w\S*)\s+[^<>\n]+>¦<$1>¦g;

        # Some of these DSL modems put a line-break into the labels.  We not
        # only don't need that, it's a problem when scanning for the stats
        # that we want.  So, convert the <br/> tags into a ' '.
        s¦<(?:BR/?|P)>¦ ¦gi;

        # The paragraph-end tags should be removed.
        s¦</P>¦¦gi;

        # Remove tags that we don't care about, *and* that we can remove from
        # anyplace in the file w/o causing problems.
        s¦<(?:$c_Ignored_StandaloneTag_re|$c_Ignored_Tags_re)>¦¦goi;

        # Remove any inter-tag spaces.  We don't need it.
        s¦>\s+<¦><¦g;

        # Convert "nonbreaking space" entities to the actual spaces.  BUT only
        # AFTER removing inter-tag spaces.  (This way, we preserve the
        # non-breaking spaces in the original document.)
        s¦&nbsp;¦ ¦g;

        # NOW that we've pruned out all manner of stuff, we can check for and
        # skip empty lines.
        #
        next if (m/^\s*$/);

        if (m¦$c_EndTag_re.¦o) {
            # If we match an end tag, followed by any character, then we have
            # a line that needs to be split into smaller lines.
            s¦($c_EndTag_re)¦$1\n¦go;

            # Clean any crap off of the ends of the new lines we've created.
            my @subLines = map({ s¦\r$¦¦; s¦^\s+¦¦; s¦\s+$¦¦;
                                 $_; } split(m¦\n¦));
            # Add only nonblank lines.
            push(@$ref_cleanedLines, grep(!m¦^\s*$¦, @subLines));
        } else {
            push(@$ref_cleanedLines, $_);
        }
    }

    close($http_fh);
}


sub keepBody(\@) {
    my $ref_lines = shift();

    my $startNotSeen = 1;
    my $endNotSeen = 1;
    my $bodyStartIdx = -1;
    my $bodyEndIdx = -1;
    foreach (@$ref_lines) {
        next unless (defined);
        # Increment first, since we're starting our indices at -1.
        ++$bodyStartIdx if ($startNotSeen);
        ++$bodyEndIdx if ($endNotSeen);
        $startNotSeen = 0 if (m¦<BODY>¦i);
        $endNotSeen = 0 if (m¦</BODY>¦i);
    }

    return (undef, undef) if ($startNotSeen && $endNotSeen);

    # Remove any trailing junk.
    my @trailing = ();
    if ($bodyEndIdx > -1) {
        @trailing = splice(@$ref_lines, $bodyEndIdx);
        # Remove the </BODY> tag.
        if ($trailing[0] =~ m¦^.+</BODY>$¦i) {
            $trailing[0] =~ s¦</BODY>¦¦i;
        } else {
            shift(@trailing);
        }
    }

    # Remove any header.
    my @header = ();
    if ($bodyStartIdx > -1) {
        # Is anything following the <BODY> tag?
        my $inTheHeader = 0;
        if ($ref_lines->[$bodyStartIdx] =~ m¦<BODY>$¦i) {
            # Nope.  Ensure that its removed from @$ref_lines and tossed into
            # the header.
            ++$bodyStartIdx;
            $inTheHeader = 1;
        }

        @header = splice(@$ref_lines, 0, $bodyStartIdx);

        # Remove the lone <BODY> tag from wherever it is.
        if ($inTheHeader) {
            # Nothing following the tag.  Just remove it.
            $header[$#header] =~ s¦<BODY>¦¦i;
            pop(@header) if ($header[$#header] eq '');
        } else {
            # Remove everything up to and including the <BODY> tag from
            # @$ref_lines.  (We only know that something follows the tag.  We
            # don't know what precedes it, if anything.)
            $ref_lines->[0] =~ s¦^(.*<BODY>)¦¦i;
            my $lastLine = $1;
            # Remove the <BODY> tag completely.
            $lastLine =~ s¦<BODY>¦¦i;
            # If there was anything preceding the <BODY> tag, put it at the
            # end of the header.
            push(@header, $lastLine) unless ($lastLine eq '');
        }
    }

    return ( (scalar(@header) ? \@header : undef),
             (scalar(@trailing) ? \@trailing : undef) );
}


sub findComments(\@\@) {
    my $ref_lines = shift();
    my $ref_comments = shift();

    # Now rescan the contents, removing all comments.
    my $insideComment = 0;
    my $idx = 0;
    foreach (@$ref_lines) {
        study;
        if (m¦<!--¦) {
            $insideComment = 1;
            if (m¦^<!--¦) {
                push(@$ref_comments, $idx);
            } else {
                s¦<!--.*$¦¦;
            }
        } elsif (m¦-->¦) {
            $insideComment = 0;
            if (m¦-->$¦) {
                push(@$ref_comments, $idx);
            } else {
                s¦^.*-->¦¦;
            }
        } elsif ($insideComment) {
            push(@$ref_comments, $idx);
        }

        # While we're here, check again and trim off any leading/trailing
        # whitespace.
        s¦^\s+¦¦; s¦\s+$¦¦;

        # Don't forget to bump the index!
        ++$idx;
    }
}


sub findEmptyPairs(\@\@@) {
    my $ref_lines = shift();
    my $ref_empties = shift();

    my $regexp = '';
    foreach (@_) {
        $regexp .= '|' unless ($regexp eq '');
        $regexp .= '<'; $regexp .= $_; $regexp .= '></';
        $regexp .= $_; $regexp .= '>';
    }

    my $idx = 0;
    foreach (@$ref_lines) {
        study;
        push(@$ref_empties, $idx) if (m¦^(?:$regexp)$¦i);
        ++$idx;
    }
}


sub findScriptCode(\@\@) {
    my $ref_lines = shift();
    my $ref_scriptCode = shift();


    # Now rescan the contents, removing all comments.
    my $insideScript = 0;
    my $idx = 0;
    foreach (@$ref_lines) {
        study;
        my $hasScriptEndTag = m¦</SCRIPT>¦i;

        # The order that we do things in is important now.
        #
        # We must start by checking for a newly-seen <SCRIPT>, or a line of
        # code in the middle of a script-block.
        if (m¦<SCRIPT>¦i) {
            # We're only inside of a script-block if there's no end-tag on
            # this line.
            $insideScript = !$hasScriptEndTag;
            if (m¦^<SCRIPT>¦i && !$hasScriptEndTag) {
                push(@$ref_scriptCode, $idx);
            } else {
                # There's either something preceding the open-tag, and/or
                # we're inside of an inline script-blocks.  Remove the
                # open-tag and everything following it.
                s¦<SCRIPT>.*$¦¦i;
            }
        } elsif ($insideScript && !$hasScriptEndTag) {
            push(@$ref_scriptCode, $idx);
        } elsif ($hasScriptEndTag) {
            $insideScript = 0;
            # Nothing follows an ending tag.  If anything precedes the
            # </SCRIPT>, we want to ignore it.
            push(@$ref_scriptCode, $idx);
        }

        # While we're here, check again and trim off any leading/trailing
        # whitespace.
        s¦^\s+¦¦; s¦\s+$¦¦;

        # Did we create any blank lines (say, when removing inline script
        # code)?  Skip those.
        push(@$ref_scriptCode, $idx) if ($_ eq '');

        # Don't forget to bump the index!
        ++$idx;
    }
}


sub getTableLines(\@\@) {
    my $ref_content = shift();
    my $ref_tblLines = shift();

    # Notes:
    #
    # <table> contains <(?:thead|tfoot|tbody|tr)>
    #   -- xhtml-basic only requires <tr>
    # <tbody> contains <tr>
    # <thead> contains <tr>
    # <tfoot> contains <tr>
    # <tr> contains <t[hd]>
    #   -- xhtml-basic requires a <th>
    #   -- The other forms of xhtml require a <td>
    # <th> is like <td>, but for column header info.  Prefer it to the
    #   first <td> cell.

    # Start by finding the table lines.
    my $tableDepth = 0;
    my $maxTableDepth = 0;
    my @tableLinesIdx = ();
    foreach my $idx (0 .. $#$ref_content) {
        my $line = $ref_content->[$idx];
        study $line;

        if ($line =~ m¦<(/?)TABLE>¦i) {
            push(@tableLinesIdx, $idx);
            if ($1) {
                --$tableDepth;
            } else {
                ++$tableDepth;
                if ($tableDepth > $maxTableDepth) {
                    $maxTableDepth = $tableDepth;
                }
            }
        } elsif ($tableDepth ||
                 ($line =~ m¦</?T(?:BODY|D|FOOT|H(?:EAD)?|R)>¦i)) {
            push(@tableLinesIdx, $idx);
        }
    }

    # Break apart and store these lines.
    @$ref_tblLines = ();
    my $isFirstLine = 1;
    my $inMultilineCell = 0;
    my $modifiedLine;
    foreach (@$ref_content[@tableLinesIdx]) {
        next if (m/^\s*$/);

        # Check everything all at once, after studying but before modifying.
        study;

        # Table-Cells on their own line need no additional processing.  Nor do
        # tags alread on their own line.  Skip them so that we don't need to
        # worry about them in the subsequent lines.
        if (m¦^<T[DH]></T[DH]>$¦i || m¦^<[^>]+>$¦) {
            push(@$ref_tblLines, $_);
            next;
        }

        # Don't edit the $_ variable!  That would modify the array elements
        # themselves.  So, we'll check the regexps for all of the expressions
        # we want to handle up front and store them for later reuse.
        my $splitTags = (m¦>\s*<¦);
        my $textBeforeTag = (m¦[^>]\s*</?$c_TableNonCellTags¦o);
        my $textAfterOpenTag = (m¦<$c_TableNonCellTags>\s*[^<]¦o);
        my $textBeforeFirstTable = ($isFirstLine && $textBeforeTag &&
                                    m¦^.+<TABLE>¦i);
        my $hasCellOpen = (m¦<T[DH]>¦i);

        # If there are no special cases to handle, then store and continue.
        unless ($splitTags || $textBeforeTag || $textAfterOpenTag ||
                $textBeforeFirstTable)
        {
            push(@$ref_tblLines, $_);
            next;
        }


        # At this point, we'll have to modify this line somehow, so make a
        # copy.
        $modifiedLine = $_;

        # Remove anything preceding the first <TABLE> tag.  (This is the only
        # edge-case we need, since nothing will follow the last </TABLE> tag.)
        if ($isFirstLine) {
            $isFirstLine = 0;
            if ($textBeforeFirstTable) {
                $modifiedLine =~ s¦^.+(<TABLE>)¦$1¦i;
            }
        }

        # Break off any table cells in this line.
        if ($hasCellOpen) {
            $modifiedLine =~ s¦(.)(<T[DH]>)¦$1\n$2¦g;
            # Note:  $modifiedLine =~ m|</T[DH]>$| is always true, so nothing
            # further to do.
        }

        # Split up tags that are on the same line.  (Ignore any whitespace
        # between them, for the most part.)
        if ($splitTags) {
            $modifiedLine =~ s¦>[ \t\f\r]*<(?!/T[DH]>)¦>\n<¦gi;
            # N.B - No '<TD>...</TD>' or '<TH>...</TH>' should be split by the
            # previous regexp.
        }

        # Put all tags onto their own line, removing any text preceding
        # them.  If it's whitespace before the tag, keep it on the line.
        if ($textBeforeTag) {
            $modifiedLine =~ s¦([^\n])(</?$c_TableNonCellTags)¦$1\n$2¦gi;
        }

        # Put all tags onto their own line, removing any text preceding
        # them.  If it's whitespace after the tag, keep it on the line.
        if ($textAfterOpenTag) {
            $modifiedLine =~ s¦(<$c_TableNonCellTags>)([^\n])¦$1\n$2¦gi;
        }

        push(@$ref_tblLines, split(/\n/, $modifiedLine));
    }
    @tableLinesIdx = (); # Free up memory

    # Scan for and re-join multiline <TH> & <TD> cells that don't
    # contain other tables.
    my @splitCellsIdx = ();
    my $splitStartIdx = 0;  # shouldn't ever be a <TH>/<TD> tag here.
    foreach my $idx (0 .. $#$ref_tblLines) {
        if ($ref_tblLines->[$idx] =~ m¦<$c_TableNonCellTags>¦i) {
            # Reset the counters any time we see any other table tag.  Nested
            # tables won't be reconcatenated into one line.
            $splitStartIdx = 0;
            next;
        }

        my $hasCellOpen = ($ref_tblLines->[$idx] =~ m¦<T[DH]>¦i);
        my $hasCellClosed = ($ref_tblLines->[$idx] =~ m¦</T[DH]>¦i);
        # Skip lines that don't have a hanging tag.
        # [N.B. - We don't have to worry about the first conditional catching a
        #  line with m|</T[DH]>.+<T[DH]>|, since we've already split up
        #  lines after the end-tags.]
        next if ( ($hasCellOpen && $hasCellClosed) ||
                  (!$hasCellOpen && !$hasCellClosed) );

        if ($hasCellOpen) {
            # Dangling open tag.
            $splitStartIdx = $idx;
        } else {  # $hasCellClosed
            # In case of nested tables, some of the dangling closed tags won't
            # have any matching open tags, at least as far as this loop is
            # concerned.
            if ($splitStartIdx) {
                push(@splitCellsIdx, [$splitStartIdx, $idx]);
            }
            # ...aaand, reset.
            $splitStartIdx = 0;
        }
    }

    return $maxTableDepth unless (scalar(@splitCellsIdx));

    foreach (@splitCellsIdx) {
        my ($startIdx, $stopIdx) = @$_;
        my @range = ($startIdx .. $stopIdx);
        # Note:  All <TD> and <TH> tags in @$ref_tblLines are at the beginning
        # of the line they occur in.  So, a simple 'join' is fine.
        my $line = join("", @$ref_tblLines[@range]);
        delete(@$ref_tblLines[@range]);
        $ref_tblLines->[$startIdx] = $line;
    }
    @$ref_tblLines = grep(defined, @$ref_tblLines);

    return $maxTableDepth;
}


sub storeRow_and_reset($\$) {
    my $ref_tbl = shift();
    my $refref_row = shift();

    # Do nothing if there's no table at present.
    my $tblExists = (defined($ref_tbl) && (ref($ref_tbl) eq "HASH"));
    my $isValidRow = (ref($$refref_row) eq "ARRAY");

    if ($tblExists && $isValidRow && scalar(@$$refref_row)) {
        $ref_tbl->{$$refref_row->[0]} = $$refref_row;
    }
    # Reset the row by setting the underlying arrayref variable to a new
    # arrayref.
    $$refref_row = [];
    return $tblExists;
}


sub pushTable(\@$\@;$) {
    my $ref_stack = shift();
    my $ref_tbl = shift();
    my $ref_row = shift();
    my $pushTblOnly = (scalar(@_) ? shift() : 0);

    my $lastRowKey = (scalar(@$ref_row) ? $ref_row->[0] : undef);

    # Do nothing if there's no table at present.
    return unless (storeRow_and_reset($ref_tbl, $ref_row));
    if ($pushTblOnly) {
        push(@$ref_stack, $ref_tbl);
    } else {
        push(@$ref_stack, [$ref_tbl, $lastRowKey]);
    }
}


sub parseTables_rowMajor(\@$\@) {
    my $ref_tblContent = shift();
    my $hasNested = shift();
    my $ref_tables = shift();

    # This is fairly easy.  We just look for the <tr> tags and use the first
    # column as the key.
    my $ref_currentTbl = undef;
    my $ref_currentRow = [];
    my @tblStack = ();
    foreach (@$ref_tblContent) {

        study;
        # Ignore stray text and certain table-tags.
        next unless(m¦</?T(?:ABLE|[DHR])>¦i);

        if (m¦<TABLE>¦i) {
            # New table.  If it's nested, put the current one back on the
            # stack.
            pushTable(@tblStack, $ref_currentTbl, @$ref_currentRow);
            $ref_currentTbl = {};
        }
        elsif (m¦</TABLE>¦i) {

            # This time, store the current table in the output array.
            pushTable(@$ref_tables, $ref_currentTbl, @$ref_currentRow, 1);
            my $lastRowSeen;
            ($ref_currentTbl, $lastRowSeen) = pop(@tblStack);
            if (defined($lastRowSeen)) {
                $ref_currentRow = $ref_currentTbl->{$lastRowSeen};
            }

        }
        elsif (m¦</?TR>¦i) {
            storeRow_and_reset($ref_currentTbl, $ref_currentRow);
        }
        elsif (m¦<TD>¦i) {
            push(@$ref_currentRow, $_);
        }
        elsif (m¦<TH>¦i) {
            # Keep the most recent heading, overwriting any earlier ones.
            $ref_currentRow->[0] = $_;
        }

    }
print Data::Dumper->Dump([\@tblStack, $ref_tables],
                         [qw(Cruft CookedTables)]), "\n";
    # Anything leftover in @tblStack is an unclosed table.  Explicitly
    # discarding it to make it clear that it's garbage.
    @tblStack = ();

}


sub parseTables_columnMajor(\@$\@) {
    my $ref_tblContent = shift();
    my $hasNested = shift();
    my $ref_tables = shift();

    # FIXME:  This will be far easier to do using the HTML::TableExtract
    # package.
}


sub parse_statsPage($$\%\%\%) {
    my $how = shift();
    my $url = shift();
    my $ref_auth = shift();
    my $ref_options = shift();
    my $ref_statsMap = shift();

    my @content;

    # FIXME:  We should use the HTML::TableExtract package, since it does most
    # of what we want.
    #
    # Create a list of dependent pkgs in a comment in this file, to be moved
    # later into a README file and/or a script to get the pkgs from CPAN &
    # install in /usr/local/share/perl or somesuch.
    #
    # Since HTML::TableExtract uses HTML::Parser, we can use the latter to do
    # other things.
    #
    # Set the following on the HTML::TableExtract object (inherited from
    # HTML::Parser):
    #     $teParser->emtpy_element_tags(1);
    #     $teParser->ignore_elements(qw(style img form));
    #
    # Use $teParser->parse_file($fh) to parse.

    # FIXME:  Regroup the options into a $opt{'syslog'}{...} subhash and a
    # $opt{'dslStats'}{...} subhash, or somesuch.

    read_and_clean_webpage($how, $url, %$ref_auth, @content);

    # Separate the body from anything else.
    my ($ref_header, $ref_trailing) = keepBody(@content);

    if (exists($ref_options->{'StatsInScriptCode'})) {
        # FIXME:  Add code & use the correct option.
        my $tmp;
    } else {
        # Remove comments, empty tag pairs, and scripts embedded in the body.
        my @removeIdx = ();
        findComments(@content, @removeIdx);
        findEmptyPairs(@content, @removeIdx, 'li', 'dl', 'dt');
        findScriptCode(@content, @removeIdx);

        # Delete the lines marked for removal.
        if (scalar(@removeIdx)) {
            delete(@content[@removeIdx]);
            @content = grep(defined, @content);
        }

#DBG::rm#
# print (Data::Dumper->Dump([\@content, $ref_header,
# $ref_trailing, \@removeIdx], [qw(body Header Trailing RemoveThese)]), "\n");

        # FIXME:  Cleanup.
        #if ( exists($ref_options->{'Table_RowMajor'}) ||
        #     exists($ref_options->{'Table_ColumnMajor'}) )
        if (1 || # FIXME
            exists($ref_options->{'TableLayout_RowMajor'})) {
            my @tableData = ();
            my $hasNested = getTableLines(@content, @tableData);
#DBG::rm#
#print Data::Dumper->Dump([\@tableData],
#                         [qw(TableContents)]), "\n";
            my @tableMaps = ();
            if (1 || #FIXME
                $ref_options->{'TableLayout_RowMajor'}) {
                parseTables_rowMajor(@tableData, $hasNested, @tableMaps);
            } else {
                parseTables_columnMajor(@tableData, $hasNested, @tableMaps);
            }
        }
    }

##print "'", join("'\n'", @content), "'\n";
}


#----------
# Functions for handling event data
#----------


sub printEvent($\@) {
    my $fh = shift();
    my $ref_event = shift();

    my $hrt = $ref_event->[$c_HRT_Idx];
    $hrt =~ s/\s+/ /g;
    print $fh ($hrt, ":    DSL connection ");
    print $fh ($ref_event->[$c_UpDownIdx] ? "came back up" : "went down   ");
    printf $fh ("\t    (%10ds)\n", $ref_event->[$c_tsIdx]);
}


sub isValidEvent($) {
    my $ref_event = shift();

    return 1 if (defined($ref_event) && (ref($ref_event) eq "ARRAY")
                 && scalar(@$ref_event));
    # else:

    print STDERR ("!!!INTERNAL ERROR!!! - ");
    if (defined($ref_event)) {
        print STDERR ("Undefined entry in new event array.\n",
                      " "x24, "Expected an arrayref.\n");
    } elsif (ref($ref_event) ne "ARRAY") {
        my $type = ref($ref_event);
        print STDERR ("Entry in new event array is a ");
        if ($type) {
            print STDERR ('"', $type, '"');
            }
        else {
            print STDERR ("scalar value");
        }
            print STDERR (",\n", " " x24, "not an arrayref.\n");
    } else {
        print STDERR ("Empty event.\n");
    }
    print STDERR (" "x24, "Ignoring bogus entry...\n");

    return 0;
}


sub startup_eventDefaultValue() {
    my @defaultInitialEvent = ();
    $defaultInitialEvent[$c_UpDownIdx] = 1;
    $defaultInitialEvent[$c_nDropsIdx] = 0;
    # N.B. - DO NOT use the current time.  Doing so may remove unseen events
    # at startup.
    $defaultInitialEvent[$c_HRT_Idx] = "\<\<Daemon Startup\>\>";
    $defaultInitialEvent[$c_tsIdx] = 0;
    return \@defaultInitialEvent;
}


sub placeholderSyslogEvent($) {
    my $t = shift();
    my @event = ();
    $event[$c_UpDownIdx] = 1;
    $event[$c_nDropsIdx] = 0;
    # N.B. - DO NOT use the current time.  Doing so may remove unseen events
    # at startup.
    $event[$c_tsIdx] = $t;
    $event[$c_HRT_Idx] = strftimeFmt($c_myTimeFmt, localtime($t));
    return \@event;
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


sub tieArrayElement2eventArray($;$) {
    my $tieElement = shift();
    my $keepTieArrayOrder = (scalar(@_) ? shift() : 0);
    study $tieElement;

    my @eventArray = ();
    if ( ($tieElement =~ m/^\[\[/) && ($tieElement =~ m/\]\]$/) ) {
        $tieElement =~ s/^\[\[//;
        $tieElement =~ s/\]\]$//;
        my @eventArrayTAO = split(/;\|;/, $tieElement);

        if (scalar(@eventArrayTAO) >= 4) {
            if ($keepTieArrayOrder) {
                @eventArray = @eventArrayTAO;
            } else {
                $eventArray[$c_UpDownIdx] = $eventArrayTAO[0];
                $eventArray[$c_nDropsIdx] = $eventArrayTAO[1];
                $eventArray[$c_HRT_Idx] = $eventArrayTAO[2];
                $eventArray[$c_tsIdx] = $eventArrayTAO[3];
            }
        }
    }

    return \@eventArray;
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


sub retrieve_statistics($$) {
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
        return (-1, -1);
    }

    # We're ready!  Retrieve the two measurements.
    my @result = tieArrayElement2eventArray($measurements[$#measurements], 1);

    # Cleanup
    undef($ref_tied);
    untie(@measurements);

    # Postprocessing

    my $nMeasures = scalar(@result);
    if ($nMeasures < 1) {
        return (-1, -1);
    }
    if (($targ1 < 0) || ($targ1 > $nMeasures)) {
        $targ1 = 0;
    }
    if (($targ1 < 0) || ($targ2 > $nMeasures)) {
        $targ2 = 0;
    }

    foreach my $t ($targ1, $targ2) {
        # FIXME:  I should really make a set of constants for the
        # @g_Measurements indices.
        next unless ($t == 1);
        my $t_UptdInterval_end = t2DropCountInterval($result[$#result], 1);
        my $now = time();
        if ($now >= $t_UptdInterval_end) {
            # The most recent data might be from an earlier
            # '$_DropCountInterval'.  If so, then we need to reset the drop
            # count.
            $result[$t] = 0;
        }
    }

    # *Now* we can return.
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

            print("[[", $isUp, ";|;", $ndn{$tsh}, ";|;", $hrt,
                  ";|;", $ts, "]]\n");
            print;
        }
    }
    close(LFH);

    exit 0;
}


# Utility for merging a file with a recovered tie-array with the MRTG data
# log.
sub recoveredTieArray2MRTG($$) {
    my $recoveredDatafile = shift();
    my $mrtgDatafile = shift();

    die ("Cannot recover:  bad args")
        unless (($recoveredDatafile ne "") && ($mrtgDatafile ne ""));

    my $mrtgNewDatafile = $mrtgDatafile . '-nu';

    $g_refDataTieObj = tie(@g_Measurements, 'Tie::File', $recoveredDatafile,
                          'mode' => O_RDONLY);
    my @unsortedData = ();
    my %seen = ();
    foreach my $entryStr (@g_Measurements) {
        my @event = tieArrayElement2eventArray($entryStr);
        unless (exists($seen{$event[$c_tsIdx]})) {
            $seen{$event[$c_tsIdx]} = 1;
            push(@unsortedData, \@event);
        }
    }

    # Sort the new data, in ascending order.  Free the old data (since it
    # might be quite large).
    #
    my @recoveredEvents = sort({ $a->[$c_tsIdx] <=> $b->[$c_tsIdx]
                               } @unsortedData);
    @unsortedData = ();

    updateMRTGdata(@recoveredEvents, $mrtgDatafile, $mrtgNewDatafile);
    exit 0;
}


#----------
# MRTG Log-Handling
#----------


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


sub projectDropCountsForward(\@\@) {
    my $ref_data = shift();
    my $ref_recentEvents = shift();

    # Determine which '$_DropCountInterval's have drop events.
    # Also find the timestamp of the most recent drop event.
    my %updtIntervalHasDropEvents = ();
    my $lastSeenDrop = 0;
    foreach my $ref_event (@$ref_recentEvents) {
        my $ev_t_updtInterval = t2DropCountInterval($ref_event->[$c_tsIdx]);
        unless (exists($updtIntervalHasDropEvents{$ev_t_updtInterval})) {
            $updtIntervalHasDropEvents{$ev_t_updtInterval} = 0;
        }
        if ($ref_event->[$c_UpDownIdx] == 0) {
            $lastSeenDrop = $ref_event->[$c_tsIdx];
        }
        if ($ref_event->[$c_nDropsIdx]) {
            $updtIntervalHasDropEvents{$ev_t_updtInterval} = 1;
        }
    }

    # Remember: @$ref_data is in descending chronological order.  So, to
    # project the drop-counts "forward" in time, we need to reverse the index
    # order (which, sadly, we can't use the '..' operator to do directly).
    foreach my $idx (reverse(0 .. ($#$ref_data -1))) {
        my $timeUptdInterval = t2DropCountInterval($ref_data->[$idx][0]);

        # Ignore data not in the update interval(s) of the new events.
        unless (exists($updtIntervalHasDropEvents{$timeUptdInterval})) {
            next if ($timeUptdInterval <= $lastSeenDrop);
            # Any '$_DropCountInterval' later than the timestamp of the last
            # drop event seen should have its count "reset" to 0.
            $updtIntervalHasDropEvents{$timeUptdInterval} = 0;
        }

        if ($updtIntervalHasDropEvents{$timeUptdInterval}) {
            # There are drop events somewhere in this '$_DropCountInterval'.
            # Extend them forward.
            if ( ($ref_data->[$idx+1][2] != 0) &&
                 ($ref_data->[$idx][2] == 0) )
            {
                $ref_data->[$idx][2] = $ref_data->[$idx+1][2];
            }
            if ( ($ref_data->[$idx+1][4] == 0) &&
                 ($ref_data->[$idx][4] == 0) )
            {
                $ref_data->[$idx][4] = $ref_data->[$idx+1][4];
            }
        } else {
            # No drop events anyplace in this '$_DropCountInterval'.  Reset
            # the count to zero (but not the max counts).
            $ref_data->[$idx][2] = 0;
            #$ref_data->[$idx][4] = 0;
        }

    }
}


sub updateMRTGdata(\@$$) {
    my $ref_newData = shift();
    my $mrtgDatafile = shift();
    my $mrtgNewDatafile = shift();

    # No new data?  Nothing to do...
    return 1 unless (scalar(@$ref_newData));

    if ($_DebugLoggingIsActive) {
        # N.B. - Reason for this 'if'-statement == avoid doing the 'map(...)'
        #        work when not needed.
        printDbg("\n\t",
                 join("\n\t", map({ my $rT = ref;
                                    if ("ARRAY" eq $rT) {
                                        eventArray2tieArrayElement(@{$_});
                                    } else {
                                        '!!!!! Error: ref == "' . $rT . '"'
                                    }
                                  } @$ref_newData)
                     ), "\n");
    }

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
        printErr($failure,
                 "Cannot update MRTG data in \"", $mrtgDatafile, "\"\n",
                 "DSL State information between ", $t_firstNewEvent,
                 " and ", $t_lastNewEvent, "\n",
                 "will be lost.\n");
        return 0;
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
    projectDropCountsForward(@mergedData, @$ref_newData);

    #
    # Open the file for the updated data:
    #

    unless (open(OUT_FH, ">$mrtgNewDatafile")) {
        printErr("Unable to open file for writing: \"",
                 $mrtgNewDatafile, "\"\n", "Reason: \"$!\"\n",
                 "Cowwardly refusing to update the MRTG data.\n");
        return 0;
    }

    # Write out the records preceding the merge region.
    #
    # Note:  We need to project the drop count from the most-recent record in
    #        '@mergedData' forward in time, into every MRTG record before the
    #        merge interval.  The best way to do it is to splice off the
    #        pre-merge records. and call projectDropCountsForward()
    my @preMergeData = map({ [ split(/\s/, $_) ]
                           } @MRTG_Data[0 .. ($mergeStartIdx - 1)]);

    # The first record requires special handling:
    my $ref_firstRecord = shift(@preMergeData);
    if ($mergeStartIdx == 1) {
        # The first record always matches the first 3 elements of the next
        # record.  If we merge in data at the top, we need to mimic this.
        @$ref_firstRecord = @{$mergedData[0]}[(0 .. 2)];
    } else {
        # Just copy the drop count from the first merge record.
        $ref_firstRecord->[2] = $mergedData[0][2];
    }
    print OUT_FH (join(' ', @$ref_firstRecord), "\n");

    # Write the subsequent pre-merge records, if any.
    if (scalar(@preMergeData)) {
        projectDropCountsForward(@preMergeData, @$ref_newData);
        foreach my $ref_record (@preMergeData) {
            print OUT_FH (join(' ', @$ref_record), "\n");
        }
    }

    # Write Merged.
    foreach my $ref_record (@mergedData) {
        print OUT_FH (join(' ', @$ref_record), "\n");
    }

    # Write out the remaining records.
    foreach my $entry (@MRTG_Data[($mergeEndIdx + 1) .. $#MRTG_Data]) {
        print OUT_FH ($entry, "\n");
    }
    close(OUT_FH);

    # Now overwrite MRTG's file with our update file.
    unless (rename($mrtgNewDatafile, $mrtgDatafile)) {
        printErr("Failed to update the MRTG data (could not rename\n",
                 "the updated file).\n");
        return 0;
    }

    return 1;
}


#----------
# Daemon-related
#----------


sub daemonize(;$) {
    my $keepParentRunning = (scalar(@_) ? shift() : 0);

    defined(my $pid = fork) or die "Can't fork: $!";
    if ($pid) {
        if ($keepParentRunning) {
            return 1;
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

    defined($pid = fork) or die "Can't fork: $!";
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
    #return 0 if (scalar(@match));
    ## Don't use "system()", as it discards the output.

    print STDERR ("Process '", $daemonPid, "' not found.\n");
    print STDERR ("Check for dead/stale PID file:  \"", $_DaemonPIDFile,
                  "\"\n");
    return 1;
}


sub daemon_sig_cleanup {
    my $killsig=shift();

    untie(@g_Measurements);
    undef($g_refDataTieObj);
    unlink($_DaemonPIDFile);

    if ($killsig =~ m/HUP|INT|TERM/) {
        # Only delete the data file in the event of a normal termination.
        unlink($_DataFile);
        exit 0;
    } # else
    #FIXME:  Would be nice to xlate this into the number...
    exit 1; #$killsig;
}


sub daemon_housekeeping(\$\$$) {
    my $ref_inDST = shift();
    my $ref_currentWeek_endTs = shift();
    my $now = shift();

    # Do nothing until next week.
    unless ($$ref_currentWeek_endTs < $now) {
        # Update the week counter.
        $$ref_currentWeek_endTs += $c_Week_Secs;

        # Now check and see if we're in DST.
        $$ref_inDST = (localtime())[8];
    }

    my $datafileSize = (stat($_DataFile))[7];
    if ($datafileSize > $_MaxSize_DataFile) {
        printDbg("\tRotating data file...\n");

        my $errmsg;
        if (open ROT_FH, ">", $_DataFile.'-old') {
            foreach (@g_Measurements) {
                print ROT_FH ($_, "\n");
            }
            close(ROT_FH);
            my $threeQuarters = scalar(@g_Measurements) * 3 / 4;
            my @keep = @g_Measurements[($threeQuarters .. $#g_Measurements)];
            @g_Measurements = @keep;
        } else {
            printErr("Failed to open file for writing:\n\t\"",
                     $_DataFile, "-old\"\n  ", $!,
                     "\nThe original file, \"", $_DataFile,
                     "\" will keep growing.\n",
                     "Data file rotation failed.\n");
        }
    }

    # Rotate the log file after any other housekeeping, in case rotation
    # fails.
    my $logSize = (stat(STDOUT))[7];
    if ($logSize > $_MaxSize_Log) {
        printDbg("\tRotating log file...\n");

        if (rename($_DaemonLog, $_DaemonLog.'-old')) {
            unless (open STDOUT, ">$_DaemonLog") {
                my $errmsg = strftime($c_myTimeFmt, localtime());
                $errmsg .= ":  Logfile Rotation Failed!";
                $errmsg .= "Could not reopen $_DaemonLog:\n  $!\n";
                $errmsg .= "This will cause the original file, now named\n\"";
                $errmsg .= $_DaemonLog;
                $errmsg .= "-old\"to keep growing.\nRestarting the daemon ";
                $errmsg .= "is recommended.\n";
                open(EFH, ">$_DaemonLog")
                    and print EFH ($errmsg)
                        and close(EFH);
            }
        } else {
            printErr("Could not rotate ", $_DaemonLog, ":\n  ", $!,
                     "\nThe log file will keep growing.\n");
        }
    }
}


sub daemon_main(\%\%) {
    my %options = %{shift()};
    my %auth = %{shift()};

    # Print out something for the log file
    print "\n", "="x78, "\n\n";
    print "#  Starting $_MyName in Daemon Mode\n";
    my $date = strftime($c_myTimeFmt, localtime());
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
        } elsif ($signame =~ m/USR[12]/) {
            # Use a closure to define the "reload-the-configfile" handler.
            $SIG{$signame} = sub {
                reprocessConfigFile(%options, %auth);
            };
        } else {
            $SIG{$signame} = \&daemon_sig_cleanup;
        }
    }

    # Tie an array to the data file, keeping any existing one.
    #
    if ( -f $_DataFile) {
        # Make sure the permissions are correct.
        chmod(0644, $_DataFile);
        $g_refDataTieObj = tie(@g_Measurements, 'Tie::File', $_DataFile,
                              'mode' => O_APPEND | O_RDWR);
    } else {
        $g_refDataTieObj = tie(@g_Measurements, 'Tie::File', $_DataFile);
    }
    my $failure = checkForErrors_tie($!, $@, $g_refDataTieObj, $_DataFile);
    if (defined($failure)) {
        print STDERR ($failure,
                     "\nCowardly refusing to continue running.\n");
        exit 1;
    }

    #
    # Variables used in the Main Loop
    # (No need to keep redeclaring them every iteration.)
    #

    my @updatedDslState = ();
    my $probe_duration;
    my $adjustedSleepTime;
    my $ref_lastEvent = startup_eventDefaultValue();

    if (scalar(@g_Measurements)) {
        my $ref_tmpArr
            = tieArrayElement2eventArray($g_Measurements[$#g_Measurements]);
        # If there was an error retrieving the last measurement, stick to the
        # default (which we don't need to add to @g_Measurements, since we know
        # that it has data).
        if (scalar(@$ref_tmpArr)) {
            $ref_lastEvent = $ref_tmpArr;
        }
    }

    my $inDST = 0;
    my $currentWeek_endTs = 0;
    init_DST_vars($inDST, $currentWeek_endTs);

    #
    # The Main Loop:
    #

    while (1) {
        my $now = time();
        my $probe_duration = -$now;

        printErr("\n\n");
        if ($options{'SyslogUrl'} ne "") {
            printDbg("Reading DSL modem log.\n");

            parse_syslog($_GetURLVia, $options{'SyslogUrl'}, %auth,
                         $options{'DslUp_expr'}, $options{'DslDown_expr'},
                         $options{'_Time_Regexp_'}, @updatedDslState);
            adjustBorkedTimestamps(@updatedDslState, $inDST,
                                   $options{'ModemAdjustsForDST'},
                                   $options{'ExtraTimeOffset'},
                                   $options{"_strftime_Format_"});
            removeOldEventsAndAdjust(@updatedDslState,
                                     $ref_lastEvent->[$c_tsIdx],
                                     $ref_lastEvent->[$c_nDropsIdx]);
            resetStaleDropCounts(@updatedDslState, $now, @$ref_lastEvent,
                                 $options{"_strftime_Format_"});
        } else {
            # Create a placeholder that we can add the S&R, Attenuation,
            # etc. statistics to.  This will also become $ref_lastEvent later
            # on.
            @updatedDslState = ();
            push(@updatedDslState, placeholderSyslogEvent($now));
        }

        printDbg("    Storing...\n");

        # Output:
        foreach my $ref_event (@updatedDslState) {
            # Empty data is an error of some sort.
            next unless(isValidEvent($ref_event));

            # 'push' on a tied-array always flushes.
            push(@g_Measurements,
                 eventArray2tieArrayElement(@$ref_event));
            # Log the event, as well (at least for now).
            printEvent(\*STDERR, @$ref_event);
            # Update the last-event holder.
            $ref_lastEvent = $ref_event;
        }

        printDbg("    Updating the MRTG data...\n");

        # Build the new MRTG data log file & rotate it in.
        updateMRTGdata(@updatedDslState,
                       $options{'_MRTG_Data_'},
                       $options{'_MRTG_Updated_Data_'});

        daemon_housekeeping($inDST, $currentWeek_endTs, $now);

        printDbg("Done.  Sleeping.\n");

        $probe_duration += time();
        $adjustedSleepTime = $options{"_UpdateInterval_sec_"};
        next if ($adjustedSleepTime == $probe_duration);
        if ($adjustedSleepTime > $probe_duration) {
            $adjustedSleepTime -= $probe_duration;
        }
        sleep($adjustedSleepTime);
    }
}


sub start_daemon($\%\%) {
    my $keepParentRunning = shift();
    my $ref_options = shift();
    my $ref_auth = shift();

    # daemonize() either exits the parent process or returns 0.
    daemonize($keepParentRunning) or return 0;

    # We're the child process if we reach this point.
    renice_self();
    daemon_main(%$ref_options, %$ref_auth);
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

#DBG::rm#
my %dummy=();
$_DebugLoggingIsActive=1;
parse_statsPage('curl',
                'file:///home/candide/src/perl/'.$ARGV[0],
                %dummy, %dummy, %dummy);
exit 0;

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
} elsif ($ARGV[0] eq "-p") {
    appendSecret2ConfigFile(); # This fn. exits.
} elsif ($ARGV[0] eq "--l2t") {
    # For recovery only.
    shift(@ARGV);
    myLogfile2tieArrayElement($ARGV[0]); # This fn. exits.
} elsif ($ARGV[0] eq "--recover2mrtg") {
    # For recovery only.
    shift(@ARGV);
    recoveredTieArray2MRTG($ARGV[0], $ARGV[1]); # This fn. exits.
} elsif ($ARGV[0] eq "--keep-in-foreground") {
    # For Debugging Purposes Only:
    my %dbgO;
    my %dbgA;
    processConfigFile(%dbgO);
    validate_options(%dbgO, %dbgA);
    daemon_main(%dbgO, %dbgA);
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
my %auth;
processConfigFile(%options);

if ($checkNow) {
    # We don't need to validate the various pieces-parts needed for
    # daemon-mode, but we do need to validate any web page password.
    validate_auth_only(%options, %auth);
    my @recentState = ();
    my $inDST;
    my $dummy;
    init_DST_vars($inDST, $dummy);
    print "===== Current DSL Modem Syslog: =====\n\n";
    parse_syslog($_GetURLVia, $options{'SyslogUrl'}, %auth,
                 $options{'DslUp_expr'}, $options{'DslDown_expr'},
                 $options{'_Time_Regexp_'}, @recentState);
    adjustBorkedTimestamps(@recentState, $inDST,
                           $options{'ModemAdjustsForDST'},
                           $options{'ExtraTimeOffset'},
                           $options{"_strftime_Format_"});
    foreach my $ref_event (@recentState) {
        printEvent(\*STDOUT, @$ref_event);
    }
    exit 0;
} else {
    my $noDaemonRunning = no_running_daemon();
    if ($daemonize) {
        # Only validate the options in daemon-mode.
        validate_options(%options, %auth);

        if ($noDaemonRunning) {
            start_daemon($reportAfterDaemonizing, %options, %auth);

            # If we return from start_daemon(), we're the parent.  Let's sleep
            # for a bit for the daemon to start up before going on (and
            # getting the ping data).
            sleep($_TieAttempts*$_TieWait + $_PostDaemonizeWait);

        }
        elsif (!$reportAfterDaemonizing) {
            # Don't do anything more.
            print("Daemonized instance already running.  Examine \n\"",
                  $_DaemonPIDFile, "\" for its PID.\n\n",
                  "To restart $0, do the following:\n",
                  "\tkill \$(\< ", $_DaemonPIDFile, ");\n",
                  "\t$0 -d\n");
            exit 0;
        }

        # else:  We want to ping whether or not we daemonize.
    }
    elsif ($noDaemonRunning && !$daemonize) {
        print("No daemonized instance running.  Rerun \n",
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
my @rates = retrieve_statistics($statistic1, $statistic2);
printf ("%.0f\n%.0f\n", $rates[0], $rates[1]);

# TODO:
#
# Need to make sure that there's no collision between MRTG and the data file
# update.  Whether this goes in the client-mode or the daemon, I don't know
# yet.


#################
#
#  End
