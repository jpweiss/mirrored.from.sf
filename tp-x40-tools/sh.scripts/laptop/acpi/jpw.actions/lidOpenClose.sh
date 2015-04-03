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
# RCS $Id$
############


############
#
# Includes & Other Global Variables
#
############


myPath=`dirname $0`

PROC_LID=/proc/acpi/button/lid
SYSFS_LID=/sys/\?\?\?
SYS_CPUFREQ=/sys/devices/system/cpu/cpu0/cpufreq/


. $myPath/screenblanker.sh


############
#
# Functions
#
############


lid_is_closed()
{
    if [[ -d $PROC_LID ]]; then
        grep -q closed $PROC_LID/*/state
        return $?
    fi
    # else:

    # TODO:  Find where the lid info lives in /sys
}


cpufreq_set_powersave()
{
    echo "powersave" >>${SYS_CPUFREQ}/scaling_governor
}


cpufreq_set_autoAdjusting()
{
    local governor="ondemand"
    local powersrc=$(getState)

    if [ "${powersrc}" = "BATTERY" ]; then
        governor="conservative"
    fi
    echo "${governor}" >>${SYS_CPUFREQ}/scaling_governor

    local min max
    min=$(< ${SYS_CPUFREQ}/scaling_min_freq)
    max=$(< ${SYS_CPUFREQ}/scaling_max_freq)

    if [ "$min" != "$max" ]; then
        cat ${SYS_CPUFREQ}/cpuinfo_min_freq >>${SYS_CPUFREQ}/scaling_min_freq
        cat ${SYS_CPUFREQ}/cpuinfo_max_freq >>${SYS_CPUFREQ}/scaling_max_freq
    fi

    if [ -d ${SYS_CPUFREQ}/ondemand ]; then
        if [ -w ${SYS_CPUFREQ}/ondemand/up_threshold ]; then
            echo $ONDEMAND_UP_THRESH >>${SYS_CPUFREQ}/ondemand/up_threshold
        fi
    fi
}


toggle_low_power()
{
    if [ -n "$*" ]; then
        cpufreq_set_powersave
    else
        cpufreq_set_autoAdjusting
    fi
}


############
#
# Main
#
############


# If we have one, execute the initial-tasks script.
[ -x /etc/acpi/local/lid.sh.pre ] && /etc/acpi/local/lid.sh.pre


# DBG:  Comment out when not in use.
##echo "Running $0" >>/tmp/logs/acpi-debug-event.log
if lid_is_closed; then
    # N.B.:  We don't really need to blank the screen, but it's not hurting
    # anything to do so.
    ctrl_screenblank "closed"
    toggle_low_power "closed"
else
    toggle_low_power
    sleep 1
    # N.B.:  We don't really need to unblank the screen, but it's not hurting
    # anything to do so.
    ctrl_screenblank
    sleep 1
    reset_brightness
fi


# If we have one, execute the final-tasks script.
[ -x /etc/acpi/local/lid.sh.post ] && /etc/acpi/local/lid.sh.post


#################
#
#  End
