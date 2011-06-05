#!/bin/bash
#


test -f /usr/share/acpi-support/state-funcs || exit 0

. /usr/share/acpi-support/power-funcs
. /usr/share/acpi-support/policy-funcs
. /etc/default/acpi-support


LASTCONSOLE_FILE=/var/local/lidClose-lastConsole


[ -x /etc/acpi/local/lid.sh.pre ] && /etc/acpi/local/lid.sh.pre

grep -q closed /proc/acpi/button/lid/*/state
if [ $? = 0 ]; then

    fgconsole >$LASTCONSOLE_FILE
    chvt 1

    for x in /tmp/.X11-unix/*; do
        displaynum=`echo $x | sed s#/tmp/.X11-unix/X##`
        getXuser;
        if [ x"$XAUTHORITY" != x"" ]; then
            export DISPLAY=":$displaynum"
            su $user -c "xset dpms force off"
        fi
    done

else

    lastConsole=7
    if [ -r $LASTCONSOLE_FILE ]; then
        lastConsole=`cat $LASTCONSOLE_FILE`
    fi
    chvt $lastConsole
    if [ `CheckPolicy` = 0 ]; then exit; fi

    for x in /tmp/.X11-unix/*; do
        displaynum=`echo $x | sed s#/tmp/.X11-unix/X##`
        getXuser;
        if [ x"$XAUTHORITY" != x"" ]; then
            export DISPLAY=":$displaynum"
            pidof xscreensaver >/dev/null && xscreensaver_running=y
            grep -q off-line /proc/acpi/ac_adapter/*/state
            if [ $? = 1 ]; then
                if [ -n "$xscreensaver_running" ]; then 
                    su $user -c "xscreensaver-command -unthrottle"
                fi
            fi
            if [ -n "$xscreensaver_running" ]; then 
                su $user -c "xscreensaver-command -deactivate"
            fi
            su $user -c "xset dpms force on"
        fi
    done

fi

[ -x /etc/acpi/local/lid.sh.post ] && /etc/acpi/local/lid.sh.post
