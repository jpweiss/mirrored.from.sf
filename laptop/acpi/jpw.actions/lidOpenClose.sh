#!/bin/bash
#

exit 0

test -f /usr/share/acpi-support/state-funcs || exit 0

. /usr/share/acpi-support/power-funcs
. /usr/share/acpi-support/policy-funcs
. /etc/default/acpi-support


LASTCONSOLE_FILE=/var/local/lidClose-lastConsole
VBESTATE_FILE=/var/local/lidClose-i915.state

[ -x /etc/acpi/local/lid.sh.pre ] && /etc/acpi/local/lid.sh.pre


grep -q closed /proc/acpi/button/lid/*/state
if [ $? = 0 ]
then
    fgconsole >$LASTCONSOLE_FILE
    chvt 1
    vbetool vbestate save >$VBESTATE_FILE
    if [ `CheckPolicy` = 0 ]; then exit; fi

    for x in /tmp/.X11-unix/*; do
	displaynum=`echo $x | sed s#/tmp/.X11-unix/X##`
	getXuser;
	if [ x"$XAUTHORITY" != x"" ]; then
	    export DISPLAY=":$displaynum"	    
	    # [jpw] Just to be triply-sure, we're gonna skip this file, which
	    #       locks the screen any chance it gets.  Instead, we'll
	    #       just turn off the screen.
	    #. /usr/share/acpi-support/screenblank
            su $user -c "xset dpms force off"
	fi
    done
else
    lastConsole=7
    if [ -r $LASTCONSOLE_FILE ]; then
        lastConsole=`cat $LASTCONSOLE_FILE`
    fi
    chvt $lastConsole
    if [ -r $VBESTATE_FILE ]; then
        vbetool vbestate restore <$VBESTATE_FILE
    fi
    if [ `CheckPolicy` = 0 ]; then exit; fi

    for x in /tmp/.X11-unix/*; do
	displaynum=`echo $x | sed s#/tmp/.X11-unix/X##`
	getXuser;
	if [ x"$XAUTHORITY" != x"" ]; then
	    export DISPLAY=":$displaynum"
	    grep -q off-line /proc/acpi/ac_adapter/*/state
	    if [ $? = 1 ]
		then
		if pidof xscreensaver > /dev/null; then 
		    su $user -c "xscreensaver-command -unthrottle"
		fi
	    fi
	    if [ x$RADEON_LIGHT = xtrue ]; then
		[ -x /usr/sbin/radeontool ] && radeontool light on
	    fi
	    if [ `pidof xscreensaver` ]; then
		su $user -c "xscreensaver-command -deactivate"
	    fi
	    su $user -c "xset dpms force on"
	fi
    done
fi
[ -x /etc/acpi/local/lid.sh.post ] && /etc/acpi/local/lid.sh.post
