# !/bin/bash
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
# Includes & Other Global Variables
#
############


if type -t getXuser; then
    :
else
    # 'power-funcs' defines the 'getXuser()' and 'getXconsole' functions,
    # amongst others.
    . /usr/share/acpi-support/power-funcs
fi


############
#
# Functions
#
############


wrapper__runX()
{
    local xdisplay="$1"
    shift
    local xuser="$1"
    shift
    local xauth="$1"
    shift

    if [ -z "$DISPLAY" ]; then
        DISPLAY="$xdisplay"
    fi
    export DISPLAY

    if [ -z "$XAUTHORITY" ]; then
        XAUTHORITY="$xauth"
    fi
    export XAUTHORITY

    if [ -z "$xuser" ]; then
        return 1
    fi

    for cmd in "$@"; do
        su $xuser -c "$cmd"
    done
}


runXCmd()
{
    getXconsole
    if [ -z "$user" ]; then
        return 1
    fi

    if [ "$1" = "-f" ]; then
        shift
        cmd_fn="$1"
        shift
        $cmd_fn  "$DISPLAY" "$user" "$XAUTHORITY" "$@"
    else
        wrapper__runX "$DISPLAY" "$user" "$XAUTHORITY" "$@"
    fi
}


runXCmd_allXServers()
{
    for x in /tmp/.X11-unix/*; do
        displaynum=`echo $x | sed s#/tmp/.X11-unix/X##`
        getXuser
        if [ -z "$user" ]; then
            continue
        fi

        if [ "$1" = "-f" ]; then
            shift
            cmd_fn="$1"
            shift
            $cmd_fn  ":$displaynum" "$user" "$XAUTHORITY" "$@"
        else
            wrapper__runX ":$displaynum" "$user" "$XAUTHORITY" "$@"
        fi
    done
}


#################
#
#  End
