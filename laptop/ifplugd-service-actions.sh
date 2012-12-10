#!/bin/bash
#
# Copyright (C) 2004-2009, 2012 by John P. Weiss
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


SERVICES="ssh privoxy samba cups"

LAN_IFC=eth0
IFC_HOSTNAME=mloe
REMOTE_HOSTNAME=uqbar
PING_TIMEOUT=10
PING_COUNT=5
IFUP_TIMEOUT=15

NETCHECK_WAIT=15
NETCHECK_MAX=20 # 12 <==> 5m / 25s

WAIT_TO_DRAINQ="2m"

LOG=/tmp/logs/sync-mode.log

# How old the logfile should be in order to trigger an NTP-sync.
# In units of days.
LOG_AGE_TRIGGER=7


############
#
# Includes & Other Global Variables
#
############


#. some.include.sh

SERVICE=/usr/bin/service
MAILQ=/usr/bin/mailq
POSTQUEUE=/usr/sbin/postqueue
NTP_SYNC=/etc/LocalSys/maintenance-scripts/xntp-sync.sh

# Based on the modification time of the log file, trigger certain things.
LOG_OLDER_THAN_AGE_TRIGGER=""

MY_NAME="ifplugd-service-actions.sh"


############
#
# Functions
#
############


check_logfile_age() {
    case "$LOG_AGE_TRIGGER" in
        [^0-9]*|*[^0-9])
            LOG_OLDER_THAN_AGE_TRIGGER="t"
            return 0
            ;;
    esac
    if [ -z "$LOG" -o -z "$LOG_AGE_TRIGGER" ]; then
        # Do nothing if the cfgvars aren't set correctly.
        echo "Error:  $0 is misconfigured.  Missing setting(s):"
        echo "    \$LOG==$LOG"
        echo "    \$LOG_AGE_TRIGGER==$LOG_AGE_TRIGGER"
        return 0
    fi

    if [ -e $LOG ]; then

        rm -f ${LOG}--datecheck >/dev/null 2>&1 && \
            touch --date="-${LOG_AGE_TRIGGER} day" ${LOG}--datecheck

        retstat=$?
        if [ -e ${LOG}--datecheck ]; then
            if [ ${LOG}--datecheck -nt ${LOG} ]; then
                LOG_OLDER_THAN_AGE_TRIGGER="t"
            fi
            rm -f ${LOG}--datecheck >/dev/null 2>&1
        else
            # Don't force the trigger in the event of any sort of error.
            return $retstat
        fi

    else
        # Treat "log missing" as "log is ancient".
        LOG_OLDER_THAN_AGE_TRIGGER="t"
    fi

    return 0
}


pingcheck_unavailable() {
    pingTimeout=$1
    shift
    pingCount=$1
    shift
    pingHostOrIP=$1
    shift

    ping -q -w ${pingTimeout} -c ${pingCount} ${pingHostOrIP} \
        >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        return 1
    fi # else
    return 0
}


ifc_unavailable() {
    pingTimeout=$1
    shift
    pingCount=$1
    shift

    pingcheck_unavailable ${pingTimeout} ${pingCount} ${IFC_HOSTNAME}
    return $?
}


network_unavailable() {
    pingTimeout=$1
    shift
    pingCount=$1
    shift

    pingcheck_unavailable ${pingTimeout} ${pingCount} ${REMOTE_HOSTNAME}
    return $?
}


wait_for_connectivity() {
    i=0
    while `network_unavailable ${PING_TIMEOUT} ${PING_COUNT}`; do
        let i++
        if [ $i -gt $NETCHECK_MAX ]; then
            echo ""
            echo -n "Failed to find any connectivity to host "
            echo "\"${REMOTE_HOSTNAME}\"."
            echo "Aborting."
            exit 2
        fi
        sleep ${NETCHECK_WAIT}
        echo -n "."
        if [ $((i % 10)) -eq 0 ]; then
            echo "No connectivity found after $i tries."
        fi
    done

    echo ""
    echo "Network is up."
}


sync_clock() {
    if [ ! -x $NTP_SYNC -o -z "$LOG_OLDER_THAN_AGE_TRIGGER" ]; then
        return 0
    fi

    $NTP_SYNC ntpdate 2>&1 >>${LOG}
}


mail_queued() {
    case `$MAILQ` in
        *is*empty*)
            return 1
            ;;
    esac
    # Default:
    return 0
}


drainq() {
    nowait=''
    if [ "$1" == nowait ]; then
        nowait='y'
    fi

    i=0
    while `mail_queued`; do
        let i++
        $POSTQUEUE -f
        if [ -n "$nowait" ]; then
            return 0
        fi
        sleep ${WAIT_TO_DRAINQ}
        if [ $((i % 10)) -eq 0 ]; then
            echo "Mail queue still not empty after $i tries."
        fi
    done
}


service_start_or_restart() {
    svc=$1
    shift

    # Do nothing if not run by root.
    if [ $UID -ne 0 ]; then
        return 1
    fi

    case `$SERVICE "$svc" status` in
        *[Ss]topped*)
            $SERVICE "$svc" restart
            ;;
        *unrecognized*|*unknown*)
            return 1
            ;;
        *)
            # Default:  Assume $sv wasn't running.
            $SERVICE "$svc" start
            ;;
    esac
    return 0
}


service_stop() {
    svc=$1
    shift

    # Do nothing if not run by root.
    if [ $UID -ne 0 ]; then
        return 1
    fi

    $SERVICE "$svc" stop
}


start_tasks() {
    wait_for_connectivity

    # Run this one first, and only at startup
    sync_clock

    # Start the rest
    for s in $SERVICES; do
        service_start_or_restart $s
    done

    # Run this one last.
    drainq
}


stop_tasks() {
    # Run this one first.
    drainq nowait

    # Stop the rest
    for s in $SERVICES; do
        service_stop $s >>$LOG 2>&1
    done
}


first_mesg() {
    what="$1"
    shift

    echo ""
    echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    echo ""
    date
    echo ""
    echo "=== ${MY_NAME}:  $what Services:"
}


############
#
# Main
#
############


# Begin by checking how old $LOG is before anything starts writing to it.
check_logfile_age


# Process the name under which this script ran.
is_named_start=''
is_named_stop=''
clearlog='y'
case "$0" in
    *start*|*-up*)
        is_named_start='y'
        export MODE="start"
        export PHASE="up"
        clearlog=''
        ;;
    *stop*|*-down*)
        is_named_stop='y'
        export MODE="stop"
        export PHASE="down"
        ;;
esac
MY_NAME=${0##*/}


# Now we can process the commandline options.
clearlog='y'
while [ -n "$1" ]; do
    arg="$1"
    shift
    case "$arg" in
        -H|-n|--hostname)
            shift
            IFC_HOSTNAME=$1
            ;;
        -c|--ping_count)
            shift
            PING_COUNT=$1
            ;;
        -t|--ping_timeout)
            shift
            PING_TIMEOUT=$1
            ;;
        --keeplog)
            clearlog=''
            ;;
        --start|start|up)
            start='y'
            stop=''
            ;;
        --stop|stop|down)
            stop='y'
            start=''
            ;;
        --help|-h)
            start=''
            stop=''
            break
            ;;
        [eilw]*)
            export IFACE="$arg"
            export LOGICAL="$arg"
    esac
done
[ "$IFACE" = "$LAN_IFC" ] || exit 0
export ADDRFAM="NetworkManager"
export METHOD="NetworkManager"


if [ -n "$start" ]; then

    if [ -z "$is_named_stop" ]; then
        if [ -n "$clearlog" ]; then
            rm -f $LOG >/dev/null 2>&1
        fi

        first_mesg "Starting" >>$LOG 2>&1
        start_tasks >>$LOG 2>&1
    fi
    # else:
    # Script name contains "stop", so ignore requests to start.

elif [ -n "$stop" ]; then

    if [ -z "$is_named_start" ]; then
        first_mesg "Stopping" >>$LOG 2>&1
        stop_tasks >>$LOG 2>&1
    fi
    # else:
    # Script name contains "start", so ignore requests to stop.

else
    (cat - <<-EOF
	"usage: $MY_NAME [<Options>] \\
	                {[--keeplog] {start | up} | {stop | down}"
	"usage: <prefix>start<suffix> [<Options>] up"
	"usage: <prefix>stop<suffix> [<Options>] down"

	<Options>
	-H
	-n
	--hostname
	    Name of a host on the network of the target interface.
	    $MY_NAME pings this host to determine if/when
	    the interface has come up.
	-c
	--ping_count
	    How many times to ping the target network before deciding that
	    it's not active.
	-t
	--ping_timeout
	    How long (in seconds) to ping the target network before deciding
	    that it's not active.
	start
	up
	--start
	    Start services.  Also syncs the clock using NTP, and drains the mail
	    queue.
	stop
	down
	--stop
	    Stops services.


	Special Options
	-h
	--help
	    This message.
	--keeplog
	    Appends to, instead of overwriting, an existing logfile.  Only used by
	    the "start" mode.
	[eiwl]*
	    Any argument starting with an 'e', 'i', 'w', or 'l' is assumed to be
	    the name of a network interface.  If it's "lo", then
	    $MY_NAME exits.

	Any commandline arguments or options not listed above are ignored.


	Special Script Names

	In addition to running this script manually, you can also run it from
	a symlink with a special name.  When the symlink (or filename) matches one
	of the following patterns, $MY_NAME behaves as follows:

	*start*
	*-up*
	    a) The '--keeplog' option is enabled.
	    b) Ignores the 'stop', '--stop', or 'down' options.
	       [They're effectively a no-op.]

	*stop*
	*-down*
	    Ignores the 'start', '--start', or 'up' options.
	    [They're effectively a no-op.]
EOF
    ) | tee -a $LOG
    exit 1
fi
echo "" >>$LOG 2>&1
echo "=== Done." >>$LOG 2>&1


#################
#
#  End
