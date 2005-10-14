#!/bin/bash
#
# Copyright (C) 2004-2005 by John P. Weiss
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

LOG=/tmp/sync-mode.log


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


############
#
# Functions
#
############


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
    profile_name="$1"
    shift

    if [ ! -x ${SWITCH_NET_PROFILE_CMD} -o -z "$profile_name" ]; then
        return 1
    fi
    # else:

    profile_active=$(grep "CURRENT_PROFILE=$profile_name" \
        /etc/sysconfig/network)
    if [ -z "$profile_active" ]; then
        # Only switch the profile if needed.
        $SWITCH_NET_PROFILE_CMD -p "$profile_name"
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

    # Change network profile back to "home base"
    switch_net_profile "${NET_PROFILE_NAME}"

    neton
    wait_for_connectivity
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
