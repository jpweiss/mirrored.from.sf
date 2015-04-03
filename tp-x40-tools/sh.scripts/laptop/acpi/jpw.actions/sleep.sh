#!/bin/bash

# [jpw] This is a very simple script.

if [ ! -d /tmp/logs ]; then
    mkdir /tmp/logs
    chown root.users /tmp/logs
    chmod ug+rw,+t /tmp/logs
fi
date > /tmp/logs/last-suspend-attempt

pm-suspend
