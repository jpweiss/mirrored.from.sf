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
# RCS $Id$
############


# Configuration Variable:
# Only one ... Where to find "rc.suspend"
# 
RC_SUSPEND=/etc/rc.d/rc.suspend


############
#
# Local Configuration Variables
# Set from $RC_SUSPEND later on by this script.
#
############


L_SUSP_DISK=''
L_PMDISK_SUPPORT=''
L_RET2X_PAUSE=2

# X typically runs on console #7.  If you run it on a different VT, specify
# its number here.
L_X_VT=7

L_DEST_CONSVT=8

L_LOG="/tmp/suspend2any.log"
L_LOCKFILE="/tmp/.suspenders.lock"

# List of modules to unload/reload after resume.
# List them in the order that they should be uninstalled.
L_MODULES=''


############
#
# Includes & Other Global Variables
#
############


CHANGEVT=chvt
OPENVT=openvt
FGCONSOLE=fgconsole
HWCLOCK=hwclock
XSCREENSAVER_CMD=xscreensaver-command
SWAPON=/sbin/swapon
SWAPOFF=/sbin/swapoff
MODPROBE=/sbin/modprobe

SILENT=/dev/null

RMMOD_SILENT='--quiet'
SUSP_DISK_ENABLED=''
SUSP_DISK_OLDPRIORITY=''
DISABLED_MODULES=''
CLOCKDEF=""
CLOCKFLAGS=''
nl='
'

RAN_GET_SWAPINFO=''
declare -a SWAPS
declare -a SWAPS_PRI
declare -a SWAPS_SIZE
declare -a SWAPS_USED
declare -a IDX_DISABLED_SWAPS


############
#
# Functions
#
############


# ~~~~~~~~~~~~~~~
# SWSusp-Specific
#


on_signal__() {
    sigval=$1
    rm -f $L_LOCKFILE
    exit ${sigval:-137} # 128+9
}


validate_proc_swap_fmt__() {
    retval=0
    if [ "$1" != "Filename" ]; 
        then retval=$((retval + 1)); fi
    shift
    if [ "$1" != "Type" ]; 
        then retval=$((retval + 2)); fi
    shift
    if [ "$1" != "Size" ]; 
        then retval=$((retval + 4)); fi
    shift
    if [ "$1" != "Used" ]; 
        then retval=$((retval + 8)); fi
    shift
    if [ "$1" != "Priority" ]; 
        then retval=$((retval + 16)); fi
    shift
    return $retval
}


parse_swap_info__() {
    is_first='y'
    while read -a line; do
        if [ -n "$is_first" ]; then
            is_first=''
            if [ ${#line[*]} -eq 5 -a "${line[1]}" = "partition" ]; then
                # Proceed with normal processing (after a warning message).
                echo "WARNING:  No header line in /proc/swaps" >> $L_LOG
            elif [ ${#line[*]} -eq 5 -a "${line[1]}" = "file" ]; then
                # Proceed with normal processing (after a warning message).
                mesg="WARNING:  No header line in /proc/swaps"
                mesg="${mesg}  Attempting to continue..."
                echo "${mesg}" >> $L_LOG
                continue
            elif `validate_proc_swap_fmt__ "${line[@]}"`; then
                continue
            else
                mesg="WARNING:  Unknown format of first line in"
                mesg="${mesg} /proc/swaps:$nl"
                mesg="${mesg}          \"${line[@]}\"$nl"
                mesg="${mesg}          Attempting to proceed normally"
                mesg="${mesg} (may still fail)." 
                echo "${mesg}" >> $L_LOG
            fi
        elif [ "${line[1]}" != "partition" ]; then
            continue
        fi # else
        # This function expects the swaps to be listed in order of increasing
        # priority.  We will store them in reverse order, skipping the target
        # swap.
        if [ "${line[0]}" = "${L_SUSP_DISK}" ]; then
            SUSP_DISK_ENABLED="y"
            SUSP_DISK_OLDPRIORITY="${line[4]}"
            continue
        fi # else
        SWAPS=("${line[0]}" "${SWAPS[@]}")
        SWAPS_PRI=("${line[4]}" "${SWAPS_PRI[@]}")
        SWAPS_SIZE=("${line[2]}" "${SWAPS_SIZE[@]}")
        SWAPS_USED=("${line[3]}" "${SWAPS_USED[@]}")
    done
}


get_swapinfo__() {
    # Cache results; why run this more than once?
    if [ -n "$RAN_GET_SWAPINFO" ]; then
        return 0
    fi

    # Wrapper function  The real work happens in 'parse_swap_info__' and is
    # stored in global variables.
    parse_swap_info__ </proc/swaps 
    RAN_GET_SWAPINFO='y'
}


enable_swap__() {
    status=0
    if [ "$1" = "-n" ]; then
        pretend="$1"
        shift
    fi 
    swappri="$1"
    shift
    swappart="$1"
    shift
    if [ -n "$pretend" ]; then
        echo ">>> $SWAPON -p $swappri \"${swappart}\""
    else
        $SWAPON -p $swappri "${swappart}"
        status=$?
    fi
    if [ $status -ne 0 ]; then
        print_warning__ "Unable to open target swap: ${swappart}."
        return 1
    fi
    return 0
}


disable_swap__() {
    status=0
    if [ "$1" = "-n" ]; then
        pretend="$1"
        shift
    fi 
    swappart="$1"
    if [ -n "$pretend" ]; then
        echo ">>> $SWAPOFF \"${swappart}\""
    else
        $SWAPOFF "${swappart}"
        status=$?
    fi
    if [ $status -ne 0 ]; then
        mesg="Unable to close target swap: ${swappart}. $nl"
        mesg="${mesg}  Suspend may not use expected partition."
        print_warning__ "$mesg"
        return 1
    fi
}


pmdisk_close_swaps__() {
    # N.B.:  See reenable_swaps__() about $pretend
    pretend="$1"

    # If we don't have enough free space to suspend, punt.
    eval `read_fn_output__ mem_total mem_free swap_total swap_free -- \
        get_meminfo__`
    get_swapinfo__

    # Start by closing the hibernation partition.  We want to ensure that it
    # is empty when suspend begins.
    if [ -n "${SUSP_DISK_ENABLED}" ]; then
        disable_swap__ $pretend "${L_SUSP_DISK}" \
            || { 
            SUSP_DISK_ENABLED=''
            print_warning__ \
                "Suspend will either use a different partition or fail."
            return 1 
        }
        # Update mem info now that the hibernation partition is out of the
        # way.
        eval `read_fn_output__ mem_total mem_free swap_total swap_free -- \
            get_meminfo__`
    fi

    # Close swaps in reverse-priority order (i.e. as stored by
    # get_swapinfo__), depending on availability of free swap space and free
    # memory.  Stop if/when swaps & memory are full.  Keep track which ones we
    # need to turn back on.
    i=0
    retstat=0
    while [ $i -lt ${#SWAPS[*]} -a -n "${SWAPS[$i]}" ]; do
        total_free=$((mem_free + swap_free))
        if [ $swap_free -eq 0 -o -z "${SWAPS_USED[$i]}" ]; then
            continue
        elif [ $total_free -lt ${SWAPS_USED[$i]} ]; then 
            continue
        fi # else
        disable_swap__ $pretend "${SWAPS[$i]}" || { 
            let ++retstat; 
            continue 
        }
        # else
        IDX_DISABLED_SWAPS[$i]=$i
        # Update memory again.
        eval `read_fn_output__ mem_total mem_free swap_total swap_free -- \
            get_meminfo__`
        let ++i
    done
    return $retstat
}


reenable_swaps__() {
    if [ "$1" = "-n" ]; then
        pretend="$1"
        shift
    fi 
    if [ -z "$1" -o $1 -ne 0 ]; then
        print_warning__ "Cannot reenable swaps."
    fi

    for i in "${IDX_DISABLED_SWAPS[@]}"; do
        # N.B.:  Leave $pretend unquoted, so that it's not passed as arg[1]
        # when empty.
        enable_swap__ $pretend ${SWAPS_PRI[$i]} "${SWAPS[$i]}"            
    done
}


swsusp_swap_setup__() {
    # N.B.:  See reenable_swaps__() about $pretend
    pretend="$1"

    # Do nothing if no suspend partition is specified.
    if [ -z "${L_SUSP_DISK}" ]; then
        return 4
    fi

    op_state=0
    if [ -n "${L_PMDISK_SUPPORT}" ]; then
        #PMDisk:  Turn off all swaps but the target swap, if there's enough
        # room. 
        action_shfn__ "Disabling all (nonfull) swaps" \
            pmdisk_close_swaps__ $pretend \
            || op_state=2

        # PMDisk will grab whichever swap partition has available
        # space and hibernate to it.  To increase the chances that
        # PMDisk grabs $L_SUSP_DISK, pmdisk_close_swaps__() disables it first,
        # before doing anything else.
        if [ $op_state -eq 0 ]; then
            how="Reactivating"
            if [ -z "${SUSP_DISK_ENABLED}" ]; then
                how="Enabling"
            fi
            action_shfn__ "$how suspend partition" \
                enable_swap__ $pretend -32767 ${L_SUSP_DISK}
            op_state=$?
        fi
    else
        # SWSusp: The default changes - don't close an already-enabled
        # hibernation partition on resume.
        get_swapinfo__
        op_state=1
        if [ -z "${SUSP_DISK_ENABLED}" ]; then
            action_shfn__ "Enabling suspend partition" \
                enable_swap__ $pretend -32767 ${L_SUSP_DISK}
                op_state=$?
        fi
    fi
    return $op_state
}


swsusp_restore_swaps__() {
    close_suspdisk_on_wake=$1
    shift
    # N.B.:  See reenable_swaps__() about $pretend
    pretend="$1"

    if [ -n "${L_PMDISK_SUPPORT}" ]; then
        swap_close_status=0
        case $close_suspdisk_on_wake in
            2)
                swap_close_status=1
                ;;
        esac

        action_shfn__ "Restoring swaps to original state" \
            reenable_swaps__ $pretend $swap_close_status
        if [ $? -eq 0 -a $close_suspdisk_on_wake -eq 0 ]; then 
            # Old restore_suspdisk__():
            action_shfn__ "Cleaning up suspend partition" \
                disable_swap__ $pretend ${L_SUSP_DISK} \
                || return 1
            if [ -n "${SUSP_DISK_ENABLED}" ]; then
                action_shfn__ "Restoring original suspend partition state" \
                    enable_swap__ $pretend \
                    ${SUSP_DISK_OLDPRIORITY} "${L_SUSP_DISK}"
                return $?
            fi
            return 0
        fi
        # return otherstatus
    else 
        # SWSusp Support:  Just close the hibernation partition if it wasn't
        # originally enabled.
        if [ ${close_suspdisk_on_wake} -eq 0 ]; then
            action_shfn__ "Closing suspend partition" \
                disable_swap__ $pretend ${L_SUSP_DISK}
            return $?
        fi # else
        return 0
    fi
}


swsusp_presuspend_finalcheck__() {
    eval `read_fn_output__ mem_total mem_free swap_total swap_free -- \
        get_meminfo__`
    errmesg=''
    if [ ${swap_total} -eq 0 ]; then
        errmesg="No swaps active.  Suspend WILL fail to do anything."
    elif [ ${swap_free} -lt ${mem_total} ]; then
        errmesg="Not enough free memory.  Suspend will likely fail$nl"
        errmesg="${errmesg}  to do anything."
    fi
    if [ -n "$errmesg" ]; then
        print_warning__ "$errmesg"
    fi
}


# ~~~~~~~~~~~~~~~~~~~~~~
# Core Utility Functions
#


read_config_set_local_vars__() {
    # Source $RC_SUSPEND
    . $RC_SUSPEND
    if [ -n "${SUSPEND_PARTITION}" ]; then
        L_SUSP_DISK="$SUSPEND_PARTITION"
    fi
    if [ -n "${PMDISK_SUPPORT}" ]; then
        L_PMDISK_SUPPORT="$PMDISK_SUPPORT"
    fi
    if [ -n "${ILL_BEHAVED_MODULES}" ]; then
        L_MODULES="$ILL_BEHAVED_MODULES"
    fi
    if [ -n "${SWITCH_TO_CONSOLE}" ]; then
        L_DEST_CONSVT="$SWITCH_TO_CONSOLE"
    fi
    if [ -n "${RETURN_TO_X_PAUSE}" ]; then
        L_RET2X_PAUSE="$RETURN_TO_X_PAUSE"
    fi
    if [ -n "${X_CONSOLE}" ]; then
        L_X_VT="$X_CONSOLE"
    fi
    if [ -n "${LOGFILE}" ]; then
        L_LOG="$LOGFILE"
    fi
    if [ -n "${LOCKFILE}" ]; then
        L_LOCKFILE="$LOCKFILE"
    fi
}


read_fn_output__() {
    # While you'd *think* you could pipe the output of a command to the 'read'
    # builtin to set local variables, this doesn't work.  The problem is that
    # pipes create subshells, which hoses the variables created by 'read'.
    # - 'export' and 'local' don't work.
    # - Calling 'read' from within a fn. to which you pipe the output doesn't
    #   work. 
    # This leaves you with using global variables, or the 'eval'-trickery we
    # perform here.
    output_vars=""
    while [ "$1" != "--" ]; do
        output_vars="${output_vars} $1"
        shift
    done
    shift
    if [ -z "$1" ]; then
        exit 127
    fi
    set -- `"$@"`
    for v in ${output_vars}; do
        echo "let ${v}='$1';"
        shift
    done
}


find_binary__() {
    targ=$1
    shift
    force=$1
    shift

    if `type $targ >>$SILENT 2>&1`; then
        echo $targ
        return 0
    fi
    targ_bn=${targ##*/}
    for p in /sbin /usr/sbin /usr/local/sbin /opt/sbin; do
        if [ -x $p/$targ_bn ]; then
            echo $p/$targ_bn
            return 0
        fi
    done
    if [ -n "$force" ]; then
        echo $targ_bg
    fi
    return 1
}


get_meminfo__() {
    set -- $(< /proc/meminfo)
    total=0
    free=0
    swapsz=0
    swapfree=0
    while [ -n "$1" ]; do
        field="$1"
        shift
        case "$field" in
            MemTotal*)
                total="$1"
                ;;
            MemFree*)
                free="$1"
                ;;
            SwapTotal*)
                swapsz="$1"
                ;;
            SwapFree*)
                swapfree="$1"
                ;;
            *)
                ;;
        esac
        shift
        shift # Throw away the "kB"
    done
    echo "${total}" "${free}" "${swapsz}" "${swapfree}"
}


disable_modules__() {
    if [ -z "$L_MODULES" ]; then
        DISABLED_MODULES=''
        return 0
    fi
    if [ "$1" = "-n" ]; then
        pretend="$@"
        shift
    fi 
    retstat=0
    for m in $L_MODULES; do
        action_shfn__ "Removing module: \"$m\"" \
            $MODPROBE $pretend $RMMOD_SILENT --remove $m
        if [ $? -eq 0 ]; then
            # Re-enable in reverse order.
            DISABLED_MODULES="$m ${DISABLED_MODULES}"
        else 
            let ++retstat
        fi
    done
    return $retstat
}


reenable_modules__() {
    if [ -z "$DISABLED_MODULES" ]; then
        return 0
    fi
    if [ "$1" = "-n" ]; then
        pretend="$@"
        shift
    fi 
    retstat=0
    for m in $DISABLED_MODULES; do
        action_shfn__ "Reinstalling module: \"$m\"" \
            $MODPROBE $pretend $m || let ++retstat
    done
    return $retstat
}


get_clockflags__() {
    # Snipped from RedHat's "rc.sysinit"
    ARC=0
    SRM=0
    UTC="no"

    if [ -f /etc/sysconfig/clock ]; then
        . /etc/sysconfig/clock
    fi
    CLOCKFLAGS="$CLOCKFLAGS --hctosys"

    case "$UTC" in
        yes|true)	CLOCKFLAGS="$CLOCKFLAGS --utc"
            CLOCKDEF="$CLOCKDEF (utc)" ;;
        no|false)	CLOCKFLAGS="$CLOCKFLAGS --localtime"
            CLOCKDEF="$CLOCKDEF (localtime)" ;;
    esac
    case "$ARC" in
        yes|true)	CLOCKFLAGS="$CLOCKFLAGS --arc"
            CLOCKDEF="$CLOCKDEF (arc)" ;;
    esac
    case "$SRM" in
        yes|true)	CLOCKFLAGS="$CLOCKFLAGS --srm"
            CLOCKDEF="$CLOCKDEF (srm)" ;;
    esac
}


reset_time__() {
    $HWCLOCK $CLOCKFLAGS
    action_shfn__ $"Setting clock $CLOCKDEF: `date`" date
}


maybe_changeconsole__() {
    if [ $L_DEST_CONSVT -le 0 -o $L_DEST_CONSVT -gt 63 ]; then
        mesg="Cannot switch consoles; \"SWITCH_TO_CONSOLE\" number"
        mesg="${mesg} out of range."
        print_warning__ "$mesg"
        return 1
    fi
    if [ -z "${FGCONSOLE}" ]; then
        print_warning__ $"Cannot switch consoles; 'fgconsole' tool not found."
        return 1
    fi
    if [ `$FGCONSOLE` -ne ${L_X_VT} ]; then
        set -C
        exec >/dev/console 2>&1
        set +C
        return 1
    fi
    if [ -z "${CHANGEVT}" ]; then
        print_warning__ $"Cannot switch consoles; 'chvt' tool not found."
        return 1
    fi
    # According to the manpages, "chvt" creates any non-existent vt's before
    # switching to them.
    $CHANGEVT ${L_DEST_CONSVT}
    status=$?
    if [ $status -eq 0 ]; then
        # Redirect STDOUT & STDERR of this script to the now-current console
        # VT.  Note that:
        # - The /dev/vcs${L_DEST_CONSVT} will not quite work, as these are
        #   mem-access devices.
        # - Using  /dev/tty${L_DEST_CONSVT} is equivalent to using
        #   /dev/console.  We could use either.
        # - The "2>&1" in the exec below ensures that STDERR is also
        #   redirected. 
        set -C
        exec >/dev/console 2>&1
        set +C
    fi
    return $status
}


return_to_X__() {
    was_running_xscreensaver=$1
    shift
    if [ $was_running_xscreensaver -ne 0 ]; then
        $XSCREENSAVER_CMD -unthrottle >>$SILENT 2>&1
    fi
    if [ -z "${CHANGEVT}" -o -z "${L_X_VT}" ]; then
        return 0
    fi
    if [ -n "$L_RET2X_PAUSE" ]; then
        sleep $L_RET2X_PAUSE
    fi
    $CHANGEVT ${L_X_VT}
    if [ $was_running_xscreensaver -ne 0 ]; then
        $XSCREENSAVER_CMD -deactivate >>$SILENT 2>&1
    fi
}


check_for_xscreensaver__() {
    if [ -n "$1" -a $1 -ne 0 ]; then
        return 1
    fi
    XSCREENSAVER_CMD=`find_binary__ $XSCREENSAVER_CMD`
    if [ -z "$XSCREENSAVER_CMD" ]; then
        return 1
    fi
    $XSCREENSAVER_CMD -throttle >>$SILENT 2>&1
    return $?
}


perform_suspend__() {
    susp_type=$1
    case "$1" in
        mem|disk)
            : # NOOP
            ;;
        *)
            errmsg="ERROR:  Incorrect suspend-type flag$nl"
            errmsg="${errmsg}  Suspend will fail to do anything."
            print_warning__ "$errmesg"
            ;;
    esac

    if [ "$susp_type" = "disk" ]; then
        swsusp_presuspend_finalcheck__
    fi

    action_shfn__ "Initiating suspend" echo

    # This performs the suspend.
    echo -n $susp_type > /sys/power/state
    # Alt Method:
    #echo 3 >>/proc/acpi/sleep  # suspend to mem
    #echo 4 >>/proc/acpi/sleep  # suspend to disk
}


suspend_system__() {
    susp_type=$1

    # Retrieve clock setup info.
    get_clockflags__

    # Disable any power-sensitive modules
    disable_modules__

    # PMDisk Support:  Close all swap devices except for the sleep partition.
    # Note that SWSusp requires a partition name, rather than picking one at
    # random.
    if [ "$susp_type" = "disk" ]; then
        swsusp_swap_setup__
        close_suspdisk_on_wake=$?
    fi

    # ========== SUSPEND NOW
    perform_suspend__ $susp_type
    # ========== RESUME NOW
    echo "-.-.-.-.-"
    echo "Performing post-resume tasks:"

    # Fix the system clock.
    reset_time__

    # Re-enable any swap partitions shut down during suspend.
    if [ "$susp_type" = "disk" ]; then
        # Run this in the background, as it can take a while.  Note that we
        # pipe the output to `echo' and run the whole thing in a subshell to
        # delay output of the status message(s).
        (swsusp_restore_swaps__ $close_suspdisk_on_wake 2>&1 | echo) &
    fi

    # Reinstall any power-sensitive modules that were disabled.
    reenable_modules__
}


print_warning__() {
    echo -n "$*"; echo_warning; echo
    echo "WARNING:  $*" >> $L_LOG
}


# A version of the RHAT "action" shell initscript function that's safe for
# calling a shell function
action_shfn__() {
    mesg="$1"; shift
    echo -n "$mesg"
    cmd="$1"; shift
    if [ -z "$cmd" ]; then 
        return 1
    fi
    $cmd "$@" >>$SILENT 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then
        echo_success
        echo "- $mesg" >> $L_LOG
    else
        echo_failure
        echo "FAILED: $mesg" >> $L_LOG
    fi
    echo
    return $rc
}


do_unit_tests_switchvt() {
    if [ "${UNIT_TEST}" != "switchvt" ]; then
        return 0
    fi
    # Change consoles, if in X
    maybe_changeconsole__
    was_in_x=$?
    check_for_xscreensaver__ $was_in_x
    is_running_xscreensaver=$?
    return $was_in_x
}
do_unit_tests_basic() {
    if [ "${UNIT_TEST}" != "noclock" ]; then
        get_clockflags__
        echo "clock: ${CLOCKFLAGS}"
        reset_time__
    fi

    # Disable any power-sensitive modules
    disable_modules__ -n

    echo ""

    get_meminfo__
    read_fn_output__ mem_total mem_free swap_total swap_free -- \
        get_meminfo__
    eval `read_fn_output__ mem_total mem_free swap_total swap_free -- \
        get_meminfo__`
    echo "Meminfo: total/free        Swapinfo: total/free"
    echo "${mem_total}/${mem_free}        ${swap_total}/${swap_free}"

    echo ""

    # 'pmdisk_close_swaps__' calls 'get_swapinfo__'; keep next line for future
    # use 
    echo "Testing \"pmdisk_close_swaps__():\""
    #get_swapinfo__
    pmdisk_close_swaps__ -n
    echo "Done."

    echo "Testing \"swsusp_swap_setup__():\""
    swsusp_swap_setup__ -n
    swap_setup_state=$?
    echo "Done."

    echo "Swaps:          ${SWAPS[@]}"
    echo "SwapPriorities: ${SWAPS_PRI[@]}"
    echo "SwapsUsed:      ${SWAPS_USED[@]}"
    echo "SwapsSize:      ${SWAPS_SIZE[@]}"
    echo "CloseSwap Indices:  ${IDX_DISABLED_SWAPS[@]}"
    echo ""
    echo "_____________________"
    echo "Testing warning messages and actions."
    echo ""
    print_warning__ "Test of a warning."
    action_shfn__ "Test of action" echo "Foo \$bar 'bang bang'"
    action_shfn__ "Test of shell-function" get_meminfo__

    echo ""

    echo "Testing \"reenable_swaps__():\""
    reenable_swaps__ 0 -n
    echo "Done."

    echo "Testing \"swsusp_restore_swaps__():\""
    echo "Swap setup status was: $swap_setup_state"
    swsusp_restore_swaps__ $swap_setup_state  -n
    echo "Done."

    echo ""

    # Reinstall any power-sensitive modules that were disabled.
    reenable_modules__ -n
}
do_unit_tests_switchback() {
    was_in_x=$1
    if [ "${UNIT_TEST}" != "switchvt" ]; then
        return 0
    fi
    # Change back, if we were in X before the suspend
    if [ $was_in_x -eq 0 ]; then
        return_to_X__ 0
    fi
}
do_unit_tests() {
    SILENT=$L_LOG
    do_unit_tests_switchvt
    was_in_x=$?
    do_unit_tests_basic
    do_unit_tests_switchback $was_in_x
    exit 0
}


############
#
# Main
#
############


trap on_signal__ 1 2 3 4 5 6 7 8 10 11 12 15 19


how=disk
case "$1" in
    mem|disk)
        how=$1
        ;;
    *)
        echo "Usage: $0 (mem|disk)"
        exit 1
        ;;
esac


# Pull in the configfile.
read_config_set_local_vars__


# Lock - Prevent a suspend-resume-suspend-resume loop.
if [ -f $L_LOCKFILE ]; then
    echo "$0 already running."
    chmod -f a+w $L_LOCKFILE
    echo "(Run \"kill \$(< $L_LOCKFILE)\" to terminate. "
    echo " Remove lock file \"$L_LOCKFILE\" if this is incorrect.)"
    exit 0
fi

# Load some system functions, or just spoof them.
if [ -f /etc/init.d/functions -a -z "$UNIT_TEST_NONRHAT" ]; then
    # Note:  We *must* set the console type here and now.  The setup code in
    # /etc/init.d/functions will guess incorrectly that the VT is a serial
    # connection instead of a console.
    export CONSOLETYPE=linux
    . /etc/init.d/functions
else
    unset -f print_warning__
    print_warning__() {
        echo "$*	[WARNING]"
        echo "WARNING:  $*" >> $L_LOG
    }
    echo_success() { 
        echo -n "	[OK]"
    }
    echo_failure() { 
        echo -n "	[FAILED]"
    }
fi

CHANGEVT=`find_binary__ $CHANGEVT`
OPENVT=`find_binary__ $OPENVT`
FGCONSOLE=`find_binary__ $FGCONSOLE`
HWCLOCK=`find_binary__ $HWCLOCK --force`
SWAPON=`find_binary__ $SWAPON --force`
SWAPOFF=`find_binary__ $SWAPOFF --force`
MODPROBE=`find_binary__ $MODPROBE --force`

rm -f $L_LOG

if [ -n "$UNIT_TEST" ]; then
    do_unit_tests
fi


# Change consoles, if in X
maybe_changeconsole__
was_in_x=$?
echo "========="
check_for_xscreensaver__ $was_in_x
is_running_xscreensaver=$?

# Pre-suspention tasks, including locking
pre_suspend $was_in_x
echo "$$" > $L_LOCKFILE

# N.B.: No need to specify the "pmdisk" kernel option if you suspended to the 
# default pmdisk partition.
suspend_system__ $how

# Unlock after a pause.  Run the whole deal in a background subshell.
(sleep 10; rm -f $L_LOCKFILE) >>$L_LOG 2>&1 &

# Everything below gets executed after resume.
resume_tasks $was_in_x

# Change back, if we were in X before the suspend
if [ $was_in_x -eq 0 ]; then
    return_to_X__ $is_running_xscreensaver
fi


#################
#
#  End
