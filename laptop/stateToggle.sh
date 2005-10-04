#!/bin/bash
#
# Copyright (C) 2005 by John P. Weiss
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
# RCS $Id: script.sh 1401 2005-08-08 23:09:12Z candide $
############


############
#
# Configuration Variables
#
############


SYS_NET_BASE=/sys/class/net


############
#
# Includes & Other Global Variables
#
############


#. some.include.sh

GREP=grep
SED=sed
AWK=awk
LS=ls


############
#
# Functions
#
############


check_sysfile() {
    sysfile="$1"
    expected="$2"

    # Does the device state file exist?
    # If not, the device doesn't exist (yet).  Return false.
    [ -e $sysfile ] || return 1

    val=`cat $sysfile 2>&1`
    # Did the cat succeed?
    status=$?
    if [ $status -ne 0 ]; then
        return $status
    fi
    # Did the cat output an error message containing the word "invalid"
    case "$val" in 
        *[Ii]nvalid*)
            return 1
            ;;
    esac
    # At this point, we know cat spat out *something*.  Check it against the
    # expected value, if one was provided.
    if [ -n "$expected" ]; then
        if [ $expected = $val ]; then return 0; fi
         #else 
        return 1
    fi
    return 0
}


ifc_state() {
    ifc="$1"
    expected="$2"

    ifc_carrier="${SYS_NET_BASE}/$ifc/carrier"
    check_sysfile $ifc_carrier $expected
    return $?
}


lan_state() {
    # Return true if the interface is up.  The actual value of the
    # ".../carrier" file doesn't matter.  (It just indicates whether or not
    # something is actually connected to the other end of the cable.)
    ifc_state "$1"
    return $?
}


wifi_power_is_on() {
    ifc="$1"
    # Check if rf_kill==0
    ifc_rf_state="${SYS_NET_BASE}/$ifc/rf_kill"
    if [ ! -e $ifc_rf_state ]; then
        # Unlike the other /sys/... state files, "rf_kill" doesn't exist until
        # the power on the antenna is explicitly shut off.
        return 0
    fi
    # rf_state == 0 => power on    
    if [ "`cat $ifc_rf_state`" = "0" ]; then
        return 0
    fi #else
    return 1
}


wifi_state() {
    ifc="$1"

    # First, check that the wifi is actually turned on.
    wifi_power_is_on $ifc || return 1

    # Check several other state files for existence (don't really care what
    # value they return).
    for statefile in $SYS_NET_BASE/$ifc/{wireless/{link,status},carrier}; do
        check_sysfile $statefile || return $?
    done

    # Only reaches here on success.
    return 0
}


get_actual_ifc_name() {
    case "$1" in
        eth*_*)
            echo "${1%%_*}"
            ;;
        eth*-*)
            echo "${1%%-*}"
            ;;
        eth*.*)
            echo "${1%%.*}"
            ;;
        *)
            echo "$1"
            ;;

    esac
}


state2start_stop() {
    if [ $1 -eq 0 ]; then
        echo stop
    else
        echo start
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
    usage="usage: $0 <lan_state|wifi_power_is_on|wifi_state"
    usage="${usage}> <ifc_name>"
    if [ -z "$*" ]; then
        echo "$usage"
        exit 1
    fi
    while [ -n "$1" ]; do
        case "$1" in
            lan_state|wifi_power_is_on|wifi_state)
                opname="$1"
                ;;
            ut_*)
                opname="${1##ut_}"
                ;;
            -h|--help|*)
                echo "$usage"
                exit 1
                ;;
        esac
        shift
        ifc=`get_actual_ifc_name "$1"`
        shift
        $opname "$ifc"
        state2start_stop $?
    done
fi


#################
#
#  End
