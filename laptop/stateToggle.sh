#!/bin/bash
#
# Copyright (C) 2005-2008 by John P. Weiss
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


SYS_NET_BASE=/sys/class/net
# This will be auto-set if left blank.
SYS_WIFI_RF_KILL_RELPATH=""


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


kernel_specific_wifi_setup()
{
    oIFS="$IFS"
    IFS=".-_"
    set -- `uname -r`
    IFS="$oIFS"

    kver_major=$1
    shift
    kver_minor=$1
    shift
    kver_release=$1
    shift

    if [ "${kver_major}.${kver_minor}" = "2.6" -a \
         -z "${SYS_WIFI_RF_KILL_RELPATH}" ]; then
        if [ $kver_release -gt 13 ]; then
            # For kernel v2.6.14 and later.
            SYS_WIFI_RF_KILL_RELPATH=device/rf_kill
        else
            # For kernel v2.6.13 and earlier.
            SYS_WIFI_RF_KILL_RELPATH=rf_kill
        fi
    else
        echo "!!! ERROR:  Not configured to handle kernels earlier than v2.6" \
            >&2
        return 1
    fi
    return 0
}


# Returns 0 if the power is on.
# Returns 1 if the power is off.
# Returns 2 if the "/sys/.../rf_kill" file for the WiFi interface can't be
# found, and we can't make an unabiguous determination of the power state.
# Returns 3 if the specified WiFi interface doesn't even exist.
# Returns 127 if we can't run at all.
wifi_power_is_on() {
    ifc="$1"

    # Check if the ifc exists
    sys_ifc_base="${SYS_NET_BASE}/$ifc"
    if [ ! -e $sys_ifc_base ]; then
        return 3
    fi

    # Run kernel-specific setup if it wasn't run already.
    if [ -z "${SYS_WIFI_RF_KILL_RELPATH}" ]; then
        kernel_specific_wifi_setup
        # Punt if this is still blank.
        [ -z "${SYS_WIFI_RF_KILL_RELPATH}" ] && return 127
    fi

    # Check if rf_kill exists
    ifc_rf_state="${sys_ifc_base}/${SYS_WIFI_RF_KILL_RELPATH}"

    if [ ! -e $ifc_rf_state ]; then
        # Unlike the other /sys/... state files, "rf_kill" doesn't exist until
        # the power on the antenna is explicitly shut off or turned on. (Well,
        # at least that was the case in certain kernel versions.)   Sooo... we
        # need to use an alternative check 
        ifc_wireless_base="${SYS_NET_BASE}/$ifc/wireless"
        for f in beacon level link status; do
            check_sysfile "${ifc_wireless_base}/$f"
            if [ $? -ne 0 ]; then
                return 2
            fi
        done
        for f in beacon level link; do
            check_sysfile "${ifc_wireless_base}/$f" 0
            if [ $? -ne 0 ]; then
                # If any of these flags happens to be nonzero, the wifi is
                # definitely powered on.
                return 0
            fi
        done
        return 2
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
    wifi_power_is_on $ifc || return $?

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
