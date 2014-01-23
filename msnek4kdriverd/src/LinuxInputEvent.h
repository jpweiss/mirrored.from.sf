// -*- C++ -*-
// Header file for class LinuxInputEvent
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
// $Id$
//
#ifndef _LinuxInputEvent_H_
#define _LinuxInputEvent_H_

// Includes
//
#include <stdint.h>
#include <sys/time.h>
#include "LinuxInputDevice.h"


// Enclosing namespace
//
namespace jpwTools {
 // Class LinuxInputEvent
 /**
  * A POD-struct for manipulating linux input events.
  *
  * Based, in part, on information from the Linux Kernel Documentation and
  * "linux/input.h".
  */
 struct LinuxInputEvent
 {
 public:
     // Notice that the members of this struct require no padding.  All
     // adjacent members smaller than a word fit within a single word.

     /// The time at which the input event occurred.
     timeval evTime;  // sizeof(timeval) == 2 x wordsize.
     /// The type of input event.
     uint16_t evType;
     /// What event happened.  Its meaning depends on the value of \c evType.
     uint16_t evCode;
     /// The event "value".  Its meaning depends on the value of \c evType.
     uint32_t evValue;

     // Static member constants.  See "linux/input.h".
     static const uint16_t evt_SYNCHRONIZE;
     static const uint16_t evt_KEY;
     static const uint16_t evt_RELATIVE_MOTION;
     static const uint16_t evt_ABSOLUTE_MOTION;
     static const uint16_t evt_MISC;
     static const uint16_t evt_SWITCH;
     static const uint16_t evt_LED;
     static const uint16_t evt_SOUND;
     static const uint16_t evt_AUTOREPEAT;
     static const uint16_t evt_FORCE_FEEDBACK;
     static const uint16_t evt_POWER;
     static const uint16_t evt_FORCE_FEEDBACK_STATUS;
     static const uint16_t evt_MAX;
 };

}; //end namespace


#endif //_LinuxInputEvent_H_
/////////////////////////
//
// End
