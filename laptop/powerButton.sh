#!/bin/bash
#
# Copyright (C) 2004-5 by John P. Weiss
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

if [ -f /tmp/.init.env ]; then 
    . /tmp/.init.env
fi

############
#
# Configuration Variables
#
############


HALT_TIME=${POWER_BUTTON_HALT_TIME:-1}
N_CLICKS_HALT=3
N_CLICKS_SUSPEND=2
HALT_CLICK_INTERVAL=2

SHUTDOWN_PIDFILE=/var/run/shutdown.pid

MAX_INTERCLICK_TIME=5

IGNORE_CFG_HALTNOW__FILE=/tmp/.halt.now
SUSPEND_INSTEAD_OF_HALT__FILE=/tmp/.suspend
KBD_HANDLER=''
KBD_DEV=''


############
#
# Includes & Other Global Variables
#
############


HISTFILE=/tmp/.powerButton.log
COUNTFILE=/tmp/.powerButton.clicks.log
PRETEND=''
N_CLICKS=0
N_SEC=0
PROC_INPUTDEVS=/proc/bus/input/devices
SYS_INPUTDEVS=/sys/class/input


############
#
# Functions
#
############


parse_inputdev() {
    is_first='y'
    while read -a line; do
        if [ "${line[0]}" != "H:" ]; then
            continue
        fi # else
        line[1]=${line[1]#Handlers=}
        unset line[0]
        found=1
        for elt in "${line[@]}"; do
            case $elt in
                kbd)
                    found=0
                    echo "${line[@]}"
                    return
                    ;;
                *)
                    found=1
                    ;;
            esac 
        done
    done
}


find_kbdhandler() {
    set -- `cat $PROC_INPUTDEVS | parse_inputdev`
    while [ -n "$1" ]; do
        if [ -e ${SYS_INPUTDEVS}/$1/dev ]; then
            KBD_HANDLER=${SYS_INPUTDEVS}/$1/dev
            KBD_DEV=/dev/input/$1
            return
        fi
        shift
    done
}


do_halt() {
    if [ -f $IGNORE_CFG_HALTNOW__FILE ]; then
	    HALT_TIME=0
        rm -f $IGNORE_CFG_HALTNOW__FILE >/dev/null 2>&1
    elif [ $HALT_TIME -lt 0 ]; then
        HALT_TIME=1
    fi
    rm $COUNTFILE
    $PRETEND shutdown -h $HALT_TIME "Powering Down."
}


cancel_halt() {
    if [ -f $SHUTDOWN_PIDFILE -o ! -f $COUNTFILE ]; then
        $PRETEND shutdown -c "Power-Down canceled."
        touch $COUNTFILE
        echo "Power-Down canceled." >> $HISTFILE
        # If we're still running shutdown, forcibly cancel it.
        if [ -f $SHUTDOWN_PIDFILE ]; then
            kill -9 $(< $SHUTDOWN_PIDFILE)
            rm -f $SHUTDOWN_PIDFILE
        fi
        if [ -f /etc/nologin ]; then
            rm -f /etc/nologin
        fi
        return 0
    fi
    # else
    return 1
}


count_clicks() {
    evtype="$1"
    shift
    ev_which="$1"
    shift
    ev_code="0x$1"
    shift
    ev_count=$((0x$1))
    shift

    now=`date +%s`
    first_ts=$now
    first_count=$((ev_count - 1))
    delta_ts=0
    delta_count=0
    echo "$now: '$evtype' '$ev_which' $ev_code $ev_count" >> $HISTFILE

    if [ -f $COUNTFILE ]; then
        set -- $(< $COUNTFILE)
        if [ $# -gt 3 ]; then
            first_ts="$1"
            first_count="$2"
            last_ts="$3"
            last_count="$4"
            delta_ts=$((now - last_ts))
            # A pure delta would ignore the 1st click-depress, hence the +1
            N_CLICKS=$(((ev_count - first_count + 1) / 2))
        fi
    fi
    N_SEC=$((now - first_ts))

    if [ $N_CLICKS -le 1 -a $delta_ts -gt $MAX_INTERCLICK_TIME ]; then
        # Under 1 click per $MAX_INTERCLICK_TIME sec ==> Treat as new event. 
        echo "$now $ev_count $now $ev_count" > $COUNTFILE
    elif [ $N_SEC -gt $((MAX_INTERCLICK_TIME * 2)) ]; then
        # Double the $MAX_INTERCLICK_TIME is our limit for absolute time
        # elapsed since the first click
        echo "$now $ev_count $now $ev_count" > $COUNTFILE
    else
        # Update the counts.
        echo "$first_ts $first_count $now $ev_count" > $COUNTFILE
    fi
}


do_unit_test() {
    PRETEND=echo

    count_clicks $@
    echo "N_CLICKS==$N_CLICKS"
    echo "N_SEC==$N_SEC"
    if [ $N_CLICKS -ge $N_CLICKS_HALT -a \
        $N_SEC -le $HALT_CLICK_INTERVAL ]; then
        echo "Would halt: "
        echo "    N_CLICKS_HALT==$N_CLICKS_HALT"
        echo "    HALT_CLICK_INTERVAL==$HALT_CLICK_INTERVAL"
    fi

    if cancel_halt; then
        : # Nothing more to do.
    elif [ $N_CLICKS -ge $N_CLICKS_HALT -a \
        $N_SEC -le $HALT_CLICK_INTERVAL ]; then
        do_halt
    fi

    echo "Handler file (before): \"$KBD_HANDLER\"  Device: \"$KBD_DEV\""
    cat $PROC_INPUTDEVS | parse_inputdev
    find_kbdhandler
    echo "Handler file (found?): \"$KBD_HANDLER\"  Device: \"$KBD_DEV\""

    exit 0
}


############
#
# Main
#
############


if [ "$1" = "--unit_test" ]; then
    shift
    # NOTE:
    # You should 'tail -f /var/log/acpid' to see the output generated by the
    # unit tests.
    do_unit_test "$@"
    exit 0
fi


if cancel_halt; then
    # Nothing more to do.
    exit 0
fi

count_clicks $@

chmod -f a+r,go-w $HISTFILE $COUNTFILE >/dev/null 2>&1

if [ -f $SUSPEND_INSTEAD_OF_HALT__FILE ]; then
    if [ $N_CLICKS -ge $N_CLICKS_SUSPEND -a \
        $N_SEC -le $HALT_CLICK_INTERVAL ]; then
        #rm -f $SUSPEND_INSTEAD_OF_HALT__FILE >/dev/null 2>&1
        rm -f $COUNTFILE >/dev/null 2>&1
        exec /etc/acpi/actions/suspenders.sh
        exit 1  # if exec failed
    fi
fi # else

if [ $N_CLICKS -ge $N_CLICKS_HALT -a $N_SEC -le $HALT_CLICK_INTERVAL ]; then
    rm -f $SUSPEND_INSTEAD_OF_HALT__FILE >/dev/null 2>&1
    do_halt
fi


#################
#
#  End
