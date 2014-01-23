## Process this file with autoconf to produce a configure script.
##
## (Note:  Use double-comments with autoconf files.)
##
## $Id$
#############

AC_PREREQ([2.65])
AC_INIT([msnek4k_driverd],
        [1.0.0],
        [jpwcandide@sourceforge.net],
        [msnek4k-driverd],
        [http://sourceforge.net/projects/msnek4kdriverd])
AC_CONFIG_HEADERS([config.h])

# [jpw]  My licensing and SVN revision variable.
AC_COPYRIGHT([Artistic License])
AC_REVISION([ $Revision$ ])

# [jpw] Pull in my custom macros.
# 
m4_include([ax_jpwTools.m4])


# [jpw] We're building on Linux only.  Follow the FHS layout.
AX_JPW_USE_FHS_DEFAULTS

# [jpw] We're building Debian and RPM packaging files.
#       Remember:  Run 'REBUILD_PACKAGING_FILES=y ./configure' to "reinstall"
#                  the generated packaging files.
AX_JPW_CREATING_DEB_RPM([pkgTemplates],
                        [debian.control debian.postinst],
                        [msnek4k-driverd.spec])


# [jpw] Default for XSESSIOND_PATH
AX_JPW_ARG_MAKEFILE_VAR([ETC_X11_PATH], 
                        [/etc/X11],
                        [Sets the path to X11's configuration directory (which
                         is where the "msnek4k_driverd.xmodmap" file will be
                         installed).  Usually, this is "/etc/X11".  Set this
                         variable if your system needs to use an alternate
                         path.  Note that 'configure' will prepend the value
                         of $(DESTDIR), if defined, to this path
                         automatically.])

AX_JPW_ARG_MAKEFILE_VAR([XSESSIOND_PATH], 
                        [${ETC_X11_PATH}/Xsession.d],
                        [Sets the path to X11's 'Xsession.d' directory.  (The
                         daemon's startup script will be installed here.)
                         Usually, this is "${ETC_X11_PATH}/Xsession.d".  Set
                         this variable if your system needs to use an
                         alternate path.  Note that 'configure' will prepend
                         the value of $(DESTDIR), if defined, to this path
                         automatically.])

# [jpw] Add a config.h var corresponding to the 'sysconfdir' variable.
AX_JPW_EXPORT_PATH_TO_CONFIG_H([sysconfdir])

# [jpw]  Automake
AM_INIT_AUTOMAKE([-Wall color-tests])

# Checks for programs.
AC_PROG_CXX

# Checks for libraries.
AX_JPW_CHECK_LIB([Xtst], [XTestDiscard])

# Checks for header files.
AC_PATH_X
AC_CHECK_HEADERS([ fcntl.h stdint.h sys/time.h unistd.h \
                   X11/extensions/XTest.h X11/Xlib.h ],
                   [], [AX_JPW_HEADER_ERROR])

# [jpw] Check for required Boost headers that are part of header-only
#       libraries.
#
AX_JPW_REQUIRE_CXX_HEADERS([ boost/algorithm/string/case_conv.hpp \
                             boost/algorithm/string/classification.hpp \
                             boost/algorithm/string/predicate.hpp ])


# Checks for typedefs, structures, and compiler characteristics.
AC_HEADER_STDBOOL
AC_C_INLINE
AC_TYPE_MODE_T
AC_TYPE_PID_T
AC_TYPE_SSIZE_T
AC_TYPE_UINT16_T
AC_TYPE_UINT32_T

# Checks for library functions.
AC_FUNC_FORK
AX_JPW_REQUIRE([FUNC_FORK], [the fork() function])
AC_CHECK_FUNCS([dup2 strerror], [], [AX_JPW_FUNC_ERROR])


# [jpw] Common checks
AC_CXX_HEADER_STDCXX_TR1
AX_JPW_REQUIRE([CXX_STDCXX_TR1], [the C++ TR1 headers])
AX_BOOST_BASE
AX_JPW_ADD_BOOST_PROGRAM_OPTIONS(y, y)


# [jpw] Doxygen support
DX_DOXYGEN_FEATURE(ON)
DX_HTML_FEATURE(ON)
DX_PS_FEATURE(OFF)
DX_PDF_FEATURE(OFF)
DX_INIT_DOXYGEN([msnek4k-driverd])


# [jpw]  Nonstandard file:  "90x11-msnek4k_driverd".  It's not a
# configuration file, but it requires @bindir@ and @sysconfdir@ to be
# replaced.
AC_CONFIG_FILES([Makefile
                 src/Makefile
                 src/90x11-msnek4k_driverd
                 manpage/Makefile])

AC_OUTPUT


##################
## Local Variables:
## mode: autoconf
## End:
