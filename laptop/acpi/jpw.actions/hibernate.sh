#!/bin/bash

test -f /usr/share/acpi-support/state-funcs || exit 0

. /etc/default/acpi-support

#if [ x$ACPI_HIBERNATE != xtrue ] && [ x$1 != xforce ]; then
#  exit;
#fi

date > /tmp/last-hibernate-attempt

pm-hibernate
