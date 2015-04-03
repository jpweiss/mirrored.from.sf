#!/bin/bash
#
# Copyright (C) 2013-2015 by John P. Weiss
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
# Includes & Other Global Variables
#
############


myPath=`dirname $0`

BRIGHTNESS_CTRL_PROC=/proc/acpi/ibm/brightness
BRIGHTNESS_CTRL_SYS=/sys/class/backlight/thinkpad_screen
LASTCONSOLE_FILE=/var/local/vtSwitch-lastConsole


if [ ! -f $myPath/tools-runX.sh ]; then
    echo "$0 FAILED!  Could not find $myPath/tools-runX.sh" \
        >>/tmp/logs/acpi-errors.log
    exit 1
fi
. $myPath/tools-runX.sh


############
#
# Functions
#
############


reset_brightness()
{
    if [[ -r $BRIGHTNESS_CTRL_PROC ]]; then
        set -- $(grep '^level:' $BRIGHTNESS_CTRL)
        local cur_lvl="$2"

        # We can't just feed the current level back in.  The kernel ignores it.
        # So, we need to set it to something else, first.
        echo "level 0" >$BRIGHTNESS_CTRL
        echo "level $cur_lvl" >$BRIGHTNESS_CTRL
    else
        local cur_lvl=$(cat $BRIGHTNESS_CTRL_SYS/actual_brightness)

        # Let's assume that we'll have the same problem with feeding the
        # current level back in.
        echo 0 >$BRIGHTNESS_CTRL_SYS/brightness
        echo $cur_lvl >$BRIGHTNESS_CTRL_SYS/brightness
    fi
}


toggle_blank_via_xset()
{
    if [ -n "$*" ]; then
        runXCmd_allXServers "xset s activate"
    else
        runXCmd_allXServers "xset s reset" \
            "xset s blank" \
            "xset s on"

        reset_brightness
    fi
}


toggle_vbe_dpms()
{
    if [ -n "$*" ]; then
        touch /tmp/logs/running-vbetool_dpms_off
        vbetool dpms off
    else
        touch /tmp/logs/running-vbetool_dpms_on
        vbetool dpms on
    fi
}


reenable_vt()
{
    local xdisplay="$1"
    shift
    local user="$1"
    shift
    local xauth="$1"
    shift
    is_off_line="$1"
    shift

    if [ -z "$user" ]; then
        return 1
    fi

    local oldDISPLAY="$DISPLAY"
    export DISPLAY="$xdisplay"
    local oldXAUTHORITY="$XAUTHORITY"
    export XAUTHORITY="$xauth"

    pidof xscreensaver >/dev/null && xscreensaver_running=y

    # 'is_off_line' set from the exitval of
    # `grep -q off-line /proc/acpi/ac_adapter/*/state`
    if [ "$is_off_line" = "1" ]; then
        if [ -n "$xscreensaver_running" ]; then
            su $user -c "xscreensaver-command -unthrottle"
        fi
    fi

    if [ -n "$xscreensaver_running" ]; then
        su $user -c "xscreensaver-command -deactivate"
    fi

    su $user -c "xset dpms force on"

    export DISPLAY="$oldDISPLAY"
    export XAUTHORITY="$oldXAUTHORITY"
}


toggle_vt()
{
    if [ -n "$*" ]; then

        fgconsole >$LASTCONSOLE_FILE
        chvt 1

        runXCmd_allXServers "xset dpms force off"

    else

        lastConsole=7
        if [ -r $LASTCONSOLE_FILE ]; then
            lastConsole=`cat $LASTCONSOLE_FILE`
        fi
        chvt $lastConsole

        grep -q off-line /proc/acpi/ac_adapter/*/state
        is_off_line="$?"
        runXCmd_allXServers -f reenable_vt $is_off_line

    fi
}


ctrl_screenblank()
{
    local doBlank=''
    case "$1" in
        [Yy]*|*[Cclosed]*|*[Oo]n*)
            doBlank="y"
            ;;
        # Anything else means turn off screenblanking.
    esac

    ## [jpw] Uncomment the correct function for your laptop:
    #toggle_vt $doBlank
    #toggle_vbe_dpms $doBlank
    #toggle_dpms $doBlank
    toggle_blank_via_xset $doBlank
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
    # Was run as a script.

    # When run as a script, instead of used as a library, always blank the
    # screen.

    # DBG:  Comment out when not in use.
    ##echo "Running $0" >>/tmp/logs/acpi-debug-event.log
    ctrl_screenblank "on"
fi


#################
#
#  End
