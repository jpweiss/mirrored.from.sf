#!/bin/bash
#
# Copyright (C) 2002 by John P. Weiss
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


############
#
# Includes & Other Global Variables
#
############


if [ -z "$CONSBELL_PITCH" ]; then
    CONSBELL_PITCH="750"
fi
if [ -z "$CONSBELL_LENGTH" ]; then
    CONSBELL_LENGTH="100"
fi
export CONSBELL_PITCH CONSBELL_LENGTH


############
#
# Functions
#
############


# 1m is inaudible
# 15k just clicks; 10k is already a squeak
setBell_pitch() {
    v=$1
    case $v in
        *k)
            v="${v%k}000"
            ;;
        *K)
            v="${v%K}000"
            ;;
        *m)
            v="${v%m}000000"
            ;;
        *M)
            v="${v%M}000000"
            ;;
    esac
    echo -e "\033[10;$v]"
    CONSBELL_PITCH=$v
}


# 1c is nearly too short to use.  Doesn't always beep
# 1s is waaaaaay too long
setBell_length() {
    v=$1
    case $v in
        *d)
            v="${v%d}00"
            ;;
        *c)
            v="${v%c}0"
            ;;
        *m)
            v="${v%m}"
            ;;
        *s)
            v="${v%s}000"
            ;;
        *S)
            v="${v%S}000"
            ;;
        *\.*)
            v=$((1000*$v))
            ;;
    esac
    echo -e "\033[11;$v]"
    CONSBELL_LENGTH=$v
}


script_main() {
    CONSBELL_SH=/tmp/.CONSBELL_`fgconsole`_.sh
    if [ -f $CONSBELL_SH ]; then
        . $CONSBELL_SH
    fi
    case $1 in
        mute)
            setBell_length 0
            ;;
        unmute)
            setBell_length 1d
            ;;
        reset)
            setBell_length 1d
            setBell_pitch 750
            ;;
        toggle_mute)
            if [ ${CONSBELL_LENGTH} -eq 0 ]; then
                setBell_length 1d
            else
                setBell_length 0
            fi
            ;;
        set*ength)
            setBell_length $2
            ;;
        set*itch)
            setBell_pitch $2
            ;;
        incr*)
            step=$2
            if [ -z "$step" ]; then
                step=25
            fi
            setBell_pitch $((CONSBELL_PITCH + $step))
            echo -e "\007"
            ;;
        decr*)
            step=$2
            if [ -z "$step" ]; then
                step=25
            fi
            setBell_pitch $((CONSBELL_PITCH - $step))
            echo -e "\007"
            ;;
    esac
    echo "export CONSBELL_LENGTH='${CONSBELL_LENGTH}'" > $CONSBELL_SH
    echo "export CONSBELL_PITCH='${CONSBELL_PITCH}'" >> $CONSBELL_SH
    chmod 777 $CONSBELL_SH >/dev/null 2>&1
}


############
#
# Main
#
############


case $0 in
    *bash|*ksh)
        alias mute='setBell_length 0'
        alias unmute='setBell_length 1d'
        alias sndreset='setBell_pitch 750; setBell_length 1d'
        unset script_main
        ;;
    *)
        script_main "$@"
        ;;
esac


#################
#
#  End
