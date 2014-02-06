#!/bin/bash


translateKeycode()
{
    acpiKey="$1"
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



test -f /usr/share/acpi-support/key-constants || exit 0

. /usr/share/acpi-support/key-constants

if [ -f /etc/acpi/jpw.actions/debug.sh ]; then
    SOURCED=y
    export SOURCED
    . /etc/acpi/jpw.actions/debug.sh
fi


set -- $*

eventType="$1"
keycode="$4"

xlatedKey=`translateKeycode $keycode`
if [ $? -eq 0 ]; then
    echo "fakekey:  Translated \"$keycode\" to \"$xlatedKey\"" >>$LOGFILE
    acpi_fakekey $xlatedKey
else
    echo "fakekey:  Cannot forward:  $keycode" >>$LOGFILE
fi
echo "fakekey:      orig_event=='$@'" >>$LOGFILE
