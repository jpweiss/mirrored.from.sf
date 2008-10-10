#!/bin/sh


if [ -z "$1" ]; then
    echo "usage: $0 <mapFile>"
    exit 1
fi
cat $1 | xkbcomp - $DISPLAY
