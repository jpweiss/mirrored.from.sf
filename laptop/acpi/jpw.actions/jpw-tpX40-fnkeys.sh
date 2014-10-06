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


############
#
# Functions
#
############


parse_ibm_slash_hotkey()
{
    local full_keycode="$1"
    shift

    local ibmHotkey_code="${full_keycode%*0000}"
    case "$ibmHotkey_code" in
        1001)
            echo "Fn+F1"
            ;;
        1002)
            echo "Fn+F2"
            ;;
        1003)
            echo "Fn+F3"
            ;;
        1004)
            echo "Fn+F4"
            ;;
        1005)
            echo "Fn+F5"
            ;;
        1006)
            echo "Fn+F6"
            ;;
        1007)
            echo "Fn+F7"
            ;;
        1008)
            echo "Fn+F8"
            ;;
        1009)
            echo "Fn+F9"
            ;;
        100[aA])
            echo "Fn+F10"
            ;;
        100[bB])
            echo "Fn+F11"
            ;;
        100[cC])
            echo "Fn+F12"
            ;;
        1014)
            echo "Fn+prog1"
            ;;
        *)
            echo "$full_keycode"
            return 1
            ;;
    esac
    return 0
}


parse_button_eventcode()
{
    local keyName="$1"
    shift

    case "$keyName" in
        FNF1)
            echo "Fn+F1"
            ;;
        BAT)
            # On the ThinkPad X40, this is "Fn+F2".
            echo "Fn+F2"
            ;;
        SCRNLCK)
            echo "screenlock"
            ;;
        SBTN)
            echo "sleep"
            ;;
        WLAN)
            echo "toggleWifi"
            ;;
        FNF6)
            echo "Fn+F6"
            ;;
        VMOD)
            echo "switchVidMode"
            ;;
        ZOOM)
            # On the ThinkPad X40, this is "Fn+F8".
            echo "Fn+F8"
            ;;
        FNF9|DOCK)
            echo "dock"
            ;;
        FF10)
            echo "Fn+F10"
            ;;
        FF11)
            echo "Fn+F11"
            ;;
        SUSP)
            echo "hibernate"
            ;;
        PROG1)
            echo "Fn+prog1"
            ;;
        *)
            echo "$keyName"
            return 1
            ;;
    esac
    return 0
}


parse_eventcodes()
{
    local full_eventcode="$@"

    local event_type="$1"
    shift
    local name="$1"
    shift
    local keycode1="$1"
    shift
    local keycode2="$1"
    shift

    local parseStat=1
    case "${event_type// \//\/}" in
        video/switchmode|button/*)
            parse_button_eventcode $name
            parseStat=$?
            ;;

        ibm/hotkey*)
            parse_ibm_slash_hotkey $keycode2
            parseStat=$?
            ;;

        *)
            echo "$full_eventcode"
            ;;

    esac
    return $parseStat
}


exec_acpi_action()
{
    local key_name="$1"
    shift
    local action_args="$@"


    # WARNING:  There is no guarantee that the following actions are
    #           up-to-date with the event rules.  The latter are the
    #           definitive "Fn+"-key mappings, not this 'case' statement.
    case "$key_name" in
        Fn+F1)
            exec $myPath/switchToVT1.sh $action_args
            ;;

        Fn+F2)
            exec $myPath/enablePowersaving.sh
            ;;

        Fn+F3|screenlock)
            exec $myPath/screenblanker.sh
            ;;

        Fn+F4|sleep)
            exec $myPath/sleep.sh
            ;;

        Fn+F5|toggleWifi)
            # ThinkPad Fn+F5 == toggle WiFi.
            exec $myPath/ibm-wireless.sh
            ;;

        Fn+F6)
            exec $myPath/bluetooth-ctrl.sh
            ;;

        Fn+F10)
            exec $myPath/swapOnOff.sh $action_args
            ;;

        Fn+F12|hibernate)
            exec $myPath/hibernate.sh
            ;;

        # Unused key combos:  Just return
        #Fn+F7|switchVidMode)
        #Fn+F8)
        #Fn+F9|dock)        # ThinkPad Fn+F9 == [un]dock laptop.
        #Fn+F11)
        #PROG1)
    esac
}


############
#
# Main
#
############


orig_eventcode="$@"
xlatedKey=`$(parse_eventcodes $orig_eventcode`

# [jpw; 201410]  Currently unused; anything not handled by an event rule
#                was intentionally left unbound.
#exec_acpi_action "$xlatedKey" $orig_eventcode

# Fallback:  Any unhandled keys get passed to the "fakekey.sh" handler.
exec $myPath/fakekey.sh $orig_eventcode $xlatedKey


#################
#
#  End
