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
use HTML::TableExtract;

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
#my $c_IgnoredStandalone_re
#    = '(?:B(?:ASE(?:FONT)?|R)|COL|FRAME|HR|LINK|META)\s*/?';
#my $c__Ignored1_re='[AB]|D(?:EL|IV)|EM|FO(?:RM|NT)|I(?:MG|NPUT)?|';
#my $c__Ignored2_re='NOBR(?:EAK)?|S(?:PAN|TR(?:IKE|ONG)|U[BP])|TT|U';
my $c_IgnoredStandalone_re
    = '(?:B(?:ASE(?:FONT)?)|COL|FRAME|HR|LINK|META)\s*/?';
my $c__Ignored1_re='A|DIV|FO(?:RM|NT)|I(?:MG|NPUT)|';
my $c__Ignored2_re='NOBR(?:EAK)?|SPAN';

my $c_IgnoredPlain_re='/?(?:'.$c__Ignored1_re.$c__Ignored2_re.')';
my $c_Ignored_Tags_re
    = '(?:/?(?:'.$c_IgnoredPlain_re.')|'.$c_IgnoredStandalone_re.')';

# Used to warn the user when they need to rerun this script in '-p'-mode.
my $c_VerifyShhhh='468acef89c068eb5957bc0d1a066435cd1e2adca8e894b577b72f4'.
    'bef6cdf25bce33bf3ebc57ad5efb7500e9299c310cb877865c87b07a1e2c40f9303b'.
    '4f89272578c046cbf0432f';
my $c_ExpectedShhhh='sub shhhhh($$){ my $c_ExpectedShhhh="@th350und0fth3"';
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
            for ($line) {
                s/^['"]//;
                s/['"]$//;
            }
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

    if (exists($ref_options->{'GPG'}{'SettingsFile'})) {
        return read_fromGPG($ref_options->{'GPG'}{'SettingsFile'},
                            %$ref_auth);
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

    my $ref_MRTGOpts = $ref_options->{'MRTG'};
    if (exists($ref_MRTGOpts->{'LogDir'})) {
        unless ((-d $ref_MRTGOpts->{'LogDir'}) &&
                (-w $ref_MRTGOpts->{'LogDir'}))
        {
            print STDERR ("ERROR:  Parameter 'MRTG.LogDir' set to ",
                          "bad value.\n",
                          "Not a directory or not writeable:  \"",
                          $ref_options->{"MRTG.LogDir"},
                          "\"\n\n",
                          "Cowardly refusing to continue.\n");
            exit 2;
        }
    } else {
        print STDERR ("ERROR:  Configuration file parameter 'MRTG.LogDir' ",
                      "not set.\n\n",
                      "Cowardly refusing to continue.\n");
        exit 2;
    }

    if (exists($ref_MRTGOpts->{'Our_DataFile'})) {
        my $mrtg_log_file = $ref_MRTGOpts->{'LogDir'};
        unless ($mrtg_log_file =~ m|/$|) {
            $mrtg_log_file .= '/';
        }
        $mrtg_log_file .= $ref_MRTGOpts->{'Our_DataFile'};
        unless ((-e $mrtg_log_file) && (-w $mrtg_log_file)) {
            print STDERR ("ERROR:  Parameter 'MRTG.Our_DataFile' set to ",
                          "bad value.\n",
                          "File doesn't exist or isn't writeable:  \"",
                          $mrtg_log_file, "\"\n\n",
                          "Cowardly refusing to continue.\n");
            exit 2;
        }

        # Constructed Options:
        $ref_MRTGOpts->{'_Data_'} = $mrtg_log_file;
        $ref_MRTGOpts->{'_Updated_Data_'} = $mrtg_log_file;
        $ref_MRTGOpts->{'_Updated_Data_'} .= '-new'
    } else {
        print STDERR ("ERROR:  Configuration file parameter ",
                      "'MRTG.Our_DataFile' not set.\n\n",
                      "Cowardly refusing to continue.\n");
        exit 2;
    }
}


sub separateOutOptionSets(\%\%$) {
    my $ref_allOptions = shift();
    my $ref_optSet = shift();
    my $keyPrefix = shift();

    my @selectedKeys = grep(/$keyPrefix\./, keys(%$ref_allOptions));
    foreach (@selectedKeys) {
        my $newKey = $_;
        $newKey =~s/$keyPrefix\.//;
        $ref_optSet->{$newKey} = $ref_allOptions->{$_};
    }
    if (scalar(@selectedKeys)) {
        delete @$ref_allOptions{@selectedKeys};
    }
    $ref_allOptions->{$keyPrefix} = $ref_optSet;
}


sub processConfigFile(\%) {
    my $ref_options = shift();

    read_config(%$ref_options);

    #
    # Process/Compute Options Not Requiring Validation
    #

    # Separate out all of the different sets of options:
    #
    my %mrtgOpt = ();
    separateOutOptionSets(%$ref_options, %mrtgOpt, 'MRTG');
    my %gpgOpt = ();
    separateOutOptionSets(%$ref_options, %gpgOpt, 'GPG');
    my %syslogOpt = ();
    separateOutOptionSets(%$ref_options, %syslogOpt, 'Syslog');
    my %statsOpt = ();
    separateOutOptionSets(%$ref_options, %statsOpt, 'Stats');
    my %statsTblOpt = ();
    separateOutOptionSets(%statsOpt, %statsTblOpt, 'Table');


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
    unless (exists($c_TimeRegexps{$syslogOpt{"TimeFormat"}})) {
        print STDERR ("ERROR:  Bad value:  \"",
                      $syslogOpt{'TimeFormat'}, "\"\n",
                      "Parameter 'Syslog.TimeFormat' must be set to ",
                      "one of the following:\n",
                      "\t\"", join("\"\n\t\"", keys(%c_TimeRegexps)),
                      "\"\n\n",
                      "Cowardly refusing to continue.\n");
        exit 2;
    }
    $syslogOpt{'_Time_Regexp_'} = $c_TimeRegexps{$syslogOpt{'TimeFormat'}};
    $syslogOpt{'_strftime_Format_'}
        = $c_TimeFormatStr{$syslogOpt{'TimeFormat'}};

    # 'Stats.Table.AdjustUnits'
    #
    if (exists($statsTblOpt{'AdjustUnits'})) {
        if (exists($statsTblOpt{'Heading_exprs'})) {
            my $nExprs = scalar(@{$statsTblOpt{'Heading_exprs'}});
            if ($nExprs > scalar(@{$statsTblOpt{'AdjustUnits'}})) {
                --$nExprs;
                $statsTblOpt{'AdjustUnits'}[$nExprs] = 1;
            }
        }
        foreach (@{$statsTblOpt{'AdjustUnits'}}) {
            # Convert to number:
            $_ += 0;
            unless (defined && $_) {
                $_ = 1;
            }
        }
    }

    # 'Stats.Table.Row_exprs' and 'Stats.Table._Row_re_'
    #
    if (exists($statsTblOpt{'Row_exprs'})) {
        my $rowExpJoined = join(')|(?:', @{$statsTblOpt{'Row_exprs'}});
        $statsTblOpt{'_Row_re_'} = qr/((?:$rowExpJoined))/;
    }

    # 'Stats.Table.KeepIdx' and 'Stats.Table._KeepColumn_'
    if (exists($statsTblOpt{'KeepIdx'})) {
        $statsTblOpt{'_KeepColumn_'} = $statsTblOpt{'KeepIdx'} + 1;
    }

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

    #print STDERR ("#DBG# ", Dumper($ref_options), "\n");

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


sub parse_syslog($\%\%\@) {
    my $how = shift();
    my $ref_opts = shift();
    my $ref_auth = shift();
    my $ref_dslState = shift();

    my $url = $ref_opts->{'Url'};
    my $dslUp_re = $ref_opts->{'DslUp_expr'};
    my $dslDown_re = $ref_opts->{'DslDown_expr'};
    my $time_re = $ref_opts->{'_Time_Regexp_'};

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


sub read_and_clean_webpage($\%\%\@) {
    my $how = shift();
    my $ref_opts = shift();
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

    my $url = $ref_opts->{'Url'};

    my $getUrl_cmd = $c_WebGet{$how}{'cmd'};
    $getUrl_cmd .= $c_WebGet{$how}{'args'};
    my $http_fh;
    unless (open($http_fh, '-|', $getUrl_cmd.$auth.$url)) {
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

        # Remove intra-tag spaces, which will make the subsequent regexps
        # simpler.
        s¦/\s+>¦/>¦g;
        s¦\s+/?>¦$1>¦g;
        s¦(</?)\s+¦$1¦g;

        # Remove certain tags that are causing problems for
        # HTML::TableExtract.
        s¦<$c_Ignored_Tags_re(?:\s+[^<>\n]+)?>¦¦goi;

        # Some of these DSL modems put a line-break into the labels.  We
        # don't need that.  So, convert the <br/> tags into a ' '.
        s¦<(?:BR/?|P(?:\s+[^<>\n]+)?>\s*</P)>¦ ¦gi;

        # NOW that we've pruned out all manner of stuff, we can check for and
        # skip empty lines.
        #
        next if (m/^\s*$/);

        # HTML::TableExtract has trouble when tags are all crammed into one
        # line.
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


sub createTableParser(\%) {
    my $ref_opts = shift();

    #^^^^^^^^^^^^
    # FIXME:  Only load the HTML::TableExtract package if required, and then,
    # only once.  Prolly should do that in processConfigFile().
    #vvvvvvvvvvvv

    my %ctorOpts = ('debug' => ($_DebugLoggingIsActive > 1) );
    if (exists($ref_opts->{'Column_exprs'})) {
        $ctorOpts{'headers'} = $ref_opts->{'Column_exprs'};
    }
    if (exists($ref_opts->{'Depth'})) {
        $ctorOpts{'depth'} = $ref_opts->{'Depth'};
    }
    if (exists($ref_opts->{'PositionInLayer'})) {
        $ctorOpts{'count'} = $ref_opts->{'PositionInLayer'};
    }

    my @ignoreThese = qw(style script);
    if (exists($ref_opts->{'IgnoreTags'})) {
        @ignoreThese = @{$ref_opts->{'IgnoreTags'}};
    }

    my $tblParser = HTML::TableExtract->new(%ctorOpts);
    $tblParser->empty_element_tags(1);
    $tblParser->ignore_elements(@ignoreThese);

    return $tblParser;
}


sub getClearlyDefinedHeaders($\@) {
    my $tblObj = shift();
    my $ref_hdrs = shift();

    my $colIdx = 0;
    foreach my $h ($tblObj->hrow()) {
        unless (!defined($h) ||  ($h =~ m/^\s*$/)) {
            $h = "idx_";
            $h .= $colIdx;
            ++$colIdx;
        }
        push(@$ref_hdrs, $h);
    }
}


sub parseTables_grid($\%\%) {
    my $parser = shift();
    my $ref_opts = shift();
    my $ref_results = shift();


    # Grab all of the desired rows.
    my @allHeaders = ();
    my @slice;
    foreach my $table ($parser->tables()) {
        next unless (defined($table));

        # Don't include the first column in the slice.
        @slice = grep($_, $table->column_map());
        foreach my $ref_row ($table->rows()) {
            study $ref_row->[0];
            next unless ($ref_row->[0] =~ m/$ref_opts->{'_Row_re_'}/o);

            push(@allHeaders, $ref_row->[0]);
            $ref_results->{$ref_row->[0]} = [@$ref_row[@slice]];
        }
    }

    # Now, put the headers into the order requested in the config file.
    $ref_results->{'_Headers_InOrder_'} = [];
    foreach my $re (@{$ref_opts->{'Row_exprs'}}) {
        push( @{$ref_results->{'_Headers_InOrder_'}},
              grep(m/(?:$re)/, @allHeaders) );
    }
}


sub parseTables_rowMajor($\%\%) {
    my $parser = shift();
    my $ref_opts = shift();
    my $ref_results = shift();

    return unless ( exists($ref_opts->{'Row_exprs'}) &&
                    scalar($ref_opts->{'Row_exprs'}) );

    # Grab all of the desired rows.
    my @allHeaders = ();
    foreach my $table ($parser->tables()) {
        next unless (defined($table));

        foreach my $ref_row ($table->rows()) {
            study $ref_row->[0];
            next unless ($ref_row->[0] =~ m/$ref_opts->{'_Row_re_'}/o);

            push(@allHeaders, $ref_row->[0]);
            $ref_results->{$ref_row->[0]}
                = $ref_row->[$ref_opts->{'_KeepColumn_'}];
        }
    }

    # Now, put the headers into the order requested in the config file.
    $ref_results->{'_Headers_InOrder_'} = [];
    foreach my $re (@{$ref_opts->{'Row_exprs'}}) {
        push( @{$ref_results->{'_Headers_InOrder_'}},
              grep(m/(?:$re)/, @allHeaders) );
    }
}


sub parseTables_columnMajor($\%\%) {
    my $parser = shift();
    my $ref_opts = shift();
    my $ref_results = shift();

    # This is the easiest of the table-parsing operations.
    my @allHeaders = ();

    foreach my $table ($parser->tables()) {
        next unless (defined($table));

        # Get the column headers, replacing any blank or missing headers with
        # a constructed one.
        my @headers;
        getClearlyDefinedHeaders($table, @headers);

        if (scalar(@headers)) {
            @$ref_results{@headers} = $table->row($ref_opts->{'KeepIdx'});
            push(@allHeaders, @headers);
        }
    }

    $ref_results->{'_Headers_InOrder_'} = \@allHeaders;
}


sub parse_statsPage($\%\%\%) {
    my $how = shift();
    my $ref_options = shift();
    my $ref_auth = shift();
    my $ref_statsMap = shift();

    # "Preparse" the web page.  I've found that HTML::TableExtract doesn't
    # like the raw HTML.
    my @content;
    read_and_clean_webpage($how, %$ref_options, %$ref_auth, @content);

    if (exists($ref_options->{'Table'}) && defined($ref_options->{'Table'}))
    {

        my $ref_tblOpts = $ref_options->{'Table'};
        my $teParser = createTableParser(%$ref_tblOpts);
        $teParser->parse(join("\n",@content)."\n");
        if ( exists($ref_tblOpts->{'Column_exprs'}) &&
             exists($ref_tblOpts->{'Row_exprs'}) )
        {
            parseTables_grid($teParser, %$ref_tblOpts, %$ref_statsMap);
        } elsif(exists($ref_tblOpts->{'Column_exprs'})){
            parseTables_columnMajor($teParser, %$ref_tblOpts, %$ref_statsMap);
        } else {
            parseTables_rowMajor($teParser, %$ref_tblOpts, %$ref_statsMap);
        }

        # Adjust the stats so that they're all integers.
        if (exists($ref_tblOpts->{'AdjustUnits'})) {
            my $idx = 0;
            foreach my $k (@{$ref_statsMap->{'_Headers_InOrder_'}}) {
                $ref_statsMap->{$k} *= $ref_tblOpts->{'AdjustUnits'}[$idx];
                ++$idx;
            }
        }

    } elsif (0) {

        my $tmp;

    } # else:  Do nothing.
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
        if ($options{'Syslog'}{'Url'} ne "") {
            printDbg("Reading DSL modem log.\n");

            parse_syslog($_GetURLVia, %{$options{'Syslog'}}, %auth,
                         @updatedDslState);
            adjustBorkedTimestamps(@updatedDslState, $inDST,
                                   $options{'ModemAdjustsForDST'},
                                   $options{'ExtraTimeOffset'},
                                   $options{'Syslog'}{'_strftime_Format_'});
            removeOldEventsAndAdjust(@updatedDslState,
                                     $ref_lastEvent->[$c_tsIdx],
                                     $ref_lastEvent->[$c_nDropsIdx]);
            resetStaleDropCounts(@updatedDslState, $now, @$ref_lastEvent,
                                 $options{'Syslog'}{'_strftime_Format_'});

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
                       $options{'MRTG'}{'_Data_'},
                       $options{'MRTG'}{'_Updated_Data_'});

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


#----------
# Actions
#----------


sub checkNow_and_exit(\%\%) {
    my %options = %{shift()};
    my %auth = %{shift()};


    if ($options{'Stats'}{'Url'} ne "") {
        print "DSL Modem Statistics:\n";
        print "---------------------\n";
        my %dslStats = ();
        parse_statsPage($_GetURLVia, %{$options{'Stats'}}, %auth, %dslStats);
        foreach my $k (@{$dslStats{'_Headers_InOrder_'}}) {
            print " "x4, $k, " == ";
            if (ref($dslStats{$k})) {
                print "(", join(", ", @{$dslStats{$k}}), ") \n";
            } else {
                print $dslStats{$k}," \n";
            }
        }
        print "\n";
    }

    if ($options{'Syslog'}{'Url'} ne "") {

        my @recentState = ();
        my $inDST;
        my $dummy;
        init_DST_vars($inDST, $dummy);
        print "===== Current DSL Modem Syslog: =====\n\n";
        parse_syslog($_GetURLVia, %{$options{'Syslog'}},
                     %auth, @recentState);
        adjustBorkedTimestamps(@recentState, $inDST,
                               $options{'ModemAdjustsForDST'},
                               $options{'ExtraTimeOffset'},
                               $options{'Syslog'}{"_strftime_Format_"});
        foreach my $ref_event (@recentState) {
            printEvent(\*STDOUT, @$ref_event);
        }

    }

    exit 0;
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
    checkNow_and_exit(%options, %auth);

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
