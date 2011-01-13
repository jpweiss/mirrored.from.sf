#!/bin/bash

if [ -z "$1" ]; then
    echo "usage: $0 <outfileBasename>"
    echo ""
    echo "<outfileBasename> should have no extension ('.xkb' is appended)."
    echo ""
    exit 0
fi

name="$1"
shift
xkbcomp -o "${name}.xkb" -a -xkb -dflts $DISPLAY
