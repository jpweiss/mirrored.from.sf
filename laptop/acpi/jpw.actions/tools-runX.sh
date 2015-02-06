# !/bin/bash
#
# Copyright (C) 2013-2015 by John P. Weiss
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


DBGLOG=/tmp/logs/acpi-debug-event.log


############
#
# Functions
#
############


getXinfo_raw()
{
    local targDisplay="$1";
    shift

    type -t ck-list-sessions >/dev/null || return 1

    ck-list-sessions | \
        perl -n -e \
        'BEGIN {
             our %sessionInfo=();
             our $curSesId="";
             our $targDisplay="'$targDisplay'";
         }' -e \
        'sub dequote($) {
             my $s = shift();
             $s =~ s/^[\x27"]//;
             $s =~ s/[\x27"]$//;
            return($s);
         }' -e \
        'if (m/^(Session.+)$/) {
             $curSesId=$1;
         }
         elsif ($curSesId ne "") {
             m/(\S+) = (\S+)/;
             if ($1 ne "") {
                 $sessionInfo{$curSesId}{$1} = dequote($2);
             }
         }'  -e \
        'END {
             my $curX11Disp="";
             my $x_display="";
             my $consoleDev="";
             my $uid="";
             foreach my $k (sort(keys(%sessionInfo))) {
                 $curX11Disp = $sessionInfo{$k}{"x11-display"};
                 next unless ( ($sessionInfo{$k}{"active"} eq "TRUE")
                               ||
                               ( ($targDisplay ne "")
                                 &&
                                 ($targDisplay eq $curX11Disp)
                                 )
                              );

                 $uid = $sessionInfo{$k}{"unix-user"};
                 $x_display = $curX11Disp;
                 $consoleDev = $sessionInfo{$k}{"x11-display-device"};
                 if ($consoleDev eq "") {
                     $consoleDev = $sessionInfo{$k}{"display-device"};
                 }
             }

             print "\"$uid\" \"$x_display\" \"$consoleDev\"\n";
         }'
}


getUserInfo()
{
    # Note the jiggery-pokery taking place to trim the quotes off the arg.
    local uid="${1%\"}"
    shift

    # Format of an entry in /etc/passwd:
    #     <usernm>:<passwd>:<uid>:<gid>:<realname>:<home>:<shell>
    perl -a -F: -n -e \
        'BEGIN {
             our $userId="'${uid#\"}'";
         }' -e \
        'if ($F[2] eq $userId) {
             print "\"$F[0]\" \"$F[5]\"\n";
         }' \
             /etc/passwd
}


getXinfo()
{
    # Everything comes from 'getXinfo_raw' and 'getUserInfo' quoted, because
    # it's being written out by an embedded perl script.
    #
    # We don't need that quoting from within the shell, so remove it.

    set -- `getXinfo_raw`
    local uid="${1%\"}"
    shift
    local xdisplay="${1%\"}"
    shift
    local consoleDev="${1%\"}"
    shift

    local consoleNum="${consoleDev##*/}"
    consoleNum="${consoleNum#tty}"
    consoleNum="${consoleNum#vcs}"
    consoleNum="${consoleNum#vcsa}"

    set -- `getUserInfo $uid`

    local userName="${1%\"}"
    shift
    local xauthfile="${1%\"}/.Xauthority"
    shift

    echo -n "${userName#\"} ${uid#\"} ${xdisplay#\"} "
    echo "${xauthfile#\"} ${consoleNum#\"} ${consoleDev#\"}"
}


extractUsername_fromXInfo()
{
    local xinfo="$1"
    if [ $# -lt 2 ]; then
        set -- $xinfo
    fi

    echo "$1"
}


extractXAuth_fromXInfo()
{
    local xinfo="$1"
    if [ $# -lt 2 ]; then
        set -- $xinfo
    fi

    echo "$4"
}


wrapper__runX()
{
    local xdisplay="$1"
    shift
    local xuser="$1"
    shift
    local xauth="$1"
    shift

    if [ -z "$xuser" ]; then
        return 1
    fi

    local oldDISPLAY="$DISPLAY"
    export DISPLAY="$xdisplay"
    local oldXAUTHORITY="$XAUTHORITY"
    export XAUTHORITY="$xauth"

    for cmd in "$@"; do
        # DBG:  Comment out when not in use.
        #echo "wrapper__runX:  su $xuser -c \"$cmd\"" >>$DBGLOG
        su $xuser -c "$cmd"
    done

    export DISPLAY="$oldDISPLAY"
    export XAUTHORITY="$oldXAUTHORITY"
}


runXCmd()
{
    local user xdisplay xauth
    if [ "$1" = "--has-xinfo" ]; then
        shift

        xdisplay="$1"
        shift
        user="$1"
        shift
        xauth="$1"
        shift
    else
        set -- `getXinfo`
        user="$1"
        xdisplay="$3"
        xauth="$4"
    fi

    if [ -z "$user" ]; then
        return 1
    fi

    if [ "$1" = "-f" ]; then
        shift
        cmd_fn="$1"
        shift
        # DBG:  Comment out when not in use.
        #echo "runXCmd:  \"$cmd_fn $@\"" >>$DBGLOG
        $cmd_fn  "$xdisplay" "$user" "$xauth" "$@"
    else
        wrapper__runX "$xdisplay" "$user" "$xauth" "$@"
    fi
}


runXCmd_allXServers()
{
    local user xinfo xauth
    local x cmd_fn

    for x in /tmp/.X11-unix/*; do
        displaynum=`echo $x | sed s#/tmp/.X11-unix/X##`

        # We can't use 'set' here, since we need to preserve the current
        # arglist.  Note that "$xinfo" will have its elements already quoted,
        # so there's no need to put quotes around _it_.
        xinfo=`getXinfo ":$displaynum"`
        user=`extractUsername_fromXInfo $xinfo`
        xauth=`extractXAuth_fromXInfo $xinfo`

        if [ -z "$user" ]; then
            continue
        fi

        # if [ "$1" = "-f" ]; then
        #     shift
        #     cmd_fn="$1"
        #     shift
        #     # DBG:  Comment out when not in use.
        #     #echo "runXCmd_allXServers:  \"$cmd_fn $@\"" >>$DBGLOG
        #     $cmd_fn ":$displaynum" "$user" "$xauth" "$@"
        # else
        #     wrapper__runX ":$displaynum" "$user" "$xauth" "$@"
        # fi
        runXCmd --has-xinfo ":$displaynum" "$user" "$xauth" "$@"
    done
}


#################
#
#  End
