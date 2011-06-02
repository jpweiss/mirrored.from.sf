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

local iwconfig_failed
iwconfig_failed='n'
if isAnyWirelessPoweredOn; then
    echo "Found active WiFi; disabling..." >>$LOGFILE
    iwconfig eth1 txpower off >>$LOGFILE 2>&1 || iwconfig_failed='y'
    isAnyWirelessPoweredOn && iwconfig_failed='y'

    if [ "$iwconfig_failed" = 'y' ]; then
        echo "    'iwconfig' failed to disable TX power!" >>$LOGFILE 2>&1
        echo "    Attempting direct kernel param manipulation" \
            >>$LOGFILE 2>&1

        killWifi >>$LOGFILE 2>&1
    fi
else
    echo "Enabling WiFi..." >>$LOGFILE
    loadWifiModules >>$LOGFILE 2>&1

    iwconfig eth1 txpower on >>$LOGFILE 2>&1 || iwconfig_failed='y'
    isAnyWirelessPoweredOn || iwconfig_failed='y'

    if [ "$iwconfig_failed" = 'y' ]; then
        echo "    'iwconfig' failed to reenable TX power!" >>$LOGFILE 2>&1
        echo "    Attempting direct kernel param manipulation" \
            >>$LOGFILE 2>&1

        local d rfk
        for d in /sys/class/net/*; do
            rfk=$d/device/rf_kill
            if [ -w $rfk ]; then
                # '1' means "turn it off"
                if [ "`cat $rfk`" = "1" ]; then
                    echo "    Disabling rf_kill..." >>$LOGFILE 2>&1
                    echo 0 >>$rfk
                fi
            fi
        done
    fi
fi
toggleBluetooth

echo "Done." >>$LOGFILE


######
# End
#
