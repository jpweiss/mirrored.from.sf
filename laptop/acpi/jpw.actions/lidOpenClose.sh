#!/bin/bash
#
# Copyright (C) 2013 by John P. Weiss
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
# Includes & Other Global Variables
#
############


if [ ! -f /etc/acpi/jpw.actions/tools-runX.sh ]; then
    echo "$0 FAILED!  Could not find /etc/acpi/jpw.actions/tools-runX.sh" \
        >>/tmp/logs/acpi-errors.log
    exit 1
fi
. /etc/acpi/jpw.actions/tools-runX.sh


if type -t getXuser; then
    :
else
    . /usr/share/acpi-support/power-funcs
fi
. /usr/share/acpi-support/policy-funcs
. /etc/default/acpi-support


LASTCONSOLE_FILE=/var/local/lidClose-lastConsole


############
#
# Functions
#
############


toggle_screenblank()
{
    if [ -n "$*" ]; then
        runXCmd_allXServers "xset s activate"
    else
        runXCmd_allXServers "xset s reset" \
             "xset s blank" \
             "xset s on"

        # FIXME:  Add something to reset the brightness to whatever is in the
        # ROM.
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
    DISPLAY="$1"
    shift
    local user="$1"
    shift
    XAUTHORITY="$1"
    shift
    is_off_line="$1"
    shift

    export DISPLAY
    export XAUTHORITY

    if [ -z "$user" ]; then
        return 1
    fi

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
        if [ `CheckPolicy` = 0 ]; then exit; fi

        grep -q off-line /proc/acpi/ac_adapter/*/state
        is_off_line="$?"
        runXCmd_allXServers -f reenable_vt $is_off_line

    fi
}


############
#
# Main
#
############


test -f /usr/share/acpi-support/state-funcs || exit 0


[ -x /etc/acpi/local/lid.sh.pre ] && /etc/acpi/local/lid.sh.pre

grep -q closed /proc/acpi/button/lid/*/state
if [ $? = 0 ]; then
    :
    #toggle_vt "closed"
    #toggle_vbe_dpms "closed"
    #toggle_dpms "closed"
    toggle_screenblank "closed"
else
    :
    #toggle_vt
    #toggle_vbe_dpms
    #toggle_dpms
    toggle_screenblank
fi

[ -x /etc/acpi/local/lid.sh.post ] && /etc/acpi/local/lid.sh.post


#################
#
#  End
