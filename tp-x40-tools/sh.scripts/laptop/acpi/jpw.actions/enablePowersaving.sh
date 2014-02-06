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
# $Id$
############


############
#
# Configuration Variables
#
############


KEEP_MODULES="bluetooth bnep hidp input_polldev rfcomm"


############
#
# Includes & Other Global Variables
#
############


LOGFILE=/tmp/logs/enablePowersaving.log

POWERSAVE_FNS=""
if [ -e /etc/rc.local ]; then
    POWERSAVE_FNS="/etc/rc.local"
elif [ -e /etc/LocalSys/init.d/rc.local ]; then
    POWERSAVE_FNS="/etc/LocalSys/init.d/rc.local"
fi


############
#
# Functions
#
############


get_powersave_modules()
{
    if [ -e /etc/LocalSys/init.d/rc.powersave-modules ]; then
        grep -v -e '^$' -e '^#.*' \
            /etc/LocalSys/init.d/rc.powersave-modules |\
            grep -v -e "${KEEP_MODULES// /\\|}"
    fi
}


save_power()
{
    . /etc/LocalSys/init.d/functions-laptop
    if [ -n "$POWERSAVE_FNS" ]; then
        . $POWERSAVE_FNS

        POWERSAVE="y"
        MUTE="y"
        export POWERSAVE MUTE

        powersaveCommon
        otherPowersaveStuff
    fi

    if [ -x /etc/acpi/jpw.actions/swapOnOff.sh ]; then
        /etc/acpi/jpw.actions/swapOnOff.sh off
    fi

    # Remove defunct and/or unused modules.
    modlist=`get_powersave_modules`
    if [ -n "$modlist" ]; then
        rmmodsAll $modlist
    fi
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
    # Was run as a script.  Perform any execution-specific tasks here (rather
    # than pulling an unneeded "main" function into the environment.

    echo "" >>$LOGFILE
    echo "#################### `date` ####################" \
        >>$LOGFILE
    echo "" >>$LOGFILE
    chmod a+r $LOGFILE

    save_power "$@" >>$LOGFILE 2>&1
fi


#################
#
#  End
