#!/bin/sh

test -f /usr/share/acpi-support/state-funcs || exit 0

# Find and toggle wireless of bluetooth devices on ThinkPads

. /usr/share/acpi-support/state-funcs
. /etc/LocalSys/init.d/functions-laptop
LOGFILE=/tmp/wifi-acpi.log


toggleBluetooth()
{
    [ -e /tmp/Fn-F5.ctrl-bluetooth ] || return 0

    echo "Checking Bluetooth..." >>$LOGFILE

    rfkill list |\
        sed -n -e'/tpacpi_bluetooth_sw/,/^[0-9]/p' |\
        grep -q 'Soft blocked: yes'
    bluetooth_state=$?

    # Sequence is Both on, Both off, Wireless only, Bluetooth only
    if ! isAnyWirelessPoweredOn; then
        # Wireless was turned off
        if [ "$bluetooth_state" = 0 ]; then
            echo "Bluetooth currently turned off; reenabling..." >>$LOGFILE
            rfkill unblock bluetooth >>$LOGFILE 2>&1
        else
            echo "Disabling Bluetooth..." >>$LOGFILE
            rfkill block bluetooth >>$LOGFILE 2>&1
            #killBluetooth
        fi
    fi
}


echo "" >>$LOGFILE
echo "#################### `date` ####################" \
    >>$LOGFILE
echo "" >>$LOGFILE

# FIXME::[jpw;2010-11-13]
# Something else is running when Fn-F5 is hit, in addition to this script.
# Soooo... we'll let it run, then we'll ... um ... Wait.  If we then run this
# script after waiting, we'll _reverse_ the change.  So that won't work.
#
# The upshot is:  we have a race-condition between this script and whatever
# else is running.

if isAnyWirelessPoweredOn; then
    echo "Found active WiFi; disabling..." >>$LOGFILE
    killWifi >>$LOGFILE 2>&1
else
    echo "Enabling WiFi..." >>$LOGFILE
    local mod=ipw2200
    if [ ! -d /sys/module/$mod ]; then
        #modprobe --quiet $mod
        modprobe --quiet $mod >>$LOGFILE 2>&1
    fi
    local d
    for d in /sys/class/net/*; do
        if [ -w $d/device/rf_kill ]; then
            # '1' means "turn it on," not kill the rf.
            echo 1 >>$d/device/rf_kill
        fi
    done
fi
toggleBluetooth

echo "Done." >>$LOGFILE


######
# End
#
