#!/bin/bash

test -f /usr/share/acpi-support/state-funcs || exit 0

. /etc/default/acpi-support

#if [ x$ACPI_HIBERNATE != xtrue ] && [ x$1 != xforce ]; then
#  exit;
#fi

if [ ! -d /tmp/logs ]; then
    mkdir /tmp/logs
    chown root.users /tmp/logs
    chmod ug+rw,+t /tmp/logs
fi
date > /tmp/last-hibernate-attempt

pm-hibernate
