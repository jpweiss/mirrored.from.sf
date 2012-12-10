#!/bin/sh
#
# Find and toggle wireless of bluetooth devices on ThinkPads
#
# Copyright (C) 2011-2012 by John P. Weiss
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


WIFI_DEV=eth1


############
#
# Includes & Other Global Variables
#
############


test -f /usr/share/acpi-support/state-funcs || exit 0
. /usr/share/acpi-support/state-funcs

. /etc/LocalSys/init.d/functions-laptop
LOGFILE=/tmp/logs/wifi-acpi.log


############
#
# Functions
#
############


isWifiUp()
{
    # Set the default.
    local isOn=0
    isAnyWirelessPoweredOn && isOn=1

    local isUp=1
    local opStF="/sys/class/net/${WIFI_DEV}/device/rf_kill"
    if [ -r $opStF ]; then
        isUp="`cat $opStF`"
    else
        isUp=$isOn
    fi

    [ "$isOn$isUp" = "00" ] && return 1
    [ "$isOn$isUp" = "11" ] && return 0
    # else:  Ambiguous result.  Return a slightly different code.
    return 10
}


toggleBluetooth()
{
    if [ ! -e /tmp/Fn-F5.ctrl-bluetooth ]; then
        echo "(Bluetooth toggling suppressed.  No action taken.)"
        return 0
    fi

    echo "Checking Bluetooth..."

    # Sequence is Both on, Both off, Wireless only, Bluetooth only
    if ! isAnyWirelessPoweredOn; then
        # Wireless was turned off; toggle bluetooth.
        toggleAllBluetoothAdapters
    fi
}


turnWifiOff()
{
    local iwconfig_failed rfk
    iwconfig_failed='n'

    echo "Found active WiFi; disabling..."
    iwconfig $WIFI_DEV txpower off || iwconfig_failed='y'
    if [ "$iwconfig_failed" != "y" ]; then
        isWifiUp
        # If the wifi isn't unambiguously down, then iwconfig failed to
        # work.
        if [ $? -ne 0 ]; then
            iwconfig_failed='y'
        fi
    fi

    if [ "$iwconfig_failed" = "y" ]; then
        echo "    'iwconfig' failed to disable TX power!"
        echo "    Attempting direct kernel param manipulation"

        killWifi
    fi

    # Return an appropriate status, depending on whether or not we failed to
    # unambiguously turn the antenna off.
    isWifiUp
    if [ $? -ne 0 ]; then
        return 1
    fi
    #else
    return 0
}


turnWifiOn()
{
    local iwconfig_failed
    iwconfig_failed='n'

    echo "Enabling WiFi..."
    loadWifiModules

    iwconfig ${WIFI_DEV} txpower on || iwconfig_failed='y'
    if [ "$iwconfig_failed" != "y" ]; then
        isWifiUp
        # If the wifi isn't unambiguously up, then iwconfig failed to
        # work.
        if [ $? -ne 1 ]; then
            iwconfig_failed='y'
        fi
    fi

    if [ "$iwconfig_failed" = "y" ]; then
        echo "    'iwconfig' failed to reenable TX power!"
        echo "    Attempting direct kernel param manipulation"

        local d rfk
        for d in /sys/class/net/*; do
            rfk=$d/device/rf_kill
            if [ -w $rfk ]; then
                # '1' means "turn off wifi"
                echo "    Enabling antenna..."
                echo 0 >>$rfk
            fi
        done
    fi

    # Return an appropriate status, depending on whether or not we failed to
    # unambiguously turn the antenna on.
    isWifiUp
    if [ $? -ne 1 ]; then
        return 1
    fi
    #else
    return 0
}


toggleWifi()
{
    # FIXME::[jpw;2010-11-13]
    # Something else is running when Fn-F5 is hit, in addition to this script.
    # Soooo... we'll let it run, then we'll ... um ... Wait.  If we then run
    # this script after waiting, we'll _reverse_ the change.  So that won't
    # work.
    #
    # The upshot is:  we have a race-condition between this script and whatever
    # else is running.

    local succeeded

    if isAnyWirelessPoweredOn; then
        turnWifiOff && succeeded=y
    else
        turnWifiOn && succeeded=y
    fi

    # If my own routines failed, fall back on the functoin from
    # '/usr/share/acpi-support/state-funcs'.
    if [ -z "$succeeded" ]; then
        echo ""
        echo "Still no success!  Trying to just toggle the antenna state..."
        toggleAllWirelessStates
    fi
}


############
#
# Main
#
############


echo "" >>$LOGFILE
echo "#################### `date` ####################" \
    >>$LOGFILE
echo "" >>$LOGFILE

toggleWifi >>$LOGFILE 2>&1
toggleBluetooth >>$LOGFILE 2>&1

echo "Done." >>$LOGFILE


######
# End
#
