#!/bin/bash
#
# Copyright (C) 2014 by John P. Weiss
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


############
#
# Includes & Other Global Variables
#
############


myPath=`dirname $0`

test -f /usr/share/acpi-support/key-constants || exit 0
. /usr/share/acpi-support/key-constants


if [ -f $myPath/debug.sh ]; then
    SOURCED=y
    export SOURCED
    . $myPath/debug.sh
fi


############
#
# Functions
#
############


translateKeycode_old_ibm()
{
    local acpiKey="$1"
    shift

    case "${acpiKey##0000}" in
        1001)
            echo "$KEY_F13 (F13)"
            ;;
        1002)
            echo "$KEY_F14 (F14)"
            ;;
        1003)
            echo "$KEY_LOCK (LOCK)"
            ;;
        1004)
            echo "$KEY_SLEEP (SLEEP)"
            ;;
        1005)
            echo "$KEY_CONNECT (CONNECT)"
            ;;
        1006)
            echo "$KEY_F15 (F15)"
            ;;
        1007)
            echo "$KEY_VIDEOMODECYCLE (VIDEOMODECYCLE)"
            ;;
        1008)
            echo "$KEY_F16 (F16)"
            ;;
        1009)
            echo "$KEY_F24 (F24)"
            ;;
        100[aA])
            echo "$KEY_F17 (F17)"
            ;;
        100[bB])
            echo "$KEY_F18 (F18)"
            ;;
        100[cC])
            echo "$KEY_SUSPEND (SUSPEND)"
            ;;
        1014)
            echo "$KEY_PROG1 (PROG1)"
            ;;
        1018)
            echo "$KEY_SETUP (SETUP)"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}


translateKeycode()
{
    local preparsedKeyNm="$1"
    shift

    case "$preparsedKeyNm" in
        Fn+F1)
            echo "$KEY_F13 (F13)"
            ;;
        Fn+F2)
            echo "$KEY_F14 (F14)"
            ;;
        Fn+F3|screenlock)
            echo "$KEY_LOCK (LOCK)"
            ;;
        Fn+F4|sleep)
            echo "$KEY_SLEEP (SLEEP)"
            ;;
        Fn+F5|toggleWifi)
            echo "$KEY_CONNECT (CONNECT)"
            ;;
        Fn+F6)
            echo "$KEY_F15 (F15)"
            ;;
        Fn+F7|switchVidMode)
            echo "$KEY_VIDEOMODECYCLE (VIDEOMODECYCLE)"
            ;;
        Fn+F8)
            echo "$KEY_F16 (F16)"
            ;;
        Fn+F9|dock)
            echo "$KEY_F24 (F24)"
            ;;
        Fn+F10)
            echo "$KEY_F17 (F17)"
            ;;
        Fn+F11)
            echo "$KEY_F18 (F18)"
            ;;
        Fn+F12|hibernate)
            echo "$KEY_SUSPEND (SUSPEND)"
            ;;
        Fn+prog1)
            echo "$KEY_PROG1 (PROG1)"
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}


############
#
# Main
#
############


set -- $*


eventType="$1"
keycode="$4"
key_name="$5"

stat=0
if [ -z "$key_name" ]; then
    xlatedKey=`translateKeycode $key_name`
    stat=$?
fi

# If the new-style fails, try falling back on the old "ibm/hotkey" type.
if [ $stat -eq 0 ]; then
    xlatedKey=`translateKeycode_old_ibm $keycode`
    stat=$?
    key_name="$*"
fi

if [ $stat -eq 0 ]; then
    echo "fakekey:  Translated \"$key_name\" to \"$xlatedKey\"" >>$LOGFILE
    acpi_fakekey $xlatedKey
else
    echo "fakekey:  Cannot forward:  $key_name" >>$LOGFILE
fi
echo "fakekey:      orig_event=='$@'" >>$LOGFILE


#################
#
#  End
