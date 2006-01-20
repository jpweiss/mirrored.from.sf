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
# RCS $Id$
############


############
#
# Configuration Variables
#
############


IFC_NAME=eth1
LOG=/tmp/wifi-power.log
# This is a filename prefix.  It will be appended with "-on" or "-off" to
# construct the files that force the wifi power on or off, respectively.
FORCE_WIFI_POWER=/tmp/force-wifi


############
#
# Includes & Other Global Variables
#
############


MYPATH=`dirname $0`
IWCONFIG=/sbin/iwconfig
IFDOWN=/sbin/ifdown
MODPROBE=/sbin/modprobe
STATE_SCRIPT='stateToggle.sh'

FORCE_WIFI_POWER_ON="${FORCE_WIFI_POWER}-on"
FORCE_WIFI_POWER_OFF="${FORCE_WIFI_POWER}-off"


############
#
# Functions
#
############


power_off_wifi() {
    ifc_device="$1"
    shift

    # wifi_state returns 0 (true) if the WiFi device is currently up.
    if $(wifi_state "${ifc_device}"); then
        echo "=== Disabling interface:  ${IFC_NAME%%:*}"
        $IFDOWN ${IFC_NAME%%:*}
    fi

    echo "=== Powering down WiFi device:  ${ifc_device}"
    $IWCONFIG "${ifc_device}" txpower off
}


turn_on_wifi() {
    ifc_device="$1"

    echo "=== Enabling power on WiFi device:  ${ifc_device}"
    $IWCONFIG "${ifc_device}" txpower on
}


load_ifc_module() {
    ifc_device="$1"

    echo "=== Loading module(s) for device:  ${ifc_device}"
    $MODPROBE "${ifc_device}"
    success=$?
    if [ $success -ne 0 ]; then
        echo "!!! Failed to insert module.  Remaining steps will likely fail."
        echo "(Try defining an alias for \"${ifc_device}\" in "
        echo "/etc/modprobe.conf to load the wifi driver.)"
    else
        sleep 1
    fi

    return $success
}


toggle_wifi_power() {
    ifc_device="$1"

    # Determine what to do to the device.  wifi_power_is_on returns 0 (true)
    # if the WiFi device is currently powered on.
    if $(wifi_power_is_on "${ifc_device}"); then
        power_off_wifi "${ifc_device}"
    else
        # Perform any special processing based on the return status of
        # wifi_power_is_on.
        case $? in
            2)
                echo "=? Unclear whether or not power is on."
                echo "=? Powering off, then powering on."
                echo "=? (Kernel change modified \"/sys\" file layout?)"
                power_off_wifi "${ifc_device}" >/dev/null 2>&1
                ;;
            3)
                # No driver loaded for the WiFi interface.  Do that before we
                # try to power on.
                load_ifc_module "${ifc_device}"
                ;;
            127)
                echo "!!! Error in script: $MYPATH/$STATE_SCRIPT"
                echo -n "!!! No \"/sys/.../rf_kill\" file found "
                echo "for device: ${ifc_device}"
                echo "!!! (Is ${ifc_device} a WiFi device?)"
                echo "!!! Forcing power on."
                ;;
        esac
        turn_on_wifi "${ifc_device}"
    fi
}


first_mesg() {
    what="$1"
    shift

    echo ""
    echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    echo ""
    date
    echo ""
}


usage() {
    cat - <<-EOF
	usage: $0 [<Options>] [--keeplog]
	<Options>
	-i
	--ifc
	--ifname
	    Name of the WiFi network interface to turn on or off.  This
	    could be the name of the WiFi device's network interface, or it could
	    be a logical name of a WiFi interface device under a specific 
	    network profile.

	By default, this script toggles the state of the WiFi interface.  To 
	force it to turn on, run:
	    "touch ${FORCE_WIFI_POWER_ON}"
	before this script runs.  To force the WiFi interface off, do:
	    "touch ${FORCE_WIFI_POWER_OFF}"
	binstead.
EOF
    exit 1
}


############
#
# Main
#
############


# Begin by terminating any other running instance of this script:
for pid in `pgrep sync-mode`; do
    if [ $pid -ne $$ ]; then
        kill -15 $pid
    fi
done 

clearlog='y'
while [ -n "$1" ]; do
    arg="$1"
    shift
    case "$arg" in
        -i|--ifc|--ifname)
            shift
            IFC_NAME=$1
            ;;
        --keeplog)
            clearlog=''
            ;;
        *)
            first_mesg >>$LOG 2>&1 
            usage | tee -a $LOG
            ;;
    esac
done


if [ -n "$clearlog" ]; then
    rm -f $LOG >/dev/null 2>&1
fi
first_mesg >>$LOG 2>&1


# Load library functions
. $MYPATH/$STATE_SCRIPT


# Get the interface device. 
ifc_device=`get_actual_ifc_name "${IFC_NAME}"`


# First, see if the user wants to force the power on or off
if [ -e ${FORCE_WIFI_POWER_ON} -a -e ${FORCE_WIFI_POWER_OFF} ]; then
    echo -n "!!! ERROR:  Both \"${FORCE_WIFI_POWER_ON}\" " >>$LOG 2>&1
    echo "and \"${FORCE_WIFI_POWER_OFF}\"" >>$LOG 2>&1
    echo "    cannot exist at the same time." >>$LOG 2>&1
    echo "    Deleting both control files..." >>$LOG 2>&1
    rm -f ${FORCE_WIFI_POWER_ON} ${FORCE_WIFI_POWER_OFF} >>$LOG 2>&1
    echo "    Proceeding with default behavior..." >>$LOG 2>&1
elif [ -e ${FORCE_WIFI_POWER_OFF} ]; then
    echo "=== Forcing \"${ifc_device}\" off." >>$LOG 2>&1
    power_off_wifi "${ifc_device}" >>$LOG 2>&1
    rm -f ${FORCE_WIFI_POWER_OFF} >>$LOG 2>&1
elif [ -e ${FORCE_WIFI_POWER_ON} ]; then
    echo "=== Forcing \"${ifc_device}\" on." >>$LOG 2>&1
    wifi_power_is_on "${ifc_device}"
    if [ $? -eq 3 ]; then
        # No driver loaded for the WiFi interface.  Do that before we
        # try to power on.
        load_ifc_module "${ifc_device}"
    fi
    turn_on_wifi "${ifc_device}" >>$LOG 2>&1
    rm -f ${FORCE_WIFI_POWER_ON} >>$LOG 2>&1
else
    toggle_wifi_power "${ifc_device}" >>$LOG 2>&1
fi

echo "" >>$LOG 2>&1
echo "=== Done." >>$LOG 2>&1


#################
#
#  End
