#!/bin/sh
#
# Control bluetooth services and devices from ACPI.
#
# Copyright (C) 2012 by John P. Weiss
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


test -f /usr/share/acpi-support/state-funcs || exit 0
. /usr/share/acpi-support/state-funcs

. /etc/LocalSys/init.d/functions-laptop
LOGFILE=/tmp/bluetooth-acpi.log


############
#
# Functions
#
############


bluetoothServerIsRunning()
{
    service bluetooth status 2>&1 | grep -qi 'running'
}


pgrep_q()
{
    local p
    for p in "$@"; do
        # Stop as soon as we find the first matching process expression.
        pgrep -c "$p" >/dev/null 2>&1 && return 0
    done
}


XIsRunning()
{
    pgrep_q X
}


kdeIsRunning()
{
    pgrep_q kde
}


kdeBluetoothAppsRunning()
{
    pgrep_q kblue bluedevil
}


otherBluetoothAppsRunning()
{
    # N.B. - BlueZ is a collection of bluetooth agents and tools.  We'll grep
    # only for blueman and leave the earlier version in place for
    # documentation purposes.
    #pgrep_q bluez blueman
    pgrep_q blueman
}


anyBluetoothAppsRunning()
{
    XIsRunning || return 1
    pgrep_q kblue bluedevil blueman
}


removeStaleBluetooth()
{
    local someBluetoothExists=''

    if bluetoothServerIsRunning; then
        echo "  Old instance of \"bluetoothd\" still running."
        someBluetoothExists='y'
    fi

    if [ -d /sys/modules/bluetooth -o -d /sys/modules/btusb ]; then
        echo "  (Some) Bluetooth modules are still loaded."
        someBluetoothExists='y'
    fi

    if anyBluetoothAppsRunning; then
        echo "  Some Bluetooth systray apps are still running."
        someBluetoothExists='y'
    fi

    if [ -n "$someBluetoothExists" ]; then
        echo "Killing all Bluetooth-related processes and removing all "
        echo "Bluetooth-related modules."
        killBluetooth
    fi
}


findBluetoothTrayapp_other()
{
    # Don't do anything if there's already an applet running
    otherBluetoothAppsRunning && return

    # Right now, this just checks for the GTK/GNOME applet.
    local b
    for b in /usr/bin/blueman-applet; do
        if [ -x $b ]; then
            echo "$b"
            return 0
        fi
    done

    # else:
    return 1
}


findBluetoothTrayapp_kde()
{
    # Don't do anything if there's already an applet running
    kdeBluetoothAppsRunning && return

    local b
    for b in /usr/bin/{bluedevil,kbluetooth} /opt/trinity/bin/kbluetooth; do
        if [ -x $b ]; then
            echo "$b"
            return 0
        fi
    done

    # else:
    findBluetoothTrayapp_other
}


startBluetoothTrayapp()
{
    local appBin=""
    if kdeIsRunning; then
        appBin=`findBluetoothTrayapp_kde`
    else
        appBin=`findBluetoothTrayapp_other`
    fi

    # Stop if we didn't find a trayapp.
    [ -n "$appBin" ] || return 1

    # Get the necessary info about the user running X
    local guiUser=""

    # Get the X environment

    # Start the app as the user
    if [ -n "$guiUser" ]; then
        echo "Starting \"$appBin\" as \"$guiUser\"."
        su -c "$appBin" "$guiUser"
    fi
}


toggleBluetooth()
{
    # FIXME:  Stop the server?  Hit DBUS with some sort of "disable/enable"
    # message?
    toggleAllBluetoothAdapters


    # DBus files for the blueman-applet.  None appear to contain any useful
    # information.
    #
    #/usr/share/dbus-1/system-services/org.blueman.Mechanism.service
    #/usr/share/dbus-1/services/blueman-applet.service
    #/etc/dbus-1/system.d/org.blueman.Mechanism.conf
    #/etc/dbus-1/system.d/bluetooth.conf

    # mdbus2 finds:
    #
    # org.blueman.Applet / org.blueman.Applet.GetBluetoothStatus
    # org.blueman.Applet / org.blueman.Applet.SetBluetoothStatus {true|false}
    # 
    # org.kde.BlueDevil.Service /Service org.kde.BlueDevil.Service.isRunning
    # org.kde.BlueDevil.Service /Service org.kde.BlueDevil.Service.launchServer
    # org.kde.BlueDevil.Service /Service org.kde.BlueDevil.Service.stopServer
    #    'launchServer' and 'stopServer' don't seem to start any processes.
    #    They change the return value of 'isRunning' ... but not much else.
    # org.kde.BlueDevil.Service /MainApplication 
    #    This contains a variety of KDE-specific and QT-specific methods &
    #    properties.  None look all that useful, and I suspect that
    #    'org.kde.BlueDevil.Service' is not the trayapp.
    #
    # org.kde.bluedevilmonolithic /MainApplication
    #    Also contains KDE- and QT-specific methods & properties, but nothing
    #    related to turning bluetooth on/off.
    #    However, 'bluedevil-monolithic' *is* the systray-app.
    # 
}


doFullStart()
{
    echo "Bluetooth not running.  Performing full start..."

    rfkill unblock bluetooth
    service bluetooth start

    # FIXME:  Hit DBUS with some sort of "disable/enable" message?

    if XIsRunning; then
        startBluetoothTrayapp
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

# Punt if there's no Bluetooth adapter on the machine.
if hasBluetoothAdapter; then
    if bluetoothServerIsRunning; then
        toggleBluetooth >>$LOGFILE 2>&1
    else
        doFullStart >>$LOGFILE 2>&1
    fi
else
    removeStaleBluetooth >>$LOGFILE 2>&1
fi

echo "Done." >>$LOGFILE


######
# End
#
