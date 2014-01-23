// -*- C++ -*-
// Header file for class LinuxInputDevice
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
#ifndef _LinuxInputDevice_H_
#define _LinuxInputDevice_H_

// Includes
//
#include <string>
#include <vector>

#include <boost/scoped_array.hpp>

#include <stdint.h>


// Forward Declarations
//
extern "C" {
// FIXME:  Would it be more efficent to use pselect()?  I came across
// something that said select() is more responsive, but I don't know if that's
// true or not.
    struct pollfd;
    typedef struct pollfd C_pollfd_t;
}


// Enclosing namespace
//
namespace jpwTools {
 // Using decls.
 //
 using std::string;
 using boost::scoped_array;


 // Class LinuxInputDevice
 /**
  * A class for accessing a Linux input device.
  *
  * At its most basic, this class wraps an integer Unix/POSIX file descriptor,
  * opened for reading on one of the Linux input devices.
  *
  * In addition, this class has a function for scanning the \c
  * "/dev/input/event*" devices for a matching device.
  */
 class LinuxInputDevice
 {
 public:
     typedef std::vector<uint32_t> cap_flag_vec_t;
     static const cap_flag_vec_t m__NULL_VEC;

     /// Constructor
     /**
      * Opens the device whose path is \a filename.
      *
      * \param filename
      * In addition to the full pathname to a device, this can also be the
      * string, \c "auto", which triggers autoscanning if both \a targVendor
      * and \a targProduct are also set.
      * \param targVendor
      * The vendor ID number of the device to search for.
      * \param targProduct
      * The product ID number of the device to search for.
      * \param fallback_byName
      * In the event that a device doesn't match by vendor & product ID, you
      * can specify a string to match against the device's display name.
      * \param requiredCapabilities
      * An optional vector of capability flags.  If specified, then any device
      * found by autoscanning must have these capabilities.
      * \param forbiddenCapabilities
      * An optional vector of capability flags.  If specified, then any device
      * found by autoscanning cannot have these capabilities.
      */
     LinuxInputDevice(const string& filename,
                      uint16_t targVendor = 0,
                      uint16_t targProduct = 0,
                      const string& fallback_byName = "",
                      const cap_flag_vec_t& requiredCapabilities=m__NULL_VEC,
                      const cap_flag_vec_t&
                      forbiddenCapabilities=m__NULL_VEC);

     /// Closes the file description if it was ever opened.
     ~LinuxInputDevice();

     /// Polls the input device.
     /**
      * \param timeout_msecs
      * A positive nonzero timeout value for the call to \c poll.  Don't make
      * this too small when calling from a loop, or your loop will chew up
      * CPU.
      *
      * \note
      * This function \em might use \c poll under the hood ... or it might use
      * \c pselect.  Don't make assumptions about the function's
      * implementation based on its name.
      */
     bool poll(int timeout_msecs);


     /// Reads an event from this device.
     /**
      * \param eventObj
      * The\c LinuxInputEvent to read the event data into.
      *
      * \param nonblocking
      * If \c true, attempt a nonblocking read.  Otherwise, this function will
      * block until there's data available to read.
      *
      * \return \c true if any data was read, \c false if the read failed
      * or if '<tt>nonblocking==true</tt>' and the read would've blocked.
      */
     bool read(LinuxInputEvent& eventObj, bool nonblocking=false);


 private:
     scoped_array<C_pollfd_t> m__pFds_sca;


     /// Read an object.
     /**
      * Reads a block of data the size of the object directly into the
      * object's memory area.  This requires \c T to be a POD type (including
      * POD-structs).
      *
      * When reading into a POD-struct, be mindful of alignment issues.  You
      * will likely get garbage-results if any members of \c objPtr are padded
      * by the compiler.
      */
     template<typename T>
     ssize_t reinterpret_read(T* objPtr);

     /// Calls the Unix/POSIX \c open() function for reading, throwing a
     /// std::ios_base::failure on error.
     static int openUnixReadFd(const string& filename);

     /// Scans the \c "/dev/input/event*" files for the desired device.
     static int scanForDevice(uint16_t targVendor,
                              uint16_t targProduct,
                              const string& fallback_byName,
                              const cap_flag_vec_t& requiredCapabilities,
                              const cap_flag_vec_t& forbiddenCapabilities);
 };

}; //end namespace


#endif //_LinuxInputDevice_H_
/////////////////////////
//
// End
