##                                               -*- Makefile -*-
## Process this file with automake to produce Makefile.in
## 
## (Note:  Use double-comments with autoconf files.)
## 
## $Id$
#############


## [jpw]  Define targets and sources:
##
bin_PROGRAMS = msnek4k_driverd
msnek4k_driverd_SOURCES = Timer.h X11Display.h \
	LinuxInputEvent.h LinuxInputEvent.cc \
	LinuxInputDevice.h LinuxInputDevice.cc \
	Trace.cc Daemonizer.cc \
	Any.cc ProgramOptions_Base.cc msnek4k_driverd.cc \
	Any.h LibTrace.h Trace.h Daemonizer.h ProgramOptions_Base.h



## [jpw] Can't use dist_bin_SCRIPTS here, since that would install things to
## $(bindir), which is not what we want.  So, define a custom target.
##
## Note that defining the 'xsessiond_DATA' and 'etcx11d_DATA' macros causes
## Automake to create installation rules for them

etcx11ddir=$(ETC_X11_PATH)
# N.B.:  'etcx11d_DATA' requires 'etcx11ddir'
etcx11d_DATA = $(top_srcdir)/examples/msnek4k_driverd.xmodmap
## [jpw] Nothing here to clean up.  Also, 'examples/*' is already included in
## the src_dist by the toplevel makefile.

xsessionddir=$(XSESSIOND_PATH)
# N.B.:  'xessiond_DATA' requires 'xsessionddir'
xsessiond_DATA = 90x11-msnek4k_driverd
CLEANFILES = $(xsessiond_DATA)
EXTRA_DIST = 90x11-msnek4k_driverd.in


## [jpw]  System-Specific Makefile Vars and Generic Build-Customizations
##
include $(top_srcdir)/make.syscfg.mk



##
## [jpw] Supplemental Buld Rules
##


# Make the binary setuid-root.
install-exec-hook:
	chmod 6711 $(DESTDIR)$(bindir)/msnek4k_driverd
