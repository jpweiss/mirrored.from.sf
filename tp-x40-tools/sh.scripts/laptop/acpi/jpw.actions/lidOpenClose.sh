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


myPath=`dirname $0`


BRIGHTNESS_CTRL=/proc/acpi/ibm/brightness
SYS_CPUFREQ=/sys/devices/system/cpu/cpu0/cpufreq/


. $myPath/screenblanker.sh
. /usr/share/acpi-support/policy-funcs
. /etc/default/acpi-support

if type -t getState >/dev/null; then
    :
else
    . /usr/share/acpi-support/power-funcs
fi


############
#
# Functions
#
############


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


test -f /usr/share/acpi-support/state-funcs || exit 0


[ -x /etc/acpi/local/lid.sh.pre ] && /etc/acpi/local/lid.sh.pre

# DBG:  Comment out when not in use.
##echo "Running $0" >>/tmp/logs/acpi-debug-event.log
grep -q closed /proc/acpi/button/lid/*/state
if [ $? = 0 ]; then
    ctrl_screenblank "closed"
    toggle_low_power "closed"
else
    toggle_low_power
    sleep 1
    ctrl_screenblank
    sleep 1
    reset_brightness
fi

[ -x /etc/acpi/local/lid.sh.post ] && /etc/acpi/local/lid.sh.post


#################
#
#  End
