#!/bin/bash
#
# Copyright (C) 2002 by John P. Weiss
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


############
#
# Includes & Other Global Variables
#
############


HISTFILE=/tmp/.lidButton.log


############
#
# Functions
#
############


do_standby() {
    echo "standby" > /sys/power/state
    touch $HISTFILE
    # Alternate:
    # echo 1 > /proc/acpi/sleep       # for standby
    # echo 4 > /proc/acpi/sleep       # for suspend to disk
}


do_resume() {
}


process_and_powerdown() {
    set -- $1
    count=$((0x$4))

    # Even counts are the button release
    if [ $(((count / 2) * 2)) -ne $count ]; then
        return 1
    fi

    now=`date +%s`
    echo "$now: '$1' '$2' 0x$3 $count" >> $HISTFILE

    if [ $N_CLICKS_HALT -lt 2 ]; then
        N_CLICKS_HALT=2
    fi
    nclicks=`grep -c "$now:" $HISTFILE`
    nclicks1sec=`grep -c "$((now-1)):" $HISTFILE`
    nclicks=$((nclicks + $nclicks1sec))
    if [ $nclicks -ge $N_CLICKS_HALT ]; then
        if [ -f /tmp/.halt.now ]; then
	    HALT_TIME=0
        fi
        return 0
    fi
    # else
    return 1
}


############
#
# Main
#
############


oldArg1="$1"
echo "$1" >> /tmp/lidEvent.log
##/home/candide/tmp/test.sh


#################
#
#  End
