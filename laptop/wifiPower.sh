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


IFC_NAME=eth1

LOG=/tmp/wifi-power.log


############
#
# Includes & Other Global Variables
#
############


MYPATH=`dirname $0`
IWCONFIG=/sbin/iwconfig
IFDOWN=/sbin/ifdown
STATE_SCRIPT='stateToggle.sh'


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
	"usage: $0 [<Options>] [--keeplog]"
	<Options>
	-i
	--ifc
	--ifname
	    Name of the WiFi network interface to turn on or off.  This
	    could be the name of the WiFi device's network interface, or it could
	    be a logical name of a WiFi interface device under a specific 
	    network profile.
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

# Determine what to do to the device.  wifi_power_is_on returns 0 (true) if
# the WiFi device is currently powered on.
if $(wifi_power_is_on "${ifc_device}"); then
    power_off_wifi "${ifc_device}" >>$LOG 2>&1
else
    turn_on_wifi "${ifc_device}" >>$LOG 2>&1
fi

echo "" >>$LOG 2>&1
echo "=== Done." >>$LOG 2>&1


#################
#
#  End
