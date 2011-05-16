#!/bin/bash
#
# Copyright (C) 2009 by John P. Weiss
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


myPath=`dirname $0`
resetScreen="${myPath}/tpX40_ResetDisplay.sh"


############
#
# Functions
#
############


############
#
# Main
#
############


/usr/bin/chvt 1
if [ -x $resetScreen ]; then
   $resetScreen
fi


#################
#
#  End
