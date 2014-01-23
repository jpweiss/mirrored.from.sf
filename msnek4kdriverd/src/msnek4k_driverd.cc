// -*- C++ -*-
// Implementation of a userspace driver for the keys on a "MS Natural(C)
// Ergonomic Keyboard 4000" not supported by Linux at present.
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
msnek4k_driverd_cc__="$Id$";


// Includes
//
#include <iostream>
#include <csignal>

// Required by the code that drops root privileges.
#include <unistd.h>
#include <cstring>
#include <cerrno>

// Required for keypress/release parsing.
#include <sys/time.h>

// Requires -lXtst
#include <X11/extensions/XTest.h>

// Required for XkbGetAutoRepeatRate
#include <X11/XKBlib.h>

#include <boost/lexical_cast.hpp>

#include "X11Display.h"
#include "LinuxInputDevice.h"
#include "LinuxInputEvent.h"
#include "Daemonizer.h"
#include "Timer.h"
// Requires '-lboost_program_options-mt'
#include "ProgramOptions_Base.h"

#include "config.h"


//
// Using Decls.
//
using std::ios_base;
using std::string;
using std::exception;
using std::cerr;
using std::cout;
using std::endl;
using std::flush;

using boost::lexical_cast;

using jpwTools::X11Display;
using jpwTools::LinuxInputDevice;
using jpwTools::LinuxInputEvent;


//
// Static variables
//


namespace g__ {
 const double ReloadCfgfile_secs=1.0;

 const string CopyrightInfo="Copyright (C) 2010-2011 by John Weiss\n"
     "This program is free software; you can redistribute it and/or modify\n"
     "it under the terms of the Artistic License.\n"
     "\n"
     "This program is distributed in the hope that it will be useful,\n"
     "but WITHOUT ANY WARRANTY; without even the implied warranty of\n"
     "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.\n"
     "\n"
     "Sourceforge project page:\n"
     "    \"" PACKAGE_URL "\"";
};


namespace ms {
 const uint16_t vendorId(0x45E);
 const uint16_t nek4kProductId(0xDB);
 const string nek4kName("Microsoft Natural\u00A9 Ergonomic Keyboard 4000");
};


//
// Typedefs
//


/////////////////////////

//
// Class:  ProgramOptions
//


class ProgramOptions
    : public jpwTools::boost_helpers::ReloadableProgramOptions_Base
{
    typedef jpwTools::boost_helpers::ReloadableProgramOptions_Base Base_t;

public:
    struct KbdMapping
    {
        uint16_t scancode;
        uint16_t x11Keycode;
        bool isMouseButton;
        bool isMouseWheel;

        KbdMapping()
            : scancode(0)
            , x11Keycode(0)
            , isMouseButton(false)
            , isMouseWheel(false) {}
    };

    // Member variables for individually storing program options.
    bool doNotDaemonize;
    string daemonLog;
    string kbdDriverDev;
    KbdMapping zoomUp;
    KbdMapping zoomDown;
    KbdMapping spell;


    // C'tor
    //
    // Usually, you can get away with omitting your public member variables.
    // It's better to use the:
    //
    //     value<T>(m__myMemberVar)->default_value(...)
    //
    // ...arg in the 'add_options()' call when defining your options to set a
    // member's default value.
    //
    explicit ProgramOptions(const string& theProgramName,
                            const string& defaultCfgfile)
        : Base_t(SIGUSR1, theProgramName, defaultCfgfile)
    {}

    // Complete the body of this function (see below).
    void defineOptionsAndVariables();

    virtual bool validateParsedOptions(b_po_varmap_t& varMap);
};


/////////////////////////

//
// ProgramOptions Member Functions
//


void ProgramOptions::defineOptionsAndVariables()
{
    using namespace boost::program_options;

    //
    // Commandline-only Options
    //

    addOpts()
        ("dbg",
         bool_switch(&doNotDaemonize)->default_value(false),
         "Run in the foreground instead of as a daemon.  No logfile is "
         "created."
         )
        ("zoom-up,U",
         value<uint16_t>(&(zoomUp.x11Keycode)),
         "The X11 keycode to generate when the Zoom jog is pressed up."
         )
        ("zoom-down,D",
         value<uint16_t>(&(zoomDown.x11Keycode)),
         "The X11 keycode to generate when the Zoom jog is pressed down."
         )
        ("spell,S",
         value<uint16_t>(&(spell.x11Keycode)),
         "The X11 keycode to map the Spell key to."
         )
        ;

    //
    // The Configuration File Variables:
    //

    addCfgVars()
        ("ZoomUp.scancode",
         value<uint16_t>(&(zoomUp.scancode))->default_value(0x1A2),
         "The raw keyboard scancode generated when the Zoom jog moves up.")
        ("ZoomUp.x11Keycode",
         value<uint16_t>(&(zoomUp.x11Keycode)),
         "The X11 keycode to generate when the Zoom jog is pressed up.")
        ("ZoomUp.isMouseButton",
         value<bool>(&(zoomUp.isMouseButton))->default_value(false),
         "When set to 'true', treats the value specified to "
         "\"ZoomUp.x11Keycode\" as a mouse button number.  Binds to this "
         "mouse button instead of a keycode.")
        ("ZoomUp.isMouseWheel",
         value<bool>(&(zoomUp.isMouseWheel))->default_value(false),
         "Set this to 'true' if the button number specified to "
         "\"ZoomUp.x11Keycode\" is for a mouse wheel.  Ignored unless "
         "\"ZoomUp.isMouseButton\" is set to true.")
        ("ZoomDown.scancode",
         value<uint16_t>(&(zoomDown.scancode))->default_value(0x1A3),
         "The raw keyboard scancode generated when the Zoom jog moves down.")
        ("ZoomDown.x11Keycode",
         value<uint16_t>(&(zoomDown.x11Keycode)),
         "The X11 keycode to generate when the Zoom jog moves down.")
        ("ZoomDown.isMouseButton",
         value<bool>(&(zoomDown.isMouseButton))->default_value(false),
         "When set to 'true', treats the value specified to "
         "\"ZoomUp.x11Keycode\" as a mouse button number.  Binds to this "
         "mouse button instead of a keycode.")
        ("ZoomDown.isMouseWheel",
         value<bool>(&(zoomDown.isMouseWheel))->default_value(false),
         "Set this to 'true' if the button number specified to "
         "\"ZoomUp.x11Keycode\" is for a mouse wheel.  Ignored unless "
         "\"ZoomDown.isMouseButton\" is set to true.")
        ("Spell.scancode",
         value<uint16_t>(&(spell.scancode))->default_value(0x1B0),
         "The raw keyboard scancode generated by the Spell key.")
        ("Spell.x11Keycode",
         value<uint16_t>(&(spell.x11Keycode)),
         "The X11 keycode to map the Spell key to.")
        ;

    //
    // Configuration File Variables that can also be passed as Commandline
    // Options:
    //

    // Environment variable:  DISPLAY.  Will be added to the shared options.
    addEnvvars(Base_t::SHARED)
        ("display,d", value<string>(),
         "Self-explanatory.  Required if not set elsewhere.");

    // Because of the overly-long defaults for some options, we need to use a
    // special option group, or the doc strings for the following won't
    // properly line-wrap.
    options_description otherShared_wrapper(usageLineLength());
    otherShared_wrapper.add_options()
        ("kbd-dev,k",
         value<string>(&kbdDriverDev)->default_value("auto"),
         "The full pathname of the keyboard device, or the special string, "
         "\"auto\"."
         )
        ("Zoom.isMouseButton,b", bool_switch()->default_value(false),
         "Same as setting \"ZoomUp.isMouseButton\" and "
         "\"ZoomDown.isMouseButton\" to the same value."
         )
        ("Zoom.isMouseWheel,w", bool_switch()->default_value(false),
         "Same as setting \"ZoomUp.isMouseWheel\" and "
         "\"ZoomDown.isMouseWheel\" to the same value."
         )
        ;
    addCfgVars(otherShared_wrapper, Base_t::SHARED);

    // Note:  The uber-long default value confuses the
    // boost::program_options engine, destroying the auto-formatting.  So, put
    // it in its own subgroup.
    string deflLogfile("/tmp/");
    deflLogfile += programName();
    deflLogfile += ".log";
    options_description logfile_descr_wrapper(usageLineLength());
    logfile_descr_wrapper.add_options()
        ("logfile,l",
         value<string>(&daemonLog)->default_value(deflLogfile.c_str()),
         "Self-explanatory.  Should contain an absolute path."
         )
        ;
    addCfgVars(logfile_descr_wrapper, Base_t::SHARED);
}


// Performs more complex program option validation.
//
// The boost::program_options engine handles most forms of validation.  More
// complicated processing, such as cross-option dependencies, should go in
// this member function.
//
bool ProgramOptions::validateParsedOptions(b_po_varmap_t& varMap)
{
    // Sanity-check:  make sure that certain variables are present.  They
    // should be, but we'll do this check to prevent the
    // boost::program_options engine from segfaulting
    if(varMap.empty())
    {
        cerr << "No options or settings parsed." << endl;
        return false;
    }
    // N.B.:  Should be able to remove the following.
    //        There seems to be some bug in boost::program_options that does
    //        weird things to a variables_map when you call 'notify()' on it
    //        w/o parsing anything into it first.  My guess is that's why the
    //        default value of some variables were "disappearing."
    else if(varMap["Zoom.isMouseButton"].empty() ||
            varMap["Zoom.isMouseWheel"].empty() ||
            varMap["verbose"].empty())
    {
        cerr << "Internal Error:  Setting:  \"";
        if(varMap["Zoom.isMouseButton"].empty()) {
            cerr << "Zoom.isMouseButton";
        } else if(varMap["Zoom.isMouseButton"].empty()) {
            cerr << "Zoom.isMouseWheel";
        } else {
            cerr << "verbose";
        }
        cerr << "\" is empty.  It should have a default value." << endl;
        return false;
    }

    // Handle Zoom.isMouseButton and Zoom.isMouseWheel:
    if(varMap["Zoom.isMouseButton"].as<bool>()) {
        zoomDown.isMouseButton = zoomUp.isMouseButton = true;
    }

    if(varMap["Zoom.isMouseWheel"].as<bool>()) {
        zoomDown.isMouseWheel = zoomUp.isMouseWheel = true;
    }

    // Not an error, but a misconfiguration.  Warn the user about it.
    if(varMap["verbose"].as<int>()) {
        if(zoomDown.isMouseWheel && !zoomDown.isMouseButton) {
            const char* section = ((zoomUp.isMouseWheel
                                    && !zoomUp.isMouseButton)
                                   ? "Zoom"
                                   : "ZoomDown");
            cerr << "Warning - Misconfiguration:  \""
                 << section << ".isMouseWheel\" is meaningless when "
                 << endl
                 << section << ".isMouseButton\"==false."
                 << endl
                 << "Ignoring error (consider fixing it)..."
                 << endl;
        } else if(zoomUp.isMouseWheel && !zoomUp.isMouseButton) {
            cerr << "Warning - Misconfiguration:  "
                 << "\"ZoomUp.isMouseWheel\" is meaningless when "
                 << endl
                 << "ZoomUp.isMouseButton\"==false."
                 << endl
                 << "Ignoring error (consider fixing it)..."
                 << endl;
        }
    }

    // Make sure that the specified keycodes are in range.
    require8BitSize(spell.x11Keycode, "Spell.x11Keycode", true);
    require8BitSize(zoomUp.x11Keycode, "ZoomUp.x11Keycode", true);
    require8BitSize(zoomDown.x11Keycode, "ZoomDown.x11Keycode", true);

    if( zoomDown.isMouseButton && (!zoomDown.x11Keycode ||
                                   (zoomDown.x11Keycode > 10)) ) {
        string errmsg("Invalid mouse button number:  "
                      "\"ZoomDown.x11Keycode\"==");
        errmsg += lexical_cast<string>(zoomDown.x11Keycode);
        errmsg += "\"\n(Zoom.isMouseButton or ZoomDown.isMouseButton"
            "erroneously set to \"true\"?";
        errmsg += "\nMouse buttons are numbered from 1 to 10.";
        throw boost::program_options::invalid_option_value(errmsg);
    }

    if( zoomUp.isMouseButton && (!zoomUp.x11Keycode ||
                                 (zoomUp.x11Keycode > 10)) ) {
        string errmsg("Invalid mouse button number:  "
                      "\"ZoomUp.x11Keycode\"==");
        errmsg += lexical_cast<string>(zoomUp.x11Keycode);
        errmsg += "\"\n(Zoom.isMouseButton or ZoomUp.isMouseButton"
            "erroneously set to \"true\"?";
        errmsg += "\nMouse buttons are numbered from 1 to 10.";
        throw boost::program_options::invalid_option_value(errmsg);
    }

    // For debugging purposes
    if(varMap["verbose"].as<int>() > 2) {
        print_variables_map(cerr);
    }

    return true;
}


/////////////////////////

//
// General Function Definitions
//


void dropRootPrivileges(unsigned verbose=0)
{
    // Drop root privileges by changing the effective uid/gid to the real
    // uid/gid.
    const char* const c_errmsg1="FATAL ERROR:  Changing ";
    const char* const c_errmsg2=" to ";
    const char* const c_errmsg3=" failed!\nReason:  \"";
    const char* const c_errmsg4="\"\n\nThis is a potential security hole.\n"
        "Aborting Immediately.";

    uid_t real_uid(getuid());
    if(verbose) {
        cout << "Dropping to UID==" << real_uid << endl;
        if(verbose > 1) {
            cout << "(from UID " << geteuid() << ")" << endl;
        }
    }
    int droprootStat = seteuid(real_uid);
    if(droprootStat < 0) {
        string errmsg(c_errmsg1);
        errmsg += "User ID";
        errmsg += c_errmsg2;
        errmsg += lexical_cast<uid_t>(real_uid);
        errmsg += c_errmsg3;
        errmsg += strerror(errno);
        errmsg += c_errmsg4;
        exit(9);
    }

    gid_t real_gid(getgid());
    if(verbose) {
        cout << "Dropping to GID==" << real_gid << endl;
        if(verbose > 1) {
            cout << "(from GID " << getegid() << ")" << endl;
        }
    }
    droprootStat = setegid(real_gid);
    if(droprootStat < 0) {
        string errmsg(c_errmsg1);
        errmsg += "Group ID";
        errmsg += c_errmsg2;
        errmsg += lexical_cast<gid_t>(real_gid);
        errmsg += c_errmsg3;
        errmsg += strerror(errno);
        errmsg += c_errmsg4;
        exit(9);
    }
}


void noteSignalAndIgnore(int sig)
{
    cerr << "Received signal: " << sig << ".  Ignoring." << endl;
}


void setupSignalHandling()
{
    struct sigaction sigspec;
    sigspec.sa_handler = noteSignalAndIgnore;
    sigspec.sa_flags = SA_RESTART;

    // Signals that normally terminate the process:
    sigaction(SIGHUP, &sigspec, 0);
    sigaction(SIGINT, &sigspec, 0);
    sigaction(SIGUSR2, &sigspec, 0);
    // Used only when the process creates pipes
    sigaction(SIGPIPE, &sigspec, 0);
    // N.B.:  SIGUSR1 is used by ReloadableProgramOptions_Base.

    // Don't restart SIGALRMs
    sigspec.sa_flags = 0;
    // An unhandled SIGALRM will also terminate the process.
    sigaction(SIGALRM, &sigspec, 0);
}


bool processKbdEvent(const LinuxInputEvent& kbdEvent,
                     X11Display& theDisplay,
                     const ProgramOptions& opts)
{
    if(kbdEvent.evType != LinuxInputEvent::evt_KEY) {
        return true;
    }

    int verbose = opts["verbose"].as<int>();

    ProgramOptions::KbdMapping mapping;

    // We just have 3 keys to map; no need to use a generic data structure.
    // Just copy the appropriate KbdMapping object to the working variable.
    if(kbdEvent.evCode == opts.zoomUp.scancode) {
        mapping = opts.zoomUp;
    } else if(kbdEvent.evCode == opts.zoomDown.scancode) {
        mapping = opts.zoomDown;
    } else if(kbdEvent.evCode == opts.spell.scancode) {
        mapping = opts.spell;
    } else {
        // Unknown keycode.  Ignore it.
        if(verbose) {
            cerr << "[" << std::fixed
                 << (kbdEvent.evTime.tv_sec
                     + kbdEvent.evTime.tv_usec/1000000.0)
                 << "] Key "
                 << (kbdEvent.evValue ? "Pressed" : "Released")
                 << ":  unknown scancode==0x"
                 << std::hex << kbdEvent.evCode << endl;
        }
        return true;
    }

    if(verbose > 1) {
        cout << "[" << std::fixed
             << kbdEvent.evTime.tv_sec + kbdEvent.evTime.tv_usec/1000000.0
             << "] Key "
             << (kbdEvent.evValue ? "Pressed" : "Released")
             << ":  scancode==0x"
             << std::hex << mapping.scancode << std::dec
             << (mapping.isMouseButton
                 ? (mapping.isMouseWheel
                    ? " ==> mouse wheel button #"
                    : " ==> mouse button #")
                 : " ==> X11 keycode: ")
             << mapping.x11Keycode
             << endl;
    }

    // kbdEvent.evValue contains the pressed/released value.

    bool flushRequired(true);
    int sentOk(1);
    if(mapping.isMouseButton) {

        if(mapping.isMouseWheel) {
            // When treating a button as a mouse wheel, ignore release events.
            // Perform both a button press and release instead.
            if(kbdEvent.evValue) {
                sentOk = XTestFakeButtonEvent(theDisplay,
                                              mapping.x11Keycode,
                                              true,
                                              CurrentTime);
                // '&&' the previous value of "sentOk" to the return value
                // ... _after_ the fn. call.
                sentOk = XTestFakeButtonEvent(theDisplay,
                                              mapping.x11Keycode,
                                              false,
                                              CurrentTime)
                    && sentOk;
            } else {
                // When we ignore an event, don't flush.
                flushRequired = false;
            }
        } else {
            sentOk = XTestFakeButtonEvent(theDisplay, mapping.x11Keycode,
                                          kbdEvent.evValue, CurrentTime);
        }

    } else {

        sentOk = XTestFakeKeyEvent(theDisplay, mapping.x11Keycode,
                                   kbdEvent.evValue, CurrentTime);

    }

    int flushOk(1);
    // Since release events are ignored when using Zoom as a mouse wheel,
    // don't flush in that case.
    if(flushRequired) {
        flushOk = XFlush(theDisplay);
    }

    if(!sentOk) {
        cerr << "Failed to send a "
             << (mapping.isMouseButton
                 ? (mapping.isMouseWheel
                    ? "mouse wheel "
                    : "mouse button ")
                 : "key ")
             << (kbdEvent.evValue ? "press " : "release ")
             << "event for scancode==0x"
             << std::hex << mapping.scancode << std::dec
             << endl;
    }
    if(verbose && !flushOk) {
        cerr << "Failed to flush the X event buffer." << endl;
    }

    return (sentOk && flushOk);
}


void fixLEDsIfNeeded(X11Display& theDisplay, XkbDeviceInfoPtr xkbdDevInf)
{
    // FIXME:  ChecK that XkbDeviceInfoPtr is non-NULL.
    // FIXME:  Correct the last 3 options.
    Status xkbStat = XkbGetDeviceLedInfo(theDisplay, xkbdDevInf,
                                         0, //LED class
                                         0, //LED ID
                                         // FIXME:  Do I need the State
                                         // & Maps masks?
                                         XkbXI_IndicatorStateMask
                                         | XkbXI_IndicatorMapsMask
                                         | XkbXI_IndicatorNamesMask);

#if 0
    // Alternative:
    unsigned ledStatus;
    Status xkbStat = XkbGetIndicatorState(theDisplay,
                                          XkbUseCoreKbd, ledStatus);
    // Need to use XkbGetNamedIndicator to find out which bits mean what.
    // Evidently XkbSetNamedIndicator sets the LED.
#endif

    // Any errors?  Punt.
    if(xkbStat != Success) {
        return;
    }

    // FIXME:  Get the state of each lock key, not just the LED state.
    // FIXME:  Compare and, if needed, reset.
    // FIXME:  Below is code copies from "xkbvleds.c"
/* 
    if (wantReal || wantNamed || wantAutomatic || wantExplicit || wantVirtual) {
	register int i,bit;
	xkb= XkbGetMap(inDpy,0,XkbUseCoreKbd);
	if (!xkb) {
	    uFatalError("Couldn't read keymap\n");
	    return 1;
	}
	if (XkbGetIndicatorMap(inDpy,XkbAllIndicatorsMask,xkb)!=Success) {
	    uFatalError("Couldn't read indicator map\n");
	    return 1;
	}
	if (XkbGetNames(inDpy,XkbAllNamesMask,xkb)!=Success) {
	    uFatalError("Couldn't read indicator names\n");
	    return 1;
	}
	for (i=0,bit=1;i<XkbNumIndicators;i++,bit<<=1) {
	    XkbIndicatorMapPtr map= &xkb->indicators->maps[i];
	    if (xkb->names->indicators[i]!=None)
		named|= bit;
	    if (xkb->indicators->phys_indicators&bit)
		real|= bit;
	    if ((((map->which_groups!=0)&&(map->groups!=0))||
		((map->which_mods!=0)&&
		((map->mods.real_mods!=0)||(map->mods.vmods!=0)))||
		(map->ctrls!=0))&&
		((map->flags&XkbIM_NoAutomatic)==0)) {
		automatic|= bit;
	    }
	    else explicit|= bit;
	}
	virtual= ~real;
	if (wantReal==NO)			real= ~real;
	else if (wantReal==DONT_CARE)		real= (useUnion?0:~0);
	if (wantVirtual==NO)			virtual= ~virtual;
	else if (wantVirtual==DONT_CARE)	virtual= (useUnion?0:~0);
	if (wantNamed==NO)			named= ~named;
	else if (wantNamed==DONT_CARE)		named= (useUnion?0:~0);
	if (wantAutomatic==NO)			automatic= ~automatic;
	else if (wantAutomatic==DONT_CARE)	automatic= (useUnion?0:~0);
	if (wantExplicit==NO)			explicit= ~explicit;
	else if (wantExplicit==DONT_CARE)	explicit= (useUnion?0:~0);
	if (useUnion)
	     wanted|= real|virtual|named|automatic|explicit;
	else wanted&= real&virtual&named&automatic&explicit;
    }
    else xkb= NULL;
    if (wanted==0) {
	uError("No indicator maps match the selected criteria\n");
	uAction("Exiting\n");
	return 1;
    }

    XkbSelectEvents(inDpy,XkbUseCoreKbd,XkbIndicatorStateNotifyMask,
						XkbIndicatorStateNotifyMask);
    XkbGetIndicatorState(inDpy,XkbUseCoreKbd,&n);
    bit= (1<<(XkbNumIndicators-1));
    for (i=XkbNumIndicators-1;i>=0;i--,bit>>=1) {
	if (wanted&bit) {
	    char 	buf[12];
	    ArgList	list;

	    sprintf(buf,"led%d",i+1);
	    if (n&bit)	list= onArgs;
	    else	list= offArgs;
	    leds[i]= XtCreateManagedWidget(buf,ledWidgetClass,panel,list,1);
	}
    }
*/
}


/////////////////////////

//
// Functions "main()" and "cxx_main()"
//


// This is where all of your main handling should go.
int cxx_main(const string& myName,
             const string& /*myPath*/,
             ProgramOptions& opts)
{
    // First things first:  daemonize yourself.
    jpwTools::process::DiabLogStream dlog_st;
    if(!opts.doNotDaemonize) {
        dlog_st.open(opts.daemonLog);
        if(!dlog_st.is_open()) {
            string errmsg("Failed to open log file for writing: \"");
            errmsg += opts.daemonLog;
            errmsg += '"';
            throw std::ios_base::failure(errmsg);
        }
        jpwTools::process::daemonize(dlog_st);
    }

    // X11/XTest Setup
    X11Display theDisplay(opts["display"].as<string>());
    int xtqeDummy;
    bool hasXTest = XTestQueryExtension(theDisplay,
                                        &xtqeDummy, &xtqeDummy,
                                        &xtqeDummy, &xtqeDummy);
    if(!hasXTest) {
        string errmsg("The XTest extension is not installed "
                      "or not available.\n");
        errmsg += myName;
        errmsg += " requires XTest in order to run.\n\n"
            "Cowardly refusing to continue.";
        throw std::runtime_error(errmsg);
    }

    // Open the keyboard device or autoscan for it.

    LinuxInputDevice::cap_flag_vec_t required;
    required.push_back(LinuxInputEvent::evt_RELATIVE_MOTION);
    required.push_back(LinuxInputEvent::evt_ABSOLUTE_MOTION);

    LinuxInputDevice::cap_flag_vec_t forbidden;
    forbidden.push_back(LinuxInputEvent::evt_LED);

    LinuxInputDevice kbdDev(opts.kbdDriverDev, ms::vendorId,
                            ms::nek4kProductId, ms::nek4kName,
                            required, forbidden);

    // At this point, we no longer need to be root.
    dropRootPrivileges(opts["verbose"].as<int>());

    // The default on several signals is "terminate the process".  We don't
    // necessarily want that.
    setupSignalHandling();

    // To make this driver more responsive, we'll poll the input device and
    // time out periodically.  For the timeout interval, we'll use 10 times
    // the X keyboard auto-repeat delay.
    //
    // Why the X keyboard auto-repeat delay?  It's user-controlled, and it
    // already encapsulates a measure of "keyboard responsiveness".
    //
    // Why 2?  The timeout should be short enough to keep this process active,
    // but long enough to keep it from chewing up CPU.  So, it should be a
    // longer than the X keyboard auto-repeat delay by some factor.

    unsigned xkbGARRdummy;
    unsigned pollTimeoutInterval;
    XkbGetAutoRepeatRate(theDisplay, XkbUseCoreKbd,
                         &pollTimeoutInterval, &xkbGARRdummy);
    pollTimeoutInterval *= 2;
    if(!pollTimeoutInterval) {
        // Use a default of 1 second.
        pollTimeoutInterval = 1;
    }

    //
    // The Main Loop
    //

    XkbDeviceInfoPtr xkbdLedInfoBuf(0);
    XkbAllocDeviceLedInfo(xkbdLedInfoBuf, 0);
    XkbAddDeviceLedInfo(xkbdLedInfoBuf, 0);

    LinuxInputEvent kbdEvent;
    jpwTools::Timer reloadCfgTimer;

    while(true)
    {
        // Wait for something to happen on the keyboard device.
        if(kbdDev.poll(pollTimeoutInterval))
        {
            // Get the keyboard event.
            if(kbdDev.read(kbdEvent)) {
                processKbdEvent(kbdEvent, theDisplay, opts);
            }

            // Check if the config. file needs to be reread.  We won't do this
            // every keyboard event.  After all, if the user is holding down
            // the Zoom Rocker, they can't be running 'kill -USR1' on this
            // process over and over again.  ^_^
            if(g__::ReloadCfgfile_secs <= reloadCfgTimer.elapsed()) {
                opts.reparseIfPending(dlog_st);
                reloadCfgTimer.stop();
            }
        }

        // Special value-added feature:  Check that the LEDs are all set
        // according to the kbd state.  For some reason, the kernel and/or X
        // get confused and toggle the state of more than one LED when NumLock,
        // ScrollLock, and/or CapsLock are hit.
        fixLEDsIfNeeded(theDisplay, xkbdLedInfoBuf);
    }
}


int main(int argc, char* argv[])
{
    // Split off the name of the executable from its path.
    string myName(argv[0]);
    string::size_type last_pathsep = myName.find_last_of('/');
    string myPath;
    if(last_pathsep != string::npos) {
        myPath = myName.substr(0, last_pathsep+1);
        myName.erase(0, last_pathsep+1);
    }

    // Call cxx_main(), which is where almost all of your code should go.
    try {
        //jpwTools::Trace::tracingEnabled=true;

        ProgramOptions myOpts(myName, (ACPATH_SYSCONFDIR "/"));
        myOpts.setVersion(PACKAGE_VERSION, g__::CopyrightInfo);

        bool parsedOk = myOpts.parse(argc, argv);
        if(!parsedOk) {
            cerr << "Fatal Error:  "
                 << endl
                 << "Unable to parse commandline arguments "
                 << "and/or configuration file."
                 << endl
                 << endl
                 << "Cannot continue."
                 << endl;
            return 1;
        }

        return cxx_main(myName, myPath, myOpts);
    } catch(std::ios_base::failure& ex) {
        cerr << "I/O Error: " << ex.what() << endl;
        return 2;
    } catch(boost::program_options::duplicate_option_error& ex) {
        cerr << "Fatal Internal Programming Error:  "
             << endl
             << ex.what()
             << endl << endl;
        return 9;
    } catch(boost::program_options::error& ex) {
        cerr << "Error while parsing program options: " << ex.what()
             << endl << endl
             << "Rerun as \"" << myName << " --help\" for usage."
             << endl;
        return 1;
    } catch(exception& ex) {
         cerr << endl << "(Std) Exception caught: \""
              << ex.what() << "\"" << endl;
    } catch(...) {
        cerr << "Unknown exception caught." << endl;
    }
    return -1;
}


/////////////////////////
//
// End
