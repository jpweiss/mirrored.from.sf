#!/bin/bash
#
# Copyright (C) 2013-2014 by John P. Weiss
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
# Includes & Other Global Variables
#
############


#. some.include.sh
LOGFILE=/tmp/logs/swapOnOff-acpi.log
SWAPINFO=/proc/swaps


############
#
# Functions
#
############


get_n_swaps()
{
    local n=0
    set -- $(< $SWAPINFO)

    local fn t sz u pri
    while [ -n "$1" ]; do
        fn="$1"
        shift
        t="$1"
        shift
        sz="$1"
        shift
        u="$1"
        shift
        pri="$1"
        shift

        case "$t" in
            Type)
                :
                ;;
            *)
                let ++n
                ;;
        esac
    done

    echo "$n"
}


toggle_swap()
{
    local triggeringEvent="$*"

    local force=""
    case "$triggeringEvent" in
        *100[eE]|[oO][nN])
            # Fn+Insert
            force="on"
            ;;
        *100[fF])
            # Fn+Delete
            force=""
            #force="off"
            ;;
        [oO][fF][fF])
            force="off"
            ;;

        # Default:  Any other key combination performs a toggle.
    esac

    local nSwaps=$(get_n_swaps)
    if [ $nSwaps -gt 0 -a "$force" != "on" ]; then
        echo "Swap space on.  Disabling..."
        swapoff -a
    elif [ $nSwaps -lt 1 -a "$force" != "off" ]; then
        echo "No swap memory.  Enabling..."
        swapon -a
    fi
}


############
#
# Main
#
############


case "$0" in
    *bash)
        file_was_sourced='y'
        ;;
    *)
        if [ ${#BASH_SOURCE[*]} -gt 1 ]; then
            file_was_sourced='y'
        fi
        ;;
esac


if [ -n "$file_was_sourced" ]; then
    # Was sourced.  Remove the temporary variable created during the startup
    # checks.
    unset file_was_sourced
else
    # Was run as a script.  Perform any execution-specific tasks here (rather
    # than pulling an unneeded "main" function into the environment.

    echo "" >>$LOGFILE
    echo "#################### `date` ####################" \
        >>$LOGFILE
    echo "" >>$LOGFILE
    chmod a+r $LOGFILE

    toggle_swap "$@" >>$LOGFILE 2>&1
fi


#################
#
#  End
