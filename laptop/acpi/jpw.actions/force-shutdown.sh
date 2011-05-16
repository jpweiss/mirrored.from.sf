#!/bin/bash
# [jpw] Adapted from /etc/acpi/powerbtn.sh
# Initiates a shutdown when the power putton has been
# pressed.

# Skip if we just in the middle of resuming.
test -f /var/lock/acpisleep && exit 0

# Force a shutdown.
/sbin/shutdown -h now "Power button pressed"
