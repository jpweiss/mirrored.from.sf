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
# RCS $Id$
############


############
#
# Configuration Variables
#
############


IFC_NAME=eth0_home
IFC_HOSTNAME=mloe
REMOTE_HOSTNAME=uqbar
PING_TIMEOUT=10
PING_COUNT=5
IFUP_TIMEOUT=15

NETCHECK_WAIT=15
NETCHECK_MAX=20 # 12 <==> 5m / 25s

# Give the network a bit of time to change state after an ifup/ifdown.
IFC_STATE_WAIT=10

WAIT_TO_DRAINQ="2m"

# Set to empty string to disable profile switching on start/restart
NET_PROFILE_NAME=vslannet

# The name of the profile which will allow your sendmail/postfix installation
# to deliver its queued mail.
MAIL_PROFILE_NAME=vslannet

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

SERVICE=/sbin/service
MAILQ=/usr/bin/mailq
POSTQUEUE=/usr/sbin/postqueue
SWITCH_NET_PROFILE_CMD=/usr/sbin/system-config-network-cmd
SYSCFG_NETPATH=/etc/sysconfig/network-scripts
NTP_SYNC=/etc/LocalSys/maintenance-scripts/xntp-sync.sh

# Based on the modification time of the log file, trigger certain things.
LOG_OLDER_THAN_AGE_TRIGGER=""


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


switch_net_profile() {
    desired_ifc_name="$1"
    shift
    desired_profile_name="$1"
    shift
    force="$1"
    shift

    if [ ! -x ${SWITCH_NET_PROFILE_CMD} -o \
        -z "$desired_ifc_name" -o \
        -z "$desired_profile_name" ]; then
        return 1
    fi
    # else:

    ifc_active=$(ls -1 /etc/sysconfig/network-scripts  2>/dev/null |\
        grep "$desired_ifc_name")
    if [ -z "$ifc_active" -o -n "$force" ]; then
        # Only switch the profile if needed.
        $SWITCH_NET_PROFILE_CMD -p "$desired_profile_name"
    fi
}


netoff() {
    nowait=''
    if [ "$1" == nowait ]; then
        nowait='y'
    fi

    /sbin/ifdown ${IFC_NAME%%:*}
    if [ -z "$nowait" ]; then
        sleep ${IFC_STATE_WAIT}
    fi
}


neton() {
    # Initial quickcheck
    if `ifc_unavailable 10 3`; then
        sleep 5
        /sbin/ifup ${IFC_NAME}
        sleep ${IFC_STATE_WAIT}
    else
        # The IFC is already up.  Nothing more to do.
        echo "Already Connected:  \"$IFC_NAME\""
        return 0
    fi

    i=0
    while `ifc_unavailable ${PING_TIMEOUT} ${PING_COUNT}`; do
        let i++
        sleep ${IFUP_TIMEOUT}
        /sbin/ifup ${IFC_NAME}
        sleep ${IFC_STATE_WAIT}
        echo -n "."
        if [ $((i % 10)) -eq 0 ]; then
            echo "No connection established on \"$IFC_NAME\" after $i tries."
        fi
    done

    ethtool -s $IFC_NAME wol d
    echo ""
    echo "Connected:  \"$IFC_NAME\""
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
    if [ ! -x $NTP_SYNC -o z "$LOG_OLDER_THAN_AGE_TRIGGER" ]; then
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
    resume="$1"
    shift

    if [ -n "$resume" ]; then
        netoff
    fi

    # Change network profile back to "home base", using the profile that will
    # let you send off your queued mail.
    `mail_queued` && mustDrainQ=y
    if  [ -n "$mustDrainQ" -a -n "${MAIL_PROFILE_NAME}" ]; then
        switch_net_profile "${IFC_NAME}" "${MAIL_PROFILE_NAME}" $mustDrainQ
    else
        switch_net_profile "${IFC_NAME}" "${NET_PROFILE_NAME}" $mustDrainQ
    fi

    neton
    wait_for_connectivity

    # Run this one first, and only at startup
    sync_clock

    service_start_or_restart sshd

    # Run this one last.
    drainq
}


stop_tasks() {
    # Run this one first.
    drainq nowait
    service_stop sshd >>$LOG 2>&1
    netoff nowait >>$LOG 2>&1
}


determine_state() {
    mypath=$(dirname $0)
    state_script='stateToggle.sh'

    $mypath/$state_script lan_state $IFC_NAME
}


first_mesg() {
    what="$1"
    shift

    echo ""
    echo "- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -"
    echo ""
    date
    echo ""
    echo "=== $what Docked-Mode:"
}


############
#
# Main
#
############


# Begin by terminating any other running instance of this script:
for pid in `pgrep sync-mode`; do
    if [ $pid -ne $$ ]; then
        kill -15 $pid
    fi
done

# Next, check how old $LOG is before anything starts writing to it.
check_logfile_age

# Now we can process the commandline options.
resume=''
start=''
stop=''
clearlog='y'
while [ -n "$1" ]; do
    arg="$1"
    shift
    if [ "${arg##--}" = "toggle" ]; then
        arg=`determine_state`
    fi
    case "$arg" in
        -i|--ifc|--ifname)
            shift
            IFC_NAME=$1
            ;;
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
        -p|--profile)
            NET_PROFILE_NAME="$1"
            shift
            ;;
        --keeplog)
            clearlog=''
            ;;
        --resume|resume)
            resume='y'
            ;;
        --start|start)
            start='y'
            ;;
        --stop|stop)
            stop='y'
            ;;
        *)
            start=''
            stop=''
            break
            ;;
    esac
done


if [ -n "$start" ]; then
    if [ -n "$clearlog" ]; then
        rm -f $LOG >/dev/null 2>&1
    fi

    first_mesg "Starting" >>$LOG 2>&1
    start_tasks $resume >>$LOG 2>&1
elif [ -n "$stop" ]; then
    first_mesg "Stopping" >>$LOG 2>&1
    stop_tasks >>$LOG 2>&1
else
    (cat - <<-EOF
	"usage: $0 [<Options>] {[--keeplog] start | stop | toggle}"
	<Options>
	--keeplog
	    Appends to, instead of overwriting, an existing logfile.  Only used by
        the "start" (or the "toggle" mode when behaving as "start").
	-i
	--ifc
	--ifname
	    Name of the network interface to activate/deactivate.  This
	    could be the name of the network interface device, or it could
	    be a logical name of an interface device under a specific
	    network profile.  See the "--profile" option for more info.
	-H
	-n
	--hostname
	    Name of a host on the network of the target interface.
	    $0 pings this host to determine if/when
	    the interface has come up.
	-c
	--ping_count
	    How many times to ping the target network before deciding that
	    it's not active.
	-t
	--ping_timeout
	    How long (in seconds) to ping the target network before deciding
	    that it's not active.
	-p
	--profile
	    The name of a network profile to switch to before activating the
	    network interface.
	--resume
	    Used with "start":	Are we starting after a resume from
	    sleep/hibernation?	If so, turn the target network interface off
	    first.
EOF
    ) | tee -a $LOG
    exit 1
fi
echo "" >>$LOG 2>&1
echo "=== Done." >>$LOG 2>&1


#################
#
#  End
