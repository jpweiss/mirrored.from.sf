#!/usr/bin/perl
#
# Copyright (C) 2002-2012 by John P. Weiss
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


package jpwTools;
require 5;
use strict;

BEGIN {
    use Exporter ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # if using RCS/CVS, this may be preferred
    $VERSION = do { my @r = (q$Revision: 1401 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

    @ISA         = qw(Exporter);

    # Default exports.
    @EXPORT = qw(dbgprint check_syscmd_status do_error
                 openPipeDie closePipeDie failedOpenDie
                 datestamp datetime_now
                 const_array uniq select_sample
                 key_not_set push_subarray
                 invert_hash pivot_hash
                 rename_keys transform_keys lc_keys uc_keys
                 asymm_diff circular_shift circular_pop
                 stats stats_gaussian
                 set_seed random_indices randomize_array random_keys
                 get_files_from_dirs
                 print_hash print_array print_dump
                 fprint_hash fprint_array
                 cmpVersionNumberLists
                 create_regexp_group non_overlapping
                 not_empty set_array_if_nonempty set_scalar_if_nonempty
                 validate_options read_options);
    # Permissable exports.
    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK = qw($_Verbose $_UnitTest);

    # Tagged groups of exports; 'perldoc Exporter' for details.
    %EXPORT_TAGS = (all => [@EXPORT, @EXPORT_OK]);
}
our @EXPORT_OK;

# Other Imported Packages/requirements.
use Carp;
use Data::Dumper;
use List::Util qw(shuffle);
use File::Spec;


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


my @_RecursiveRegexpGrouper_Stack = ();
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Indent = 1;
# None


############
#
# Exported Functions
#
############


sub dbgprint($@) {
    my $lvl = shift();

    # No more args?  Nothing to do.
    return unless(scalar(@_));

    unless ($lvl > 0) {
        $lvl = 1;
    }
    my $prefix = '#' x $lvl;
    $prefix .= 'DBG';
    $prefix .= '#' x $lvl;

    my $prefixNextLvl = '#';
    $prefixNextLvl .= $prefix;
    $prefixNextLvl .= '#';

    $prefix .= ' ';
    $prefixNextLvl .= ' ';

    # Keep track of where the prefix was last time we printed it.
    my $lastOut_startsWithPrefix = 0;

    # Begin with the prefix ... unless the first element is one of our special
    # ones.
    unless ( (ref($_[0]) eq 'ARRAY') && (scalar(@{$_[0]}) > 1) &&
             defined($_[0][0]) && defined($_[0][1]) )
    {
        print STDERR ("\r", $prefix);
        $lastOut_startsWithPrefix = 1;
    }

    # Can't use a for-loop, since we need to know when we're on the last
    # element.
    while (scalar(@_))
    {
        # Yes, this IS needed
        my $arg = shift();

        # Validation checks for the special array
        my $isArrayrefArg=0;
        my $badArg_errmsg=undef;
        if ((ref($arg) ne '') && (ref($arg) ne 'ARRAY')) {
            $badArg_errmsg="arg passed with type '".ref($arg)."'";
        } elsif (ref($arg) eq 'ARRAY') {
            $isArrayrefArg = 1;
            if (!(scalar(@$arg) && defined($arg->[0]))) {
                $badArg_errmsg="arrayref arg empty or missing first element";
            } elsif (!((scalar(@$arg) > 1) && defined($arg->[1]))) {
                $badArg_errmsg="arrayref arg missing second element";
            } elsif ( (ref($arg->[1]) ne 'ARRAY') &&
                      (ref($arg->[1]) ne 'HASH') ) {
                $badArg_errmsg="arrayref arg's second element must be ".
                    "a reference to the hash or array to print";
            }
        }
        if (defined($badArg_errmsg)) {
            # Declared 'local' so that they return to their original values
            # outside of this block.  {Not that it matters when we're calling
            # 'croak()', but it's a good habit to get into.}
            local %Carp::CarpInternal;
            local $Carp::Verbose;
            ++$Carp::CarpInternal{jpwTools};
            $Carp::Verbose = ($_Verbose || $_UnitTest);
            croak('dbgprint():  "'.$badArg_errmsg.'"');
        }

        if ($isArrayrefArg) {
            # We have the special array.  Just invoke print_dump on it (which
            # will figure out whether or not it's an array
            if ($lastOut_startsWithPrefix) {
                print STDERR ("\n");
            } else {
                print STDERR ("\n", $prefix, "\n");
            }
            print_dump(\*STDERR,
                       $arg->[0],
                       $arg->[1],
                       '^',
                       $prefixNextLvl);
            print STDERR ($prefix, "\n");

            if (scalar(@_)) {
                # Only print this if there's more to do.
                print STDERR ($prefix);
            }
            $lastOut_startsWithPrefix = 1;
        }
        else
        {
            # Handle as string.

            # Don't prefix every newline; ignore any blank lines at the end of
            # the last string arg.
            if ( ( scalar(@_) && ($arg =~ m/\n/) )
                 ||
                 ($arg =~ m/\n+[^\n]/) )
            {
                $lastOut_startsWithPrefix = m/\n$/;
                $arg =~ s/\n/\n$prefix/g;
            }

            print STDERR ($arg);
        }
    }
}


## This fails at compile time if 'use constant DEBUG' doesn't precede the
## 'use'-statement for this package.  So, we disable this.
##
#sub ifdbgprint($@) {
#    if (::DEBUG) {
#        my $lvl = shift();
#        dbgprint($lvl, @_);
#    }
#}


sub check_syscmd_status {
    my $laststat=$?;
    my $lastErrmsg="$!";
    my $exitVal = ($laststat >> 8);
    my $signal = ($laststat & 0x7F);
    my $abortOnError = 1;
    my $noStacktrace = 0;
    my $whatHappened="Command failed";

    # Return %Carp::CarpInternal and $Carp::Verbose to their original states
    # if there's no error.
    local %Carp::CarpInternal;
    local $Carp::Verbose;
    ++$Carp::CarpInternal{jpwTools};
    $Carp::Verbose = (($_Verbose > 3) || $_UnitTest);

    my $ref_ignoreList = undef;
    if (ref($_[0]) eq "ARRAY") {
        $ref_ignoreList = shift();
    }

    if (ref($_[0]) eq "HASH") {
        my %flags = %{shift()};

        # In case this was called from a wrapper routine.
        if (defined($flags{"laststat"})) {
            $laststat = $flags{"laststat"};
            $exitVal = ($laststat >> 8);
            $signal = ($laststat & 0x7F);
        } elsif (defined($flags{"exitval"})) {
            $exitVal = $flags{"exitval"};
            $laststat = $exitVal;
            $signal = 0;
        }


        if (defined($flags{"no_stacktrace"})) {
            $noStacktrace = $flags{"no_stacktrace"};
        }

        if (defined($flags{"ignore"})) {
            if (ref($flags{"ignore"}) eq "ARRAY") {
                $ref_ignoreList = $flags{"ignore"};
            }
        }

        # Warn/Abort flags (mutually-exclusive)
        if (defined($flags{"warn"})) {
            if ($flags{"warn"}) {
                $abortOnError = 0;
            }
        } elsif (defined($flags{"abort"})) {
            $abortOnError = $flags{"abort"};
        }

        # open/close flags (mutually-exclusive)
        if (defined($flags{"close_pipe"})) {
            if ($flags{"close_pipe"}) {
                $whatHappened = "Error while closing pipe";
            }
        } elsif (defined($flags{"open_pipe"})) {
            if ($flags{"open_pipe"}) {
                $whatHappened = "Failed to open pipe";
            }
        } elsif (defined($flags{"open_file"})) {
            $whatHappened = "Failed to open file for ";
            $whatHappened .= $flags{"open_file"};
            # No signal or exit val when opening a file, so disable
            # their respective error messages.
            $exitVal = 0;
            $signal = 0;
        }
    }

    if (defined($ref_ignoreList)) {
        my %ignore = ();
        my @ones = (1) x scalar(@$ref_ignoreList);
        @ignore{ @$ref_ignoreList } = @ones;
        $ignore{0} = 1;
        return 0 if (exists($ignore{$exitVal}) && $ignore{$exitVal});

        # FIXME:  This may no longer be needed.
        my $errMsg="";
        if (0) {
            $errMsg .=
                "WARNING: Command \"@_\" exited with status $exitVal.\n";
            unless ($lastErrmsg eq '') {
               $errMsg .= "  Reason: \"$lastErrmsg\".\n";
            }

            if ($noStacktrace) {
                print STDERR ($errMsg);
            } else {
                carp($errMsg);
            }

            return $exitVal;
        }
    }

    if ($laststat == 0) {
        # Everything's A-okay!
        return 0;
    }

    my $errMsg="$whatHappened:  \"@_\";\n";
    unless ($lastErrmsg eq '') {
        $errMsg .= "Reason: \"$lastErrmsg\".\n";
    }
    unless ($signal == 0) {
        $errMsg .= "Exited on signal $signal.  ";
    }
    unless ($exitVal == 0) {
        $errMsg .= "Exit status: $exitVal.";
    }
    $errMsg .= "\n";

    if ($noStacktrace) {
        print STDERR ($errMsg);
    } else {
        carp($errMsg);
    }

    if ($abortOnError) {
        print "\nAborting...\n";
        exit $laststat;
    } #else
    return $laststat;
}


sub closePipeDie($) {
    my $exitstat=$?;
    # Because we're closing a pipe, $? will be zero iff the pipe command
    # exited with status==0.  So, no need to change what we pass to
    # 'laststat'.
    check_syscmd_status({'close_pipe' => 1, 'laststat' => $exitstat}, @_);
}


sub openPipeDie($) {
    my $exitstat=$?;
    # Because we're closing a pipe, $? may or may not be zero if the pipe
    # command fails at startup.  Since this function is guaranteed to die, set
    # $exitstat to 13 (== SIGPIPE).
    $exitstat = 13 unless ($exitstat);
    check_syscmd_status({'open_pipe' => 1, 'laststat' => $exitstat}, @_);
}


sub failedOpenDie($$) {
    my $fname = shift();
    my $what = shift();
    # Since this function is guaranteed to die, set 'laststat' to true.
    check_syscmd_status({'open_file' => $what,
                         'laststat' => 1}, $fname);
}


sub do_error($$$) {
    my $doFile = shift;
    my $doError = shift;
    my $parseError = shift;

    if (($parseError eq "") && ($doError eq "")) {
        return "Error:  Runtime error evaluating \"".
            $doFile."\".\n";
    } #else
    my $mesg = "";
    if ($doError ne "") {
        $mesg = "Error: 'do \"$doFile\"': $doError\n";
    }
    if ($parseError ne "") {
        $mesg .= "Error while parsing file \"$doFile\": $parseError\n";
    }
    return $mesg;
}


sub datetime_now() {
    my @timeinfo = localtime;
    # month == $timeinfo[4] + 1
    ++$timeinfo[4];
    # year == $timeinfo[5] + 1900
    $timeinfo[5] += 1900;

    # Return in the order: YYYY, MM, DD, HH24, MI, SEC
    return ($timeinfo[5], $timeinfo[4], $timeinfo[3],
            $timeinfo[2], $timeinfo[1], $timeinfo[0]);
}


sub datestamp() {
    return sprintf("%4d%02d%02d", datetime_now());
}


sub const_array($$) {
    my ($cval, $len) = @_;
    return ( $cval ) x $len;
}


# Using a hash as a set:
#
#     my %set;
#     @set{@elements} = ();
#
# ... Then use "exists" to test for membership (instead of using
# "defined").
#
# If, for some reason, you want or need to use "defined()" [i.e. check that
# the hash contains a key *and* that the key maps to something other than
# undef], use this idiom:
#
#    @set{@elements} = (1 .. scalar(@elements));
#
# ...or:
#
#    @set{@elements} = grep { 1; } (1 .. scalar(@elements));
#


sub uniq {
    my %seen =();

    # This works, is fast, but doesn't preserve the original list's order.
    #@seen{@_} = ();
    #return keys(%seen);

    # This is also fast AND preserves the original list's order, but is a bit
    # harder to read.
    return grep({ !$seen{$_}++ } @_);
}


sub key_not_set(\%$) {
    my $ref_hash = shift();
    my $key = shift();

    return (!exists($ref_hash->{$key}) || !defined($ref_hash->{$key}));
}


sub push_subarray(\%$;@) {
    my $ref_hash = shift();
    my $key = shift();

    if (key_not_set(%$ref_hash, $key)) {
        my @valArray = @_;
        $ref_hash->{$key} = \@valArray;
    } elsif (scalar(@_) && (ref($ref_hash->{$key}) eq "ARRAY")) {
        push(@{$ref_hash->{$key}}, @_);
    }
}


# How to do a set union, intersection, and difference.
#
##
#sub set_ops {
#    @union = @intersection = @difference = ();
#    %count = ();
#    foreach $element (@array1, @array2) { $count{$element}++ }
#    foreach $element (keys %count) {
#        push @union, $element;
#        push @{ $count{$element} > 1 ? \@intersection : \@difference },
#             $element;
#    }
#}


sub select_sample($\@;$) {
    my $nSelected = shift();
    my $ref_data = shift();
    my $alwaysIncludeLast = (scalar(@_) ? shift() : 0);

    my $lastDataIdx = $#{$ref_data};

    # Determine the "slice" of the data array to keep.
    my $selectionStep = $lastDataIdx/$nSelected;
    # Note the use of sprintf for rounding; see `perldoc -f int`.
    my @slice = map({ sprintf("%.0f", $_*$selectionStep)
                    } (0 .. ($nSelected-1)));

    if ($#slice > $lastDataIdx) {
            # The caller wants to report more items than we have.
            # => Show them all.
        return @$ref_data;
    } #else

    if ($slice[$#slice] > $lastDataIdx) {
        # Oops!  Rounding error ... the last index in @slice
        # is outside of @$ref_data.  Prune it.
        pop(@slice);
    }
    if ( $alwaysIncludeLast && ($slice[$#slice] < $lastDataIdx) ) {
        # Missing the last item in the list, but the caller wants to include
        # it.
        push(@slice, $lastDataIdx);
    }

    return @{$ref_data}[@slice];
}


sub invert_hash(\%;\%\@) {
    my $ref_h = shift();
    my $ref_inv = shift();
    my $ref_nonUnique = shift();

    my $returnInverse = 0;
    unless (defined($ref_inv)) {
        $ref_inv = { };
        $returnInverse = 1;
    }

    # While 'reverse %hash' will invert %hash, it won't work if multiple keys
    # map to the same value.

    while(my ($k, $v) = each(%$ref_h)) {
        next if(ref($v)); # Must be scalar
        if (exists($ref_inv->{$v})) {
            unless (ref($ref_inv->{$v}) eq 'ARRAY') {
                $ref_inv->{$v} = [ $ref_inv->{$v} ];
            }
            push(@{$ref_inv->{$v}}, $k);
        } else {
            $ref_inv->{$v} = $k;
        }
    }

    if (defined($ref_nonUnique)) {
        @$ref_nonUnique = grep({ ref($ref_inv->{$_}) } keys(%$ref_inv));
    }

    if ($returnInverse) {
        return %$ref_inv;
    }
}


sub pivot_hash(\%$;$) {
    my $ref_h = shift();
    my $idx = shift();
    my $ignoreNonPivotable = (scalar(@_) ? shift() : 0);

    my @oldKeys = keys(%$ref_h);

    # Error checking:  Make sure that...
    # - Every value is an arrayref;
    # - Each arrayref has something defined at $idx;
    # - All of those elements are scalar values.
    my @pivotableKeys = grep({ ( (ref($ref_h->{$_}) eq 'ARRAY')
                                 && exists($ref_h->{$_}[$idx])
                                 && defined($ref_h->{$_}[$idx])
                                 && !ref($ref_h->{$_}[$idx]) )
                             } @oldKeys);
    return 0 unless ($ignoreNonPivotable ||
                     (scalar(@oldKeys) == scalar(@pivotableKeys)));

    # All of the potential new keys MUST be unique, or we will end up deleting
    # elements from the hash.  Not Good.
    my %new2old = map({ $ref_h->{$_}[$idx] => $_ } @pivotableKeys);
    my @newKeys = keys(%new2old);
    my $nNewKeys = scalar(@newKeys);
    return 0 unless ($nNewKeys == scalar(@pivotableKeys));

    #
    # This is a faster operation, but will use much more memory than
    # pivotting one element at a time.
    map({ $ref_h->{$_} = $ref_h->{$new2old{$_}};
          $ref_h->{$_}[$idx] = $new2old{$_}; } @newKeys);

    delete(@{$ref_h}{@pivotableKeys});
    return 1;
}


sub transform_keys(\%\&) {
    my $ref_hash = shift;
    my $subref_transform = shift;

    map({ my $newKey = &$subref_transform($_);
          unless ($newKey eq $_) {
              $ref_hash->{$newKey} = $ref_hash->{$_};
              delete $ref_hash->{$_};
          }
        } keys(%$ref_hash));
}


sub lc_keys(\%) {
    my $ref_hash = shift;

    # Note: "lc" (and "uc") are not true "functions" in the "main::"
    # namespace.  They are actually treated as language tokens at compile
    # time.  So, we can't take a reference to them.
    # We must, instead, resort to this trick.
    sub lc_kludge { return lc $_[0]; };
    transform_keys(%$ref_hash, &lc_kludge);
}


sub uc_keys(\%) {
    my $ref_hash = shift;

    # Note: See comment in "lc_keys()" for why we must resort to this trick.
    sub uc_kludge{ return uc $_[0]; };
    transform_keys(%$ref_hash, &uc_kludge);
}


sub rename_keys(\%\%) {
    my $ref_hash = shift;
    my $ref_old2new_keys = shift;

    foreach my $oldKey (grep({defined($ref_hash->{$_})}
                             keys(%$ref_old2new_keys)))
    {
        $ref_hash->{$ref_old2new_keys->{$oldKey}} = $ref_hash->{$oldKey};
        delete $ref_hash->{$oldKey};
    }
}


sub circular_shift(\@;$) {
    my $ref_array = shift;
    if (scalar(@_)) {
        my $count = shift;
        my @vals = splice @{$ref_array}, 0, $count;
        push @{$ref_array}, @vals;
        return @vals;
    }
    # else
    my $val = shift @{$ref_array};
    push @{$ref_array}, $val;
    return $val;
}


sub circular_pop(\@;$) {
    my $ref_array = shift;
    if (scalar(@_)) {
        my $count = shift;
        my @vals = splice @{$ref_array}, (scalar($#{$ref_array})-$count);
        unshift @{$ref_array}, @vals;
        return @vals;
    }
    # else
    my $val = pop @{$ref_array};
    unshift @{$ref_array}, $val;
    return $val;
}


sub asymm_diff {
    my ($ref_set1,
        $ref_set2) = @_;
    my $set1_type=ref($ref_set1);
    my $set2_type=ref($ref_set2);
    unless ( (($set1_type eq "HASH") ||
              ($set1_type eq "ARRAY")) &&
             (($set2_type eq "HASH") ||
              ($set2_type eq "ARRAY")) ) {
        die "While calling jpwTools::asymm_diff()\n".
            "Syntax Error: First two args must be ref to hash or array.";
    }
    my $ref_delslice = ();
    my %tmphash = ();

    # "Convert" the second set to an array, if necessary.
    if ($set2_type eq "HASH") {
        $ref_delslice = [ keys %$ref_set2 ];
    } else {
        $ref_delslice = $ref_set2;
    }

    # 1. Copy the first set to a temporary hash.
    # 2. Delete the slice matching the second set.
    # 3. Return the results in the proper format.
    # Don't forget that this delete should be an array context.  Otherwise,
    # only the first element in the slice gets deleted.
    if ($set1_type eq "HASH") {
        %tmphash = %$ref_set1;
        delete @tmphash{@{$ref_delslice}};
        return %tmphash;
    } else {
        @tmphash{@{$ref_set1}} = map 1, @$ref_set1;
        delete @tmphash{@{$ref_delslice}};
        return sort(keys(%tmphash));
    }
}


sub not_empty($) {
    my $arg = shift;
    unless (defined($arg)) {
        return 0;
    }
    my $reftype=ref($arg);
    return ( (($reftype eq "ARRAY") && scalar(@$arg))
             ||
             (($reftype eq "HASH") && scalar(%$arg))
             ||
             (($reftype eq "SCALAR") && length($$arg))
             ||
             (($reftype eq "") && length($arg))
             ||
             0);
}

sub set_scalar_if_nonempty(\$\%$) {
    my ($svar_ref,
        $map_ref,
        $keyname) = @_;
    if (not_empty($map_ref->{$keyname}))
    {
        $$svar_ref = $map_ref->{$keyname};
    }
}


sub set_array_if_nonempty(\@\%$) {
    my ($avar_ref,
        $map_ref,
        $keyname) = @_;
    if (not_empty($map_ref->{$keyname}))
    {
        @{$avar_ref} = @{$map_ref->{$keyname}};
    }
}


sub stats(\@;$) {
    # According to §8.5 of "Numerical Recipies," a selection algorithm (find
    # the K^th largest value in an array) runs with O(N) time.  Thus,
    # computing the median, dispersion about the median, min, and max take
    # O(4N) (the min & max can be searched for together in a separate loop).
    # Since sorting takes O(N log N), the selection algorithm will perform
    # better when N > 10^4.
    #
    # Note, however that selection algorithms rearrange the original array.
    #
    # For the Perl versions of this method, I'll use sort.  For other
    # programming languages, especially C++, using a selection algorithm may
    # make more sense.

    my $ref_vals = shift;
    my $confidence = "";
    if (scalar(@_)) {
        $confidence = shift;
    }
    my @vals = sort {$a <=> $b;} (@{$ref_vals});
    my $N = scalar(@vals);

    # For small N, the median & dispersion are predetermined.  So, just return
    # those
    if ($N < 4) {
        if ($N == 0) { return (0, 0, 0, 0, 0); }
        if ($N == 1) { return ($vals[0],
                               $vals[0], $vals[0], $vals[0],
                               $vals[0]); }
        if ($N == 2) { return ($vals[0],
                               $vals[0], 0.5*($vals[0]+$vals[0]), $vals[1],
                               $vals[1]); }
    }

    my $median = $vals[$N/2];
    my $k_disp_lo;
    my $k_disp_hi;

    # We will do as "Numerical Recipies" does (see comment at the start of
    # §8.5), and be pedantic for N <= 100.
    if ( ($N <= 100) && (($N % 2) == 0) ) {
        $median += $vals[int($N/2) + 1];
        $median /= 2.0;
    }

    if ($confidence =~ m/^[-+]?0\.\d+/) {
        my $half_interval = 0.5 * abs($confidence);
        $k_disp_lo = int( (0.5 - $half_interval) * $N );
        $k_disp_hi = int( (0.5 + $half_interval) * $N );
    }
    elsif ($confidence =~ m/^q/) {
        # Interquartile ranges.
        $k_disp_lo = int( 0.25 * $N );
        $k_disp_hi = int( 0.75 * $N );
    }
    elsif ($confidence =~ m/^3s/) {
        # 3sigma: 0.9973
        $k_disp_lo = int( 0.00135 * $N );
        $k_disp_hi = int( 0.99865 * $N );
    }
    elsif ($confidence =~ m/^2s/) {
        # 2sigma: 0.9545
        $k_disp_lo = int( 0.02275 * $N );
        $k_disp_hi = int( 0.97725 * $N );
    }
    else {
        # Default:
        # sigma: 0.6827
        $k_disp_lo = int( 0.15865 * $N );
        $k_disp_hi = int( 0.84135 * $N );
    }

    return ($vals[0],
            $vals[$k_disp_lo], $median, $vals[$k_disp_hi],
            $vals[$#vals]);
}


sub stats_gaussian(\@) {
    my $ref_vals = shift;
    my $n = scalar(@{$ref_vals});

    my $avg=0.0;
    foreach my $val (@{$ref_vals}) { $avg += $val; }
    $avg /= $n;

    my $avg_dev=0.0;
    #my $sum_anom=0.0;
    my $var=0.0;
    my $skew=0.0;
    my $kurt=0.0;
    foreach my $val (@{$ref_vals}) {
        my $anom = ($val - $avg);
        #$sum_anom += $anom;
        $avg_dev += abs($anom);

        my $anom_sq = $anom*$anom;
        $var += $anom_sq;
        $skew += $anom_sq*$anom;
        $kurt += $anom_sq*$anom_sq;
    }
    # Compute Avg. Deviation
    $avg_dev /= $n;

    # Compute the variance using the "Corrected Two-Pass Algorithm," described
    # in "Numerical Recipies," §14.1.
    #$var -= (($sum_anom*$sum_anom)/$n);
    # Note: this doesn't work; you can generate small negative numbers with
    # this.  It looks, also, like the algorithm in NR wasn't entirely correct,
    # either.
    $var /= ($n - 1.0);
    my $stddev = sqrt($var);

    # Divide the skew by sigma^3
    $skew /= ($n * $var * $stddev);

    # Divide the kurtosis by sigma^4, then adjust so that a gaussian has 0
    # kurtosis.
    $kurt /= ($n * $var * $var);
    $kurt -= 3.0;

    return ($avg, $var, $skew, $kurt, $stddev, $avg_dev);
}


sub set_seed(;$) {
    my $seed;
    if (scalar(@_)) {
        $seed = int(shift());
    } else {
        # Perl's "srand" function does not return the seed, making Monte Carlo
        # difficult.  So, to remedy that, we call srand explicitly without any
        # seed, then generate the first random integer as the new seed.
        #
        # So, it's not great, but it'll do for Monte Carlo simulation.
        srand();
        $seed = int(rand(0xFFFFFFFF));
    }
    srand($seed);
    return $seed;
}


sub randomize_array(\@) {
    my $ref_targArray = shift;
    @$ref_targArray = shuffle(@$ref_targArray);
    # This is the naive shuffle algorithm.  It also suffers from bias.
    #my $n = scalar(@$ref_targArray);
    #for (my $i=0; $i < $n; ++$i) {
    #     my $randIdx = int(rand($n));
    #     my $tmp = $ref_targArray->[$i];
    #     $ref_targArray->[$i] = $ref_targArray->[$randIdx];
    #     $ref_targArray->[$randIdx] = $tmp;
    #}
    # This is the Fisher-Yates shuffle algorithm.  No bias here.
#     my $n = scalar(@$ref_targArray);
#     for (my $i=$n-1; $i > 0; --$i) {
#         my $randIdx = int(rand($i+1));
#         my $tmp = $ref_targArray->[$i];
#         $ref_targArray->[$i] = $ref_targArray->[$randIdx];
#         $ref_targArray->[$randIdx] = $tmp;
#     }
}


sub random_indices($;\@) {
    my $n = shift;
    my $ref_idxs = [];;
    my $returnArray = 1;
    if (scalar(@_)) {
        $ref_idxs = shift;
        $returnArray = 0;
    }
    @$ref_idxs = (0 .. ($n - 1));
    if ($returnArray) {
        return shuffle(@$ref_idxs);
    } # else
    randomize_array(@$ref_idxs);
}


sub random_keys(\%) {
    my $ref_hash = shift;
    my @keyList = sort(keys(%$ref_hash));
    return shuffle(@keyList);
}


sub get_files_from_dirs(\%$@) {
    my $ref_fileMap = shift;
    my $match_re = shift;

    # Runtime-enforcement of function signature.  Mimicks the compile-time
    # error message.
    unless (scalar(@_)) {
        my ($callerPkg, $callerFile, $callerLine) = caller();
        die("Not enough arguments for jpwTools::get_files_from_dirs() ",
            "at ", $callerFile, ", line ", $callerLine, ".\n");
    }

    my $nErrs = 0;
    my $homeDir = $ENV{"HOME"};

    foreach my $orig_dir (@_) {
        # Skip "empty" elements.
        next if ($orig_dir =~ m/^\s*$/);

        # Cleanup the directories:
        # - Make canonical & convert to an absolute path (including removal of
        #   redundant path separators or '.' dirs).
        # - Convert "~" to the home directory.
        my $dir = File::Spec->rel2abs(File::Spec->canonpath($orig_dir));
        $dir =~ s|^~|$homeDir|o;
        if ($dir =~ m|\.\.|) {
            # Do a runtime "use":
            require Cwd;
            import Cwd qw(abs_path);
            $dir = abs_path($dir);
        }

        # Make sure it's a real directory.
        unless ( (-d $dir) || (-d "$dir/.")) {
            if ($_Verbose) {
                print STDERR ("get_files_from_dirs():  Not a directory:\n",
                              "\t\"", $dir, "\"\n\tIgnoring...\n");
            }
            next;
        }

        unless (opendir(DH, $dir)) {
            my $errmsg="\"$!\"";
            if ($_Verbose) {
                print STDERR ("get_files_from_dirs():  Failed to open ",
                              "directory:\n\t\"", $dir, "\"\n\tReason:  ",
                              $errmsg, "\n\tSkipping...\n");
            }
            ++$nErrs;
            next;
        }
        for ( my $f=readdir(DH); defined($f); $f=readdir(DH) ) {
            next if (($f eq "./") || ($f eq ".") || ($f eq ".."));
            if ($f =~ m/^\./o) {
                $f =~ s|^\./||;
            }
            next unless ( ($match_re eq "") || ($f =~ m/$match_re/) );
            if ($_Verbose > 2) {
                print "### $f\n";
            }
            my $k = $f;
            unless ($k =~ m|^[\\/]|) {
                $k = File::Spec->catfile($dir, $f);
            }
            # Format:

            # [basename, dirname, extension, basename_stem, type, orig_dir]

            # 'basename_stem' is 'basename' with 'extension' removed.  'type'
            # is "" for regular files, 'd' for dirs, 'L' for symlinks, and
            # another char for other types (see the POD).  'orig_dir' is the
            # name of the original directory passed to this function.
            $ref_fileMap->{$k} = [$f, $dir, '', $f, '', $orig_dir];

            # Crude filename decomposition:  recognizes only '.' as the
            # extension separator.
            if ($ref_fileMap->{$k}[0] =~ m|^(.+)\.([^.]+)$|) {
                $ref_fileMap->{$k}[2] = $2;
                $ref_fileMap->{$k}[3] = $1;
            }
            # Stat once & reuse result via '_' in the file tests.  Note that
            # we use 'lstat' in case we're looking at a broken symlink.
            lstat($k);
            if (-d _) {
                $ref_fileMap->{$k}[4] = 'd';
            } elsif (-l _) {
                $ref_fileMap->{$k}[4] = 'L';
            } elsif (-b _) {
                $ref_fileMap->{$k}[4] = 'b';
            } elsif (-c _) {
                $ref_fileMap->{$k}[4] = 'c';
            } elsif (-p _) {
                $ref_fileMap->{$k}[4] = 'p';
            } elsif (-S _) {
                $ref_fileMap->{$k}[4] = 's';
            } elsif (! -f _) {
                $ref_fileMap->{$k}[4] = '?';
            }
        }
        closedir DH;
    }

    return !$nErrs;
}


sub print_dump($;@) {
    my $ref_var = shift;
    my $fh = undef();
    if (ref($ref_var) eq "GLOB") {
        unless(scalar(@_)) {
            die("print_dump():  Must have 2 or more args when the first arg ".
                "is a GLOB.\n");
        }
        $fh = $ref_var;
        $ref_var = shift;
    }
    my $name = "";
    if (scalar(@_) && !ref($ref_var)) {
        # 1st Arg is scalar => it's the name of the variable.  Assume the
        # var-ref is in the 2nd Arg.
        $name = $ref_var;
        $ref_var = shift;
    }

    my $output;
    if ($name eq "") {
        $output = sprintf("%s", Dumper($ref_var));
    } else {
        $output = sprintf("%s", Data::Dumper->Dump([$ref_var], ["\*$name"]));
    }
    while (scalar(@_) > 1) {
        my $oldFmt = shift;
        my $newFmt = shift;
        eval "\$output =~ s/$oldFmt/$newFmt/mg";
    }
    if (defined($fh)) {
        print $fh ($output);
    } else {
        print $output;
    }
}


sub fprint_hash(\*$\%;@) {
    my $fh = shift;
    my $name = shift;
    my $map_ref=shift;
    if ($name eq "") {
        print_dump($fh, $map_ref, @_);
    } else {
        print_dump($fh, $name, $map_ref, @_);
    }
}


sub fprint_array(\*$\@;@) {
    my $fh = shift;
    my $name = shift;
    my $list_ref=shift;
    if ($name eq "") {
        print_dump($fh, $list_ref, @_);
    } else {
        print_dump($fh, $name, $list_ref, @_);
    }
}


sub print_hash($\%;@) {
    my $name = shift;
    my $map_ref=shift;
    if ($name eq "") {
        print_dump($map_ref, @_);
    } else {
        print_dump($name, $map_ref, @_);
    }
}


sub print_array($\@;@) {
    my $name = shift;
    my $list_ref=shift;
    if ($name eq "") {
        print_dump($list_ref, @_);
    } else {
        print_dump($name, $list_ref, @_);
    }
}


sub cmpVersionNumberLists(\@\@) {
    my $ref_xl = shift;
    my $ref_yl = shift;

    while (scalar(@$ref_xl) && scalar(@$ref_yl)) {
        my $x0 = shift @$ref_xl;
        my $y0 = shift @$ref_yl;
        my $cmpstat;
        # If either piece contains non-digit characters, do a string compare.
        # Otherwise, use the numeric compare.
        if ( ($x0 =~ m/\D/) || ($y0 =~ m/\D/) ) {
            $cmpstat = ($x0 cmp $y0);
        } else {
            $cmpstat = ($x0 <=> $y0);
        }
        if ($cmpstat) {
            # These two pieces aren't equal; we're done.
            return $cmpstat;
        }
    }

    # We only reach here if $x and $y don't have the same number of pieces in
    # their version numbers.  In this case, we choose the one with more.
    return (scalar(@$ref_xl) <=> scalar(@$ref_yl));
}


sub create_regexp_group {
    # Make sure the word list is sorted, unique, and doesn't contain the "".
    my %uniqifier;
    @uniqifier{@_} = ();
    delete $uniqifier{""};
    my @words = sort(keys %uniqifier);
    undef %uniqifier;

    # Using Perl extension: Regexp operator: "(?:)" is like the regular
    # grouping operator, but doesn't save anything into the \N registers.
    @_RecursiveRegexpGrouper_Stack = (0, '(?:', 0, @words);
    return recursive_regexp_grouper();
}


sub non_overlapping {
    my @wrk = sort @_;
    if (scalar(@wrk) == 0) {
        # Nothing to do; no prune expressions.
        return @wrk;
    }
    # This isn't ideal, but it'll do for now.  Using create_regexp_group is
    # also somewhat overkill.
    my $overlap_re = '(?:';
    $overlap_re .= join "|", @wrk;
    $overlap_re .= ')';

    # Return non-overlapping element, i.e. elements that are not prefixes of
    # any other element, or those that are a minimum-sized prefix.
    return grep !m<^$overlap_re.>o, @wrk;
}


sub validate_options(\%\%;$) {
    my $ref_options = shift();
    my $ref_validator = shift();
    my $filename = shift();

    my @validation_stack = ();
    while (my ($k, $v) = each(%$ref_validator)) {
        next unless(defined($ref_options->{$k}));
        if (ref($v) eq "HASH") {
            while (my ($k2, $v2) = each(%$v)) {
                next unless(defined($ref_options->{$k}{$k2}));
                push(@validation_stack, [$k.".".$k2,
                                         ref($ref_options->{$k}{$k2}),
                                         $v2]);
            }
        } else {
            push(@validation_stack, [$k, ref($ref_options->{$k}), $v]);
        }
    }

    my $is_valid=1;
    while (scalar(@validation_stack)) {
        my ($k, $ovt, $vt) = @{pop(@validation_stack)};

        if ($ovt ne $vt) {
            if ($is_valid) {
                # Print out the header on the first error.
                if ($filename eq "") {
                    print "Error in configuration file:\n";
                } else {
                    print "Error in file \"$filename\":\n";
                }
            }
            print "\tParameter \"$k\" must be ";
            if ($vt eq "") {
                print "scalar";
            } elsif ($vt eq "ARRAY") {
                print "an array";
            } else {
                print "a ", lc($vt);
            }
            print " (not ";
            if ($ovt eq "") {
                print "scalar).\n";
            } elsif ($ovt eq "ARRAY") {
                print "an array).\n";
            } else {
                print "a ", lc($ovt), ").\n";
            }
            $is_valid = 0;
        }
    }

    die "Aborting." unless($is_valid);
}


sub read_options($;\%) {
    my $filename = shift;
    my %options=();
    my $array_option="";
    my $ref_validator = {};
    if (scalar(@_)) {
        $ref_validator = shift;
    }

    open(IN_FS, "$filename")
        or die("Unable to open file for reading: \"$filename\"\n".
               "Reason: \"$!\"\n");

    while (<IN_FS>) {
        my $line = $_;
        chomp $line; # Remove newline

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
            push @{$options{$array_option}}, $line;
            next;
        }

        # Get the option name and value, trimming whitespace on either
        # side of the delimiter characters.
        my ($optname, $val) = split /\s*[:=]\s*/, $line;

        # Special handling:
        # This is the start of an array parameter.
        if ($val eq "(") {
            $array_option=$optname;
            $options{$array_option} = [ ];
            next;
        }

        # Regular option processing
        $options{$optname} = $val;
    }
    close IN_FS;

    # Break apart our hash options.
    # Note: We only handle one-level deep.  The value must be either a scalar
    # or a hash.  Anything more complex must be split apart by the caller.
    foreach my $raw_hashopt (grep(/\./, keys(%options))) {
        $raw_hashopt =~ m/^([^.]+)\.(.*)$/;
        my $hashopt = $1;
        my $subopt= $2;
        $options{$hashopt}{$subopt} = $options{$raw_hashopt};
        delete $options{$raw_hashopt};
    }

    # And lastly, validate the options.
    validate_options(%options, %$ref_validator, $filename);

    return %options;
}


# Unit-testing stub function.
sub ut {
    exit 0;
}


############
#
# Internal Functions
#
############


sub print_hash_recurse { &print_hash; }


sub make_char_regexp {
    my @charlist = map { ord $_; } sort(@_);
    my $charsets = "";
    my $dash = "";
    my $caret = "";
    my $rbracket = "";

    my $start=-1;
    my $end=-2;
    foreach my $current (@charlist) {
        if ($current == ord("^")) { $caret = "^"; next; }
        if ($current == ord("-")) { $dash = "-"; next; }
        if ($current == ord("]")) { $rbracket = "]"; next;}

        # $range_end always equals the previous character in the list.
        if (($current-1) == $end) {
            $end = $current;
            next;
        }

        if ($end > (2+$start)) {
            $charsets .= chr($start);
            $charsets .= "-";
            $charsets .= chr($end);
        } else {
            while($end >= $start) {
                $charsets .= chr($start);
                ++$start;
            }
        }
        $start = $end = $current;
    }

    # Output final char or range.
    if($end >= $start) {
        if ($end > (2+$start)) {
            $charsets .= chr($start);
            $charsets .= "-";
            $charsets .= chr($end);
        } else {
            while($end >= $start) {
                $charsets .= chr($start);
                ++$start;
            }
        }
    }

    if (($charsets eq "") && ($rbracket eq "")) {
        return join("", "[", $dash, $caret, "]");
    }
    # else:
    return join("", "[", $rbracket, $charsets, $caret, $dash,  "]");
}


sub find_prefix {
    my @words = sort(@_);
    my $nwords = scalar(@words);
    unless ($nwords) {
        return "";
    }

    my $largest_prefix=$words[0];
    my $maxsz = length($largest_prefix);
    my $sz=1;
    my $tstprefix = "";
    my $prefix = "";
    while($sz <= $maxsz) {
        # Check the next possible match.
        $tstprefix = substr($largest_prefix, 0, $sz);
        ++$sz;
        unless ($nwords == scalar(grep(m<^$tstprefix>, @words))) {
            last;
        }
        # Set $prefix to the last successful match.
        $prefix = $tstprefix;
    }
    return $prefix;
}


sub find_suffix {
    my @words = sort(@_);
    my $nwords = scalar(@words);
    unless ($nwords) {
        return "";
    }

    my $largest_suffix=$words[0];
    my $maxsz = length($largest_suffix);
    my $sz=1;
    my $tstsuffix = "";
    my $suffix = "";
    while($sz <= $maxsz) {
        # Check the next possible match.
        $tstsuffix = substr($largest_suffix, -$sz);
        ++$sz;
        unless ($nwords == scalar(grep(m<$tstsuffix$>, @words))) {
            last;
        }
        # Set $suffix to the last successful match.
        $suffix = $tstsuffix;
    }
    return $suffix;
}


# The @_RecursiveRegexpGrouper_Stack global is a kludge around broken Perl
# recursion behavior.
sub recursive_regexp_grouper() { #($$$@) {
    my $recursionDepth = shift(@_RecursiveRegexpGrouper_Stack);
    my $group_open = shift(@_RecursiveRegexpGrouper_Stack);
    my $lax = shift(@_RecursiveRegexpGrouper_Stack);
    my @words = @_RecursiveRegexpGrouper_Stack;
    my $nwords = scalar(@words);

    if ($_Verbose) {
        print STDERR ("# recursive_regexp_grouper():  Called at depth==",
                      $recursionDepth, "\n");
    }

    unless ($nwords) {
        return "";
    }

    if ($_UnitTest) {
        print STDERR ("# recursive_regexp_grouper():  ", $nwords,
                      " \"@words\"\n");
    }

    my $group_close = "";
    my $cgrp_open = "";
    my $cgrp_close = "";
    if ($group_open ne "") { $group_close = ")"; }
    unless ($lax) {
        $cgrp_open = $group_open;
        $cgrp_close = $group_close;
    }

    if ($nwords == 1) {
        if (length($words[0]) == 1) {
            return join("", $cgrp_open, $words[0], $cgrp_close);
        } # else:
        return join("", $group_open, $words[0], $group_close);
    }

    my $patstr = "";

    # A rather obtuse way of determining if there are 2 or more one-char
    # strings present.
    my @letters = grep((length($_) == 1), @words);
    if (scalar(@letters) > 1) {
        if ($_Verbose) {
            print STDERR ("# recursive_regexp_grouper():  ",
                          " Called with single-char \"words\".\n");
        }
        my @rest = grep((length($_) != 1), @words);
        unless ($nwords == (scalar(@letters) + scalar(@rest))) {
            die "Lost elements while dividing list on length";
        }
        undef @words;
        if (scalar(@rest)) {
            if ($_Verbose) {
                print STDERR ("# recursive_regexp_grouper():  ",
                              " Grouping remaining multichar-words.\n");
            }
            $patstr .= $group_open;
            @_RecursiveRegexpGrouper_Stack = ($recursionDepth+1,
                                              "", 0, reverse(@rest));
            $patstr .= recursive_regexp_grouper();
            $patstr .=  "|";
            $patstr .= make_char_regexp(@letters);
            $patstr .= $group_close;
        } else {
            $patstr .= $cgrp_open;
            $patstr .= make_char_regexp(@letters);
            $patstr .= $cgrp_close;
        }
        return $patstr;
    }

    ## Default Behavior: list of different-length strings.

    my $prefix = find_prefix(@words);
    if ($prefix ne "") {
        # Common prefix => recurse on the suffixes.
        if ($_Verbose) {
            print STDERR ("# recursive_regexp_grouper():  ",
                          " Common prefix: \"",$prefix,
                          "\".  Grouping on suffixes.\n");
        }
        my @suffixes = ();
        foreach my $newsuf (grep m<^$prefix>, @words) {
            $newsuf =~ s<^$prefix><>;
            push @suffixes, $newsuf;
        }
        undef @words;
        $patstr .= $group_open;
        $patstr .= $prefix;
        @_RecursiveRegexpGrouper_Stack = ($recursionDepth+1,
                                          "(?:", 1, @suffixes);
        $patstr .= recursive_regexp_grouper();
        $patstr .= $group_close;
        return $patstr;
    }

    my $suffix = find_suffix(@words);
    if ($suffix ne "") {
		# Common suffix => recurse on the prefixes.
        if ($_Verbose) {
            print STDERR ("# recursive_regexp_grouper():  ",
                          " Common suffix: \"",$suffix,
                          "\".  Grouping on prefixes.\n");
        }
        my @prefixes = ();
        foreach my $newpre (grep m<$suffix$>, @words) {
            $newpre =~ s<$suffix$><>;
            push @prefixes, $newpre;
        }
        undef @words;
        $patstr .= $group_open;
        @_RecursiveRegexpGrouper_Stack = ($recursionDepth+1,
                                          "(?:", 1, @prefixes);
        $patstr .= recursive_regexp_grouper();
        $patstr .= $suffix;
        $patstr .= $group_close;
        return $patstr;
    }

    # ELSE:  Divide the list into two groups, based on common starting letter,
    # and recurse on them.
    my @half1 = ();
    my @half2 = ();
    if ($words[0] eq "") {
        # Special Case:  Divide on the empty string.  The group will start
        # with "(?:|...)"
        shift(@words);
        @half2 = @words;
    } else {
        my $markerchar = substr($words[0], 0, 1);
        foreach (@words) {
            if (m<^$markerchar>) { push @half1, $_; }
            else { push @half2, $_; }
        }
    }
    undef @words;
    if ($_Verbose) {
        print STDERR ("# recursive_regexp_grouper():  ",
                      " Divide & Conquer, left half.\n");
    }
    $patstr .= $group_open;
    @_RecursiveRegexpGrouper_Stack = ($recursionDepth+1, "", 0, @half1);
    $patstr .= recursive_regexp_grouper();
    if ($_Verbose) {
        print STDERR ("# recursive_regexp_grouper():  ",
                      " Divide & Conquer, right half.\n");
    }
    $patstr .= "|";
    @_RecursiveRegexpGrouper_Stack = ($recursionDepth+1, "", 0, @half2);
    $patstr .= recursive_regexp_grouper();
    $patstr .= $group_close;
    return $patstr;
}


1;  # don't forget to return a true value from the file
## POD STARTS HERE ##
__END__

=head1 NAME

jpwTools - Package containing John's Perl Tools.

=head1 SYNOPSIS

=head2 B<General Tools>

=over 4

=item datestamp

=item datetime_now

=item not_empty(I<var>)

=item set_array_if_nonempty(I<@listvar>, I<%map>, I<key>)

=item set_scalar_if_nonempty(I<$scalarvar>, I<%map>, I<key>)

=item create_regexp_group(I<@words>)

=item non_overlapping(I<@prefixes>)

=item get_files_from_dirs(I<%hash>, I<match_regexp>, I<dir> [, I<dir> ...])

=back

=head2 B<Debugging & Error Handling>

=over 4

=item dbgprint(I<lvl>, I<stringsOrArrayref>...)

=item ifdbgprint(I<lvl>, I<stringsOrArrayref>...)

=item check_syscmd_status([I<ctrlRef>, ] I<cmd>...)

=item openPipeDie(I<pipeCmd>)

=item closePipeDie(I<pipeCmd>)

=item failedOpenDie(I<fname>, I<openAction>)

=item do_error(I<filename>, $!, $@)

=back

=head2 B<Arrays & Lists>

=over 4

=item circular_shift(I<@list> [, I<count>])

=item circular_pop(I<@list> [, I<count>])

=item const_array(I<value>, I<n_elements>)

=item select_sample(I<nSelected>, I<@list> [, I<keepLast>])

=back

=head2 B<Hashes>

=over 4

=item key_not_set(I<%hash>, I<key2check>)

=item push_subarray(I<%hash>, I<$targKey> [, I<$val> [I<$val> ...]])

=item invert_hash(I<%hash> [, I<%invHash_out>])

=item pivot_hash(I<%hash>, I<idx> [, I<ignoreInvalidElements>])

=item rename_keys(I<%hash>, I<%oldKey2newKey>)

=item transform_keys(I<%hash>, I<&operator>)

=item lc_keys(I<%hash>)

=item uc_keys(I<%hash>)

=back

=head2 B<Set Operations>

=over 4

=item uniq(I<@list>)

=item asymm_diff(I<\@list1, \@list2>)

=item asymm_diff(I<\@list, \%hash>)

=item asymm_diff(I<\%hash, \@list>)

=item asymm_diff(I<\%hash1, \%hash2>)

=back

=head2 B<Statistics & Random Values>

=over 4

=item stats(I<@list> [, I<confidence>])

=item stats_gaussian(I<@list>)

=item set_seed([I<seed>])

=item randomize_array(I<@list>)

=item random_indices(I<nIndices>, [I<@list>])

=item random_keys(I<%hash>)

=back

=head2 B<Printing Arrays, Hashes, and Objects>

=over 4

=item print_hash(I<name>, I<%hash> [, I<regexp, sub> ...])

=item print_array(I<name>, I<@list> [, I<regexp, sub> ...])

=item fprint_hash(I<fh_ref>, I<name>, I<%hash> [, I<regexp, sub> ...])

=item fprint_array(I<fh_ref>, I<name>, I<@list> [, I<regexp, sub> ...])

=item print_dump([I<fh_ref>, ]  [I<name>, ] I<$ref> [, I<regexp, sub> ...])

=back

=head2 B<Reading Configfiles>

=over 4

=item read_options(I<option_filename> [, I<%validator>])

=item validate_options(I<%option_map>, I<%validator> [, I<filename>])

=back

=head1 DESCRIPTION

=head2 B<General Tools>

=over 2

=item -

datestamp

Returns string containing the current date, in the form 'YYYYMMDD'.  Useful
for creating date-stamped filenames.

=item -

datetime_now

Returns 6 element array containing the date and time.  The array contents are
of the form: C<(year, month, day, hour24, min, sec)>.

=item -

not_empty(I<var>)

Returns C<true> if I<var> is:

=over 2

=item *

a scalar value with nonzero length;

=item *

a reference to a scalar variable whose value has nonzero length;

=item *

a reference to an array or hash with at least one element.

=back

For any other type of variable or reference, returns C<false>.

=item -

set_array_if_nonempty(I<@listvar>, I<%map>, I<key>)

If C<$I<map>{I<key>}> is non-empty (as determined by C<not_empty()>),
sets I<@listvar> to C<@{I<$map>{I<key>}}>.

(Thus, the value of I<%map> corresponding to I<key> had better be an array
reference, or this function will return an error.)

=item -

set_scalar_if_nonempty(I<$scalarvar>, I<%map>, I<key>)

If C<$%I<map>{I<key>}> is non-empty (as determined by C<not_empty()>),
sets I<$scalarvar> to its value.

=item -

create_regexp_group(I<@words>)

Takes the array I<@words> and groups it into a pattern string for use in a
regular expression.  The pattern string is compact, with words grouped
together by common prefix & suffix.

=item -

non_overlapping(I<@words>)

Returns a list of "non-overlapping elements":  elements that are not
prefixes of any other element, or those that are a minimum-sized prefix.

=item -

get_files_from_dirs(I<%fileMap>, I<match_regexp>, I<dir> [, I<dir> ...])

Searches through the specified list of directories (the I<dir> passed to this
function) for all files/subdirectories matching I<match_regexp>.  The results
are stored in I<%fileMap> in the format described below.

If I<match_regexp> is the empty string, C<get_files_from_dirs()> returns all
files.  (The files "." and ".." are, however, always omitted.)

The I<dir> arguments are normalized and cleaned up using the L<File::Spec>
package.  Any paths containing "/../" path elements are resolved using the
L<Cwd> package (which is only loaded, dynamically, at runtime, if necessary).
Symlinks combined with "/../" subpaths will, therefore, be resolved to the
actual directory.

The results are returned in I<%fileMap>, which is keyed by the filename's full
absolute path.  Each value is an array reference containing the following:

=over 4

[I<fileBasename>,
 I<fileDirnameAbspath>,
 I<fileExtension>,
 I<fileBasenameStem>,
 I<fileType>,
 I<originalDirectory>]

=back

The names for each element are fairly self-explanatory.  I<fileBasenameStem>
is basically I<fileBasename> with I<fileExtension> removed.
I<originalDirectory> contains one of the I<dir> strings passed as an argument,
specifically the one that resolves to the file's parent.

I<fileType> is a single character string indicating the type of file.  It can
have any of the following values:

    ''  :== A regular file
    'd' :== A directory
    'L' :== A symlink (may or may not be valid)
    'b' :== A block device file
    'c' :== A character device file
    'p' :== A named pipe
    's' :== A named socket
    '?' :== An unknown type of file

=back

=head2 B<Debugging & Error Handling>

=over 2

=item -

dbgprint(I<lvl>, I<stringsOrArrayref>...)

Prints the arguments to C<STDERR>, prefixing each line with a special string.
The "special string" contains the word 'DBG', surrounded by I<lvl> '#'
characters on each side.

C<dbgprint> always prints a "\r" followed by the prefix before it starts.
This way, the first line printed each call will seem to start with the
prefix.  However, this will also mask any unterminated lines you may have
printed to C<STDERR> beforehand.  (You can prevent that from happening by
piping the output of your script to C<less>,  run w/o the C<-r> option.)

Normally, I<stringsOrArrayref> will just be a list of strings or
string-expressions, each of which is printed out.  However, if any of the args
are a reference to an array, it will be handled differently.  The
arrayref arg must have at least two elements:

=over 4

=item [ I<hashname>, I<hashref> ]

Invokes C<print_hash(I<hashname>, I<hashref>, '^', I<prefix_nextLvl>)>

=item [ I<arrayname>, I<arrayref> ]

Invokes C<print_array(I<arrayname>, I<arrayref>, '^', I<prefix_nextLvl>)>

=back

...where I<prefix_nextLvl> is the prefix that (I<lvl>+1) would generate.  If
an arrayref arg to C<dbgprint> doesn't match either of these specs, it's
treated as a string-expression.

Lastly, if the last arg ends with a sequence of "\n", they will B<not> be
prefixed.  Normally, you want this, since the next call to C<dbgprint> will
print out the prefix at the start.

However, you might actually want to print out a bunch of lines containing only
the prefix.  To do that, remove one of the "\n" and make it the last arg.
This turns your sequence of "\n" into the second-to-last arg, and terminates
the last "prefix-only line".

=item -

ifdbgprint(I<lvl>, I<stringsOrArrayref>...)

This really isn't a function, but documentation for an optimized code-pattern
that lets you leave C<dbgprint> in the source.

Here's the code pattern:

    use constant
        DEBUG => 0 # or 1, depending on what you want to do.
    ;

    sub ifdbgprint($@) {
        if (DEBUG) {
            my $lvl = shift();
            dbgprint($lvl, @_);
        }
    }

Defining the compile-time constant, C<DEBUG>, to '0' not only disables the
debug printout, the perl compiler will completely optimized away the code
inside of C<ifdbgprint>.  See L<constant> (using C<perldoc>) for details.

Unfortunately, this pattern can't be defined in this module.  You would have
to always define C<DEBUG> in the main namespace anytime you wanted to use this
package.  Otherwise, this package would fail to compile.  Making C<DEBUG> a
package-member constant obviously won't work (you can't redefine a constant).
Lastly, Perl will not optimize away the call if you don't use a constant in
the guard-C<if> block.

You can't use an C<if>-statement to check if a constant has been defined,
either, since an C<if>-statement is only evaluated at runtime.

=item -

check_syscmd_status([I<ctrlRef>, ] I<cmd>...)

Checks $?, the status of the last system command run.  If the status is
nonzero, it prints out the specified args as part of an error message, then
aborts the program.

You should call this function immediately after your call to C<system> (or to
the `` operator.  You can also use it when opening a file or pipe, and when
closing a pipe (see below).

I<cmd> is one or more strings containing the command you executed with the
C<system> call.  It will usually be the same args you just passed to
C<system>.

The first arg may, optionally, be a reference to an array or a hash, used to
control whether or not C<check_syscmd_status> aborts the program.

When called with an array reference, the array should contain a list of one or
more exit values to ignore.  If the command run using C<system> (or via a
pipe; see below) exited with one of these values, then C<check_syscmd_status>
will only issue a warning and return, instead of aborting.

If I<ctrlRef> is a hash, it may contain one of the following keys:

=over 1

=item C<ignore>

This option lets you specify the list of exit values to ignore when you also
need to use one of the other options listed below.  The value of this key
should be an array reference.  Any other value will be silently ignored.

=item C<laststat>

Normally, C<check_syscmd_status> uses the value of the $? variable
directly.  That doesn't work if you need to call some other function before
C<check_syscmd_status>, or if you call C<check_syscmd_status> from a
wrapper-function.  This option solves that problem.  Set its value to your
previously saved $? value.

Note that the C<system> function returns $?.  So, you can use that return
value with C<laststat>, too.

=item C<exitval>

An alternative to using C<laststat>, when you don't have access to $? but do
have the exit value of the subprocess.  Using C<laststat> (or neither of
these) is preferable, since the $? variable contains both exit status and
signal information.

=item C<no_stacktrace>

Setting this flag to C<1> causes C<check_syscmd_status> to omit the
stacktrace that it normally creates.

=item C<open_pipe>

This option lets you use C<check_syscmd_status> with something other than the
C<system> function.  It alters the warning/error message appropriately.  As
the name implies, this option is for checking for errors after calling the
C<open> function on a pipe.  When using this option, you should pass the
opened pipe-command as this function's I<cmd> argument.

Set the value of this key to true to enable it; setting it to false does
nothing.  Mutually-exclusive with C<open_file> and C<close_pipe>.

=item C<close_pipe>

This option lets you use C<check_syscmd_status> with something other than the
C<system> function.  It alters the warning/error message appropriately.  Use
this option after calling C<close> on a filehandle to an opened pipe.
C<check_syscmd_status> will examine the exit status of the piped command to
see if/how it failed.

When using this option, you should pass the closed pipe-command as this
function's I<cmd> argument.  Set the value of this key to true to enable it;
setting it to false does nothing.  Mutually-exclusive with C<open_pipe> and
C<open_file>.

=item C<open_file>

This option lets you use C<check_syscmd_status> with something other than the
C<system> function, specifically the C<open> function when used for reading or
writing a file.  It alters the warning/error message appropriately.  When
using this option, you should pass file's name as this function's I<cmd>
argument.

Mutually-exclusive with C<open_pipe> and C<close_pipe>.

Unlike its siblings, the value of this key must be one of the following:

=over 4

=item 'reading'

=item 'writing'

=item 'modifying'

=back

Any other value will create a gibberish error/warning message.

=item C<warn>

If the value of this key evaluates to true, C<check_syscmd_status> will return
the command's exit value instead of aborting the program.  Any value that
evaluates to false is ignored.  Mutually-exclusive with C<abort>.

I<NOTE:> When using this key, you should use a code pattern like the
following:

=over 4

if (check_syscmd_status({'warn' => 1, I<...>}, I<cmd>)) {
    # Do error handling here.
}

=back


=item C<abort>

The value of this flag directly controls whether or not C<check_syscmd_status>
aborts on error.  Mutually-exclusive with C<warn>.

=back

=item -

openPipeDie(I<pipeCmd>)

Convenience wrapper around:

    check_syscmd_status({'open_pipe' => 1,
                         'laststat' => ($? ? $? : 13)}, I<cmd>).

Use it in a statement like this:

=over 4

open(my $pipefh, "someCmd |") or openPipeDie("someCmd |");

=back

(The reason for using '13' if C<open()> doesn't set C<$?> is that
C<check_syscmd_status> will report a signal 13 == SIGPIPE.  Appropriate, no?)

=item -

closePipeDie(I<pipeCmd>)

Convenience wrapper around:

    check_syscmd_status({'close_pipe' => 1,
                         'laststat' => I<valOf_$?>}, I<cmd>).

Use it in a statement like this:

=over 4

close($pipefh) or closePipeDie("someCmd |");

=back

=item -

failedOpenDie(I<fname>, I<openAction>)

Convenience wrapper around:

    check_syscmd_status({'open_file' => I<openAction>,
                         'laststat' => 1}, I<fname>);

Use it to perform the usual post-C<open()>-error-checking-song-n-dance:

    open(my $rfh, "<somefile.txt")
        or failedOpenDie("somefile.txt", 'reading');
    open(my $wfh, ">outfile.txt")
        or failedOpenDie("outfile.txt", 'writing');

=item -

do_error(I<filename>, $!, $@)

Use this to generate an error message after a failed do-call.  Use it in a
statement like this:

=over 4

do "file.pl" or die(do_error("file.pl", $!, $@));

=back

=back

=head2 B<Arrays & Lists>

=over 2

=item -

circular_shift(I<@list> [, I<count>])

Shifts I<count> elements off of I<@list>, or 1 if I<count> isn't specified.
Like the builtin C<shift> command, returns the shifted elements.  Unlike
C<shift>, it takes the shifted elements and immediately C<push>es them onto
the back of I<@list>.  Thus, I<@list> never loses elements; they merely change
location.

=item -

circular_pop(I<@list> [, I<count>])

Pops I<count> elements off of I<@list>, or 1 if I<count> isn't specified.
Like the builtin C<pop> command, returns the popped elements.  Unlike
C<popped>, it takes the popped elements and immediately C<unshift>s them onto
the front of I<@list>.  Thus, I<@list> never loses elements; they merely
change location.

=item -

const_array(I<value>, I<n_elements>)

Create an array, I<n_elements> long, with each element set to I<value>.
You can do this inline, without the overhead of the function call, with this
piece of Perl code:

=over 4

C<my @ca = ( I<value> ) x I<n_elements>;>

C<my @set{@members} = ( I<value> ) x I<@members>;>

=back

I.e.  the C<x> operator works on arrays as well as strings.  Note that the
thing following the C<x> operator is always evaluated in scalar context.

=item -

select_sample(I<nSelected>, I<@list> [, I<keepLast>])

Select a uniform I<nSelected>-point sample of elements from I<@list>.  Returns
an array containing the selected elements.

The first element in I<@list> is always selected.  The rest of the sample are
the elements which are roughly I<$#list>/I<nSelected> indices apart.

Due to the discrete nature of an array, the last element of I<@list> often
won't be in the selection.  Set I<keepLast> to any true value in order to
force inclusion of the last element of I<@list>.  Consequently, the returned
array may contain (I<nSelected>+1) elements ... or not.

=back

=head2 B<Hashes>

=over 2

=item -

key_not_set(I<%hash>, I<key2check>)

Returns true if I<key2check> doesn't exists in I<%hash> or if it exists but
isn't defined.  Performs this check w/o autovivifying the element
C<$hash{key2check}>.

=item -

push_subarray(I<$subelement>, I<$val> [, I<$val> ...]])

Pushes the specified values onto the arrayref specified in the first arg.  If
C<$hash{$targKey}> ...  B<if> the latter is an arrayref.  If it's some other
type of value, C<push_subarray> does nothing.

If C<$hash{$targKey}> doesn't exist yet, it will be set to an arrayref
containing the specified values (or an empty arrayref if only 2 args were
passed to C<push_subarray>).

=item -

invert_hash(I<%hash> [, I<%invHash_out>])

Takes I<%hash> and inverts it, converting each scalar value in I<%hash> to a
key in I<%invHash_out> whose value is the corresponding key from I<%hash>.
Non-scalar values are ignored (i.e. they do not appear in I<%invHash_out>,
since you can't really convert them to a string key).  Preserves non-unique
values by storing the corresonding keys in a single arrayref (in arbitrary
order) in I<%invHash_out>.

When called with only one arg, C<invert_hash()> returns the inverse hash.

=item -

pivot_hash(I<%hash>, I<idx> [, I<ignoreInvalidElements>])

"Pivots" the I<%hash> by swapping each key with the value at
C<$hash{I<anykey>}[I<idx>]>.  Unlike L<invert_hash()>, this function directly
modifies I<%hash>.  Returns 1 on success.  If one or more of the values
C<$hash{I<anykey>}[I<idx>]> is non-unique,  C<pivot_hash()> returns 0 without
modifying I<%hash>.

The optional argument I<ignoreInvalidElements> controls what C<pivot_hash()>
does with values of I<%hash> that aren't arrayrefs or don't have a defined
value at I<idx>.  By default, C<pivot_hash()> returns 0 without modifying
I<%hash> if I<%hash> contains any elements like this.  (Such elements cannot
be pivoted, just like new keys that would be non-unique.)  Passing
I<ignoreInvalidElements>==1 tells C<pivot_hash()> to proceed by ignoring those
cases where there isn't any new key.

=item -

rename_keys(I<%hash>, I<%oldKey2newKey>)

"Renames" a set of keys in I<%hash>, using the map I<%oldKey2newKey> to
determine which keys to rename and what to change them to.

In reality, it takes each (key, value) pair in I<%oldKey2newKey>, sets the
new key in I<%hash> to the value of the old key, then deletes the old key from
I<%hash>.  This is the only way to "rename" a key.  So, if the values of
I<%hash> are all large strings, this routine will be a performance hit.  For a
hash of references, however, it shouldn't be too bad.

=item -

transform_keys(I<%hash>, I<&operator>)

"Modifies" all of the keys in I<%hash> by applying I<&operator> to each one.

In reality, there is no way to "modify" a key.  What this function actually
does is call I<&operator> on each key to create the new key, sets the new
key to the old key's value, then deletes the old key.  So, if the values of
I<%hash> are all large strings, this routine will be a performance hit.  For a
hash of references, however, it shouldn't be too bad.

=item -

lc_keys(I<%hash>)

=item -

uc_keys(I<%hash>)

Both of these functions are equivalent to calling C<transform_keys(I<%hash>,
&lc)> and C<transform_keys(I<%hash>, &uc)>, respectively.

They are not, however, I<identical> to the two calls above.  Those two calls
are not legal Perl.

The problem lies with Perl itself.  C<lc()> and C<uc()> are not in the
function symbol table of namespace C<main::> (if at all).  At best, they are
only bare symbols.  They may be tokenized immediately at compile time, for
that matter.  So, we can't take a reference to them.   We must, instead,
resort to the trick of creating a "wrapper" C<sub> around C<lc()> and
C<uc()>.

Bear this in mind whey trying to pass one of the built-in Perl functions to
C<transform_keys()>.

=back

=head2 B<Set Operations>

=over 2

=item -

uniq(I<@list>)

Like the Unix utility C<uniq>: Returns an array containing only the unique
members of I<@list>.  The input list does not need to be sorted.  The output
is in the same order as I<@list>).

Consider using a hash instead of an array if you truly need a set of unique
values (and if perserving order isn't an issue).

=item -

asymm_diff(I<set1>, I<set2>)

Performs a "set subtraction", returning all of the elements from I<set1> that
are not also in I<set2>.  The arguments I<set1> and I<set2> must be references
to an array or to a hash.  When one or both arguments reference a hash,
C<asymm_diff()> operates on the hash's keys, ignoring (and preserving) the
values.  The subroutine returns either an array or hash, matching whatever
data type I<set1> has.  Note that neither I<set1> nor I<set2> are modified by
this subroutine.

=back

=head2 B<Statistics & Random Values>

=over 2

=item -

stats(I<@list> [, I<confidence>])

For the given I<@list>, computes general measures of central tendency ... in
this case, the median ...  and dispersion about the median.  Returns an array
containing:

C<(min, lowerDispersion, median, upperDispersion, max)>

C<min> and C<max> are self-explanatory, and are computed for free as a
by-product of determining the C<median>.  C<lowerDispersion> and
C<upperDispersion> are the dispersion about the C<median>, computed to the
specified interval or percentage.

The term "central tendency" refers to the value in a set of data that is most
likely to occur.  The "dispersion" refers to a range of values in a set of
data which are most likely to occur.  The central tendency, therefore, always
is in the dispersion interval, hence the term "dispersion about the central
tendency".  "Percent dispersion" refers to the specific likelihood of
everything in the dispersion interval.  So, "50% dispersion" means that 50% of
the data in the set falls in the range defined by the dispersion.  For
data obeying a Gaussian distribution, the mean measures the central tendency
of the data, while the standard deviation measures the dispersion.

I<confidence> determines the percent dispersion about the median and can be
any of the following:

=over 4

=item any real < 1.0

If I<confidence> is a numeric real value less than 1.0, it is interpreted as
the percent dispersion about the median to compute.  (Any leading '-' on a
numeric value is ignored.)

=item q

Computes the "interquartile ranges," which corresponds to 50% dispersion about
the median.

=item 3s

Computes 99.73% dispersion about the median.  This is equivalent to 3 standard
deviations for a Gaussian distribution.

=item 2s

Computes 95.45% dispersion about the median.  This is equivalent to 2 standard
deviations for a Gaussian distribution.

=item default

For any other value of I<confidence>, or if it's omitted, computes 68.27%
dispersion about the median.  This is equivalent to 1 standard deviations for
a Gaussian distribution.

=back

Note that C<stats()> will not work well for multi-modal distributions,
especially if two or more of the peaks in the distributions are of similar
height.  Multi-modal distributions require more sophisticated techniques for
computing central tendency and dispersion.

=item -

stats_gaussian(I<@list>)

Computes the "Gaussian statistics" of I<@list>, a la §14 of "Numerical
Recipies."  Returns an array containing:

C<(mean, variance, skew, kurtosis, StdDeviation, AvgDeviation)>

...where C<StdDeviation> is the square root of the C<variance>, and the
C<AvgDeviation> is the mean of abs(I<<@list>-mean).

These are referred to as "Gaussian statistics" because they work best for data
with a Gaussian or near-Gaussian distribution.  Only for these distributions
does the mean give a good measure of central tendency and the standard
deviation  give a good measure of dispersion about the central tendency.

If your data's distribution is asymmetric, has large, significant tails, or
outliers, consider using L<stats()|/"stats"> instead.  For these kinds of
distributions, the mean and variance will not be meaningful values.

=item -

set_seed([I<seed>])

Sets the seed of Perl's internal PRNG in a reproducable way, returning the
seed that it used.

When passed a I<seed>, C<set_seed()> behaves the same as L<srand()>. When
called without args, C<set_seed()> "bootstraps" a seed for itself by first
calling L<srand()> with no args, then invoking L<rand()> to create the seed it
uses.  This isn't great, from the standpoint of PRNG generation, and it's
terrible for cryptographic uses.  However, when you need/want to autogenerate
a seed but save that seed for future reuse (e.g. for Monte Carlo simulation),
it'll do.

=item -

randomize_array(I<@list>)

Shuffles the contents of I<@list> in-place, using the Fisher-Yates method.

NOTE:  Consider using L<shuffle()> from L<List::Util> instead.  Only prefer
this function if I<@list> is very large (causing L<shuffle()> to be
inefficient due to copying the the return value).

=item -

random_indices(I<nIndices>, [I<@list>])

Generates indices from C<0> to I<nIndices>C< - 1> in a random (read: shuffled)
order.  If the optional I<@list> argument is specified, the indices are stored
in it, erasing any existing elements.  Otherwise, C<random_indices()> returns
the list of randomly-ordered indices.

This function invokes either L<shuffle()> from L<List::Util> or
L<randomize_array()>, depending on whether or not you omitted I<@list>.

=item -

random_keys(I<%hash>)

Returns the keys of I<%hash> in a random (read: shuffled) order.

This function invokes L<shuffle()> from L<List::Util>.

=back

=head2 B<Printing Arrays, Hashes, and Objects>

=over 2

=item -

fprint_hash(I<fh_ref>, I<name>, I<%hash> [, I<regexp, sub> ...])

Convenience wrapper around
C<print_dump(I<fh_ref>, [I<name>,] I<\%hash> [, ...])>.  I<name> can be the
empty string, in which case L<print_dump()|/"print_dump"> is called without it.

=item -

fprint_array(I<fh_ref>, I<name>, I<@list> [, I<regexp, sub> ...])

Convenience wrapper around
C<print_dump(I<fh_ref>, [I<name>,] I<\@list> [, ...])>.  I<name> can be the
empty string, in which case L<print_dump()|/"print_dump"> is called without it.

=item -

print_hash(I<name>, I<%hash> [, I<regexp, sub> ...])

Equivalent to C<fprint_hash(\*STDOUT, I<name>, I<%hash> [, ...])>.

=item -

print_array(I<name>, I<@list> [, I<regexp, sub> ...])

Equivalent to C<fprint_array(\*STDOUT, I<name>, I<@list> [, ...])>.

=item -

print_dump([I<fh_ref>, ] [I<name>, ] I<$ref> [, I<regexp, sub> ...])

Calls C<Data::Dumper::Dumper()> on I<$ref>, printing the results.  When called
with more than one arg, the first and/or second arg can be one of the
following:

=over 2

=item I<fh_ref>, a GLOB reference

I<fh_ref> is treated as the filehandle to print to.  If this is the only arg,
C<print_dump> dies.

=item I<name>, a scalar

I<name> is passed to C<Dumper()> as the variable name.

=item I<fh_ref>, I<name>, I<$ref>

Calls C<Dumper([I<$ref>], [I<name>])>, printing the results to I<fh_ref>.

If you call C<print_dump> with only two args, the first of which is I<fh_ref>,
the second arg is assumed to be the variable to dump, not the name.

=back

C<print_dump()> forces C<$Data::Dumper::Sortkeys==1> and
C<$Data::Dumper::Indent==1>.

Every additional pair of arguments, I<regexp, sub>, are treated as a
substitution operation to apply to the string returned by
C<Data::Dumper::Dumper()>.  Each pair is used to construct the expression:
C<s/I<regexp>/I<sub>/mg>, which will then be C<eval>'d.  Be sure, therefore,
to pass each I<regexp> and I<sub> single-quoted.

=back

=head2 B<Reading Configfiles>

=over 2

=item -

read_options(I<option_filename> [, I<%validator>])

Reads the file named I<option_filename> for options, returning them in a
hash.  This is a very powerful routine, permitting you to create B<safe>
configuration files for Perl scripts run by root.

The option file syntax:

=over 2

=item *

Blank lines and whitespace at the beggining or end of a line are
ignored.

=item *

Comments are lines starting with the '#' character.

=item *

The first non-whitespace character on a line starts an option name.

=item *

Scalar options appear on the same line with their value, separated
by the one of delimiter characters ':' or '='.

=item *

Option names can contain any character except '.', ':' and '='.

=item *

Any whitespace surrounding the '=' or ':' delimiter is ignored.

=item *

You cannot set a scalar option to the value "(".  [See below.]

=item *

Options can contain an array value:

=over 2

=item *

To start an array value, use a '(' character after the delimiter.

=item *

The elements of the array are each subsequent line in the file.

=item *

You can indent array elements.  [See below.]

=item *

The array ends at the next line containing a lone ')' character.

=back

=item *

Option names, scalar values, and array elements can neither begin
nor end with whitespace characters.  They are stripped off.

=item *

The options are returned in a hash map, keyed by name.   Array
options are stored as references to anonymous Perl arrays.

=item *

Options can be grouped into sections:

=over 2

=item *

Sections are just a prefix on the option name, separated by a '.' character.
For example:

C<first.wifi_interface = I<value>>

Sets the option C<wifi_interface> in the section C<first> to I<value>.

=item *

The same rules that apply to option names apply to section names, as well.

=item *

Sections are elements of the hash map returned by this function, keyed by
section name.

=item *

The options in a sections are returned in an anonymous Perl hash map, keyed by
the option name and obeying the same rules as regular options.

In other words, sections turn the return value into a 2-D Perl hash map.
Regular options and sections are accessed by the first key.  The second key
accesses options within a section.

=item *

Sections cannot be nested.  Any '.' characters after the one following the
section name are ignored.  If you wish to use sub-sub-sections and more
complex structures, you're on your own.

=back

=back

Before returning, C<read_options()> will call C<validate_options()> using
the optional hash argument, I<%validator>.  See
L<validate_options()|DESCRIPTION/"validate_options"> for a description of what
the I<%validator> argument should look like.

=item -

validate_options(I<%option_map>, I<%validator> [, I<filename>])

Checks the options in I<%option_map> for type-consistency.  I<%option_map>
should be the hash read from a configuration file by
L<read_options()|DESCRIPTION/"read_options">.

The keys of the I<%validator> map correspond to the names of the (regular)
options in I<%option_map>.  Any key of I<%validator> that isn't one
of the returned (regular) options --- and vice-versa --- is ignored.  Each
value is a string like that returned by the perl builtin, L<ref()>.  If the
reference-type of any option from I<option_filename> doesn't match the
expected type, the program aborts (via L<die()>).

You can also validate sections by using the section name as a key in
I<%validator>.  The corresponding value is a reference to an anonymous Perl
hash.  That anonymous Perl hash is, in turn, a validator hash-map, with the
same format as described above.  Or, it can be an empty hash, in which case,
C<validate_options()> only validates that a section name wasn't incorrectly
used as a regular option.

This file has been split out of L<read_options()|DESCRIPTION/"read_options">
so that one can validate a configuration file in stages.  This is especially
useful when some setting in the file determine the nature and presence of
other settings.

The optional argument I<filename> is used for pretty-printing error messages
(if any errors are present).  It should be the name of the configuration file
being validated.

=back

=cut

#################
# Local Variables:
# coding: utf-8-unix
# End:
