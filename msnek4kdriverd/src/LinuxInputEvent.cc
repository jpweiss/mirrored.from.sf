// -*- C++ -*-
// Implementation of class LinuxInputEvent
//
// Copyright (C) 2010-2011 by John Weiss
// This program is free software; you can redistribute it and/or modify
// it under the terms of the Artistic License, included as the file
// "LICENSE" in the source code archive.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//
// You should have received a copy of the file "LICENSE", containing
// the License John Weiss originally placed this program under.
//
static const char* const
LinuxInputEvent_cc__="$Id$";


// Includes
//
#include "LinuxInputEvent.h"

#include <linux/input.h>


using namespace jpwTools;


//
// Static variables
//


const uint16_t LinuxInputEvent::evt_SYNCHRONIZE=EV_SYN;
const uint16_t LinuxInputEvent::evt_KEY=EV_KEY;
const uint16_t LinuxInputEvent::evt_RELATIVE_MOTION=EV_REL;
const uint16_t LinuxInputEvent::evt_ABSOLUTE_MOTION=EV_ABS;
const uint16_t LinuxInputEvent::evt_MISC=EV_MSC;
const uint16_t LinuxInputEvent::evt_SWITCH=EV_SW;
const uint16_t LinuxInputEvent::evt_LED=EV_LED;
const uint16_t LinuxInputEvent::evt_SOUND=EV_SND;
const uint16_t LinuxInputEvent::evt_AUTOREPEAT=EV_REP;
const uint16_t LinuxInputEvent::evt_FORCE_FEEDBACK=EV_FF;
const uint16_t LinuxInputEvent::evt_POWER=EV_PWR;
const uint16_t LinuxInputEvent::evt_FORCE_FEEDBACK_STATUS=EV_FF_STATUS;
const uint16_t LinuxInputEvent::evt_MAX=EV_MAX;


/////////////////////////
//
// End
