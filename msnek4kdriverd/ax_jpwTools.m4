## A set of custom Autoconf macros that I commonly use.
##
## Copyright (C) 2010-2011 by John P. Weiss
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the Artistic License, included as the file
## "LICENSE" in the source code archive.
##
## This package is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
##
## You should have received a copy of the file "LICENSE", containing
## the License John Weiss originally placed this program under.
##
## $Id$
#############


## AX_JPW_REQUIRE([<feature_name>],
##                [<what-failed>],
##                [<cache-variable-prefix>])
##
## Abort with an error if a specific feature isn't defined.
##
## "<feature-name>" will be either the name of a feature, or the part of a
## cache variable name following the "_cv_" infix.
##
## Specifically, if a test defines a flag in "config.h" named 
## 'HAVING_FOO_THING', then the "<feature-name>" will be "FOO_THING".  Most
## library- and function-checking macros are named "AC_<feature-name>"
## or "AC_<feature-name>", which also makes it easy to identify the
## "<feature-name>".
##
## {Optional}
## "<what-failed>" is a description of the feature.  It should be a noun,
## since it will be included in a standard error message.
##
## Omitting this argument, or passing the empty string, is equivalent to using
## [feature "<feature-name"] as the second argument.
##
## {Optional}
## "<cache-variable-prefix>" is, as the name implies, the prefix on the cache
## variable that is actually being checked.  Usually either "ac" or "ax", 
## which also happens to be the prefix of the library- or function-checking 
## macro for "<feature-name>".
##
## Omitting this argument, or passing the empty string, is equivalent to using
## [ac] as the third argument.
##
AC_DEFUN([AX_JPW_REQUIRE],
[
  jpw__feature_lc=m4_tolower([$1])
  jpw__cachevar_descr="$2"
  jpw__cachevar_prefix=m4_tolower([$3])
  if test "x$jpw__cachevar_prefix" = "x" ; then
    jpw__cachevar_prefix=ac
  fi

  if test "x$jpw__cachevar_descr" = "x" ; then
      jpw__cachevar_descr="feature \"$1\""
  fi

  jpw__cachevar_name="${jpw__cachevar_prefix}_cv_${jpw__feature_lc}"
  AS_VAR_COPY([jpw__cachevar_set], [$jpw__cachevar_name])

  if test "$jpw__cachevar_set" != "yes" ; then
    AC_MSG_ERROR([Error:  Failed to find $jpw__cachevar_descr.
                  Cannot continue.])
  fi
])


## AX_JPW_ADD_LIB_STATIC([<Lib>], [<DefineUnquoted>])
##
## Adds the library <Lib> to the list of libraries to link, but using static 
## linking.
##
## A '-l' is prepented to <Lib> and the resulting string added to the left of
## "LIBS"
##
## {Optional}
## "<DefineUnquoted>" is a flag.  If set to 'y', the "HAVE_LIB<Lib>" cpp
## constant will be defined.  If set to any other value, the
## "HAVE_LIB<DefineUnquoted>" cpp constant will be defined.
##
##
## {Dev.Note.:  Because of how AC_DEFINE_UNQUOTED & AS_TR_CPP and other m4
##              macros work, we need to pass our arguments directly to the
##              m4-macros.  Otherwise, we won't get the correct behavior
##              when running auto(re)conf.}
##
AC_DEFUN([AX_JPW_ADD_LIB_STATIC],
[
  LIBS="-Wl,-Bstatic $1 -Wl,-Bdynamic $LIBS"
  m4_ifval([$2],
           [m4_if([$2], [y],
                  [AH_CHECK_LIB([$1])
                   AC_DEFINE_UNQUOTED(AS_TR_CPP(HAVE_LIB$1))],
                  [AH_CHECK_LIB([$2])
                   AC_DEFINE_UNQUOTED(AS_TR_CPP(HAVE_LIB$2))]
                  )],
           [])
])


## AX_JPW_ADD_BOOST_PROGRAM_OPTIONS([<static>], [<is_mt>])
##
## Invokes the following:
## 
##     AX_BOOST_PROGRAM_OPTIONS
##     AX_JPW_REQUIRE([BOOST_PROGRAM_OPTIONS], [boost::program_options], [ax])
##
## ...then adds $BOOST_PROGRAM_OPTIONS_LIB to "LIBS".
##
## {Optional}
## "<static>" is a flag.  If set (to anything), the library will be added
## using AX_JPW_ADD_LIB_STATIC
##
## {Optional}
## "<not_mt>" is a flag.  If set (to anything), the non-reentrant version of
## the library is added instead of the multithreaded one
##
##
## {Dev.Note.:  Because of how m4 macros work, we need to pass our
##              arguments directly to the m4-macros.  Otherwise, we 
##              won't get the correct behavior when running auto(re)conf.}
##
AC_DEFUN([AX_JPW_ADD_BOOST_PROGRAM_OPTIONS],
[
  AX_BOOST_PROGRAM_OPTIONS
  AX_JPW_REQUIRE([BOOST_PROGRAM_OPTIONS], [boost::program_options], [ax])

  jpw__b_po_lib="$BOOST_PROGRAM_OPTIONS_LIB"
  m4_ifval([$2],
           [jpw__b_po_lib=`echo $jpw__b_po_lib | sed -e 's/-mt$//'`],
           [])

  m4_ifval([$1],
           [AX_JPW_ADD_LIB_STATIC([$jpw__b_po_lib],
                                  [boost_program_options])],
           [LIBS="$jpw__b_po_lib $LIBS"])
])


## AX_JPW_CHECK_LIB([<Function>],
##                  [<Lib>],
##                  [<staticLinking>],
##                  [<OtherLibs>])
##
## Invokes:
##     AC_CHECK_LIB(<Lib>, <Function>, [CUST_ADD], [CUST_ERR], <OtherLibs>)
##
## ...where "CUST_ADD" and "CUST_ERR" are custom operations described below.
##
## "CUST_ERR" is a call to "AC_MSG_ERROR" using the error message:
##     "Failed to the <Lib> library.  Cannot continue."
## 
## "CUST_ADD" performs the same operations as AC_CHECK_LIB, with one 
## special addition.  If the argument "<staticLinking>" is not empty, the
## libraries added will be statically-linked.
##
## {Dev.Note.:  Because of how AC_CHECK_LIB works, we need to pass our
##              arguments directly to AC_CHECK_LIB and the other m4-macros.
##              Otherwise, we won't get the correct behavior when running
##              auto(re)conf.}
##
AC_DEFUN([AX_JPW_CHECK_LIB],
[
  jpw__tstErrMsg="Error:  Failed to find the \"$jpw__tstLib\" library.
                  Cannot continue."

  m4_ifval([$3],
           [AC_CHECK_LIB([$1], [$2],
                         [AX_JPW_ADD_LIB_STATIC([$1], y)],
                         [AC_MSG_ERROR([$jpw__tstErrMsg])], [$4])
           ],
           [AC_CHECK_LIB([$1], [$2], [],
                         [AC_MSG_ERROR([$jpw__tstErrMsg])], [$4])
           ])
])


## AX_JPW_SET_VAR_DEFAULT([<varname>],
##                        [<default-value>])
##
## Run this macro to provide a 'configure' variable with a default value.
##
## "<varname>" is the name of a custom variable that users can pass to
## 'configure' on the commandline.
##
## "<default-value>" is the value that "<varname>" should have if not
## explicitly passed to 'configure' on the commandline.
##
AC_DEFUN([AX_JPW_SET_VAR_DEFAULT],
[
   AC_CONFIG_COMMANDS_PRE(
   [
     jpw__varname="$1"
     jpw__defaultval="$2"

     AS_VAR_COPY([jpw__varval], [$jpw__varname])
     if test "x$jpw__varval" = "x"; then
       AS_VAR_COPY([$jpw__varname], [jpw__defaultval])
     fi
   ])
])


## AX_JPW_ARG_MAKEFILE_VAR([<varname>],
##                         [<default-value>],
##                         [<var-doc>])
##
## Invokes "AC_ARG_VAR([<varname>], [<var-doc>])" followed by
## "AX_JPW_SET_VAR_DEFAULT([<varname>], [<default-value>])".  See their
## respective documentation for more info.
##
## You might also consider using the AC_SUBST macro.
##
AC_DEFUN([AX_JPW_ARG_MAKEFILE_VAR],
[
   AC_ARG_VAR([$1], [$3])
   AX_JPW_SET_VAR_DEFAULT([$1], [$2])
])


## This is an internal helper macro.  No user-servicable parts inside.
##
AC_DEFUN([AX_JPW_EXPORT_PATH_TO_CONFIG_H__IMPL],
[
  AC_CONFIG_COMMANDS_PRE(
  [
    # [jpw] FIXME:  The following check doesn't do what I wanted.  I wanted
    # 'autoconf'/'autoreconf' to perform it to warn developers if they have
    # typos or such.
    #
    # Unfortunately, (A) it creates a test in 'configure'; (B) 'autoconf'
    # always evaluates it as 'false'.  I guess it doesn't know about 'prefix'
    # variable and friends.
    #
    #if AS_VAR_TEST_SET([$2]); then
      AS_VAR_COPY([jpw__path_expanded_val], [$2])
      eval jpw__path_expanded_val=$jpw__path_expanded_val
      AC_DEFINE_UNQUOTED([$1],
                         ["$jpw__path_expanded_val"],
                         [Exported from Autoconf's 'configure' script: 
                          the "--sysconfdir" setting.])
    #else
    #  m4_fatal([FATAL ERROR:  Programmer-misuse.
    #            No such Autoconf variable, "$2".])
    #fi
  ])
])


## AX_JPW_EXPORT_PATH_TO_CONFIG_H([<autoconf-variable>])
##
## "Exports" an Autconf variable to your C/C++ source.
## 
## Specifically, defines a CPP macro in "config.h".  The name of the macro
## always begins with "ACPATH_", and is followed by "<autoconf-variable>"
## all-uppercased.
##
## The macro's value is a string constant, containing the value of
## <autoconf-variable> as set by 'configure'.
##
## Example:
##
##    # Set in configure.ac:
##    AX_JPW_EXPORT_PATH_TO_CONFIG_H([datadir])
##    AX_JPW_EXPORT_PATH_TO_CONFIG_H([localstatedir])
##
##    # How you ran 'configure':
##    configure --prefix=/opt/custom/WhizBangPackage \
##        --localstatedir=/opt/var
##
##    # How you ran 'make':
##    make DESTDIR=$HOME/src/buildarea
##
## After running 'autoconf' (or 'autoreconf') 'config.h.in' will contain:
## "#undef ACPATH_DATADIR" and "#undef ACPATH_LOCALSTATEDIR".  The second part
## of the example creates the following two entries in "config.h":
##   #define ACPATH_DATADIR "/opt/custom/WhizBangPackage/share"
##   #define ACPATH_LOCALSTATEDIR "/opt/var"
## Notice that 'datadir' is _fully_ _expanded_.
##
## Finally, the example's last part _has_ _no_ _effect_ _whatsoever_ on the
## ACPATH_DATADIR and ACPATH_LOCALSTATEDIR macros in "config.h".  This is by
## design.  The value of any "ACPATH_" macros should tell your program where
## it was _ultimately_ _installed_, not where it was built or installed for
## the sake of packaging.  Use them accordingly.
##
AC_DEFUN([AX_JPW_EXPORT_PATH_TO_CONFIG_H],
[
    m4_define([jpw__m4_config_h_name], [ACPATH_])
    m4_append([jpw__m4_config_h_name], m4_toupper([$1]))
    AX_JPW_EXPORT_PATH_TO_CONFIG_H__IMPL([jpw__m4_config_h_name],
                                         [$1])
])


## AX_JPW_CHECK_CXX_HEADERS([<header-file-list>],
##                          [<action-if-found>],
##                          [<action-if-not-found>],
##                          [<includes>])
##
## Equivalent of the standard 'AC_CHECK_HEADERS' Autoconf macro, but using the
## C++ compiler instead of the C compiler.  See the Autoconf documentation of
## 'AC_CHECK_HEADERS' for details.
##
AC_DEFUN([AX_JPW_CHECK_CXX_HEADERS],
[
  AC_LANG_PUSH(C++)
  AC_CHECK_HEADERS([$1], [$2], [$3], [$4])
  AC_LANG_POP([C++])    
])


## A canned error message for missing headers.
##
## Typically used as follows:
##
##     AC_CHECK_HEADERS([myheader.h foo.h], [], [AX_JPW_HEADER_ERROR])
##
AC_DEFUN([AX_JPW_HEADER_ERROR],
[
  AC_MSG_ERROR([Error:  Failed to find one or more 
                required headers.  Cannot continue.])
])


## AX_JPW_REQUIRE_CXX_HEADERS([<header-file-list>],
##                            [<includes>])
##
## Syntactic sugar around 'AX_JPW_CHECK_CXX_HEADERS'.  Equivalent to:
## 
##     AX_JPW_CHECK_CXX_HEADERS([<header-file-list>], [],
##                              [AX_JPW_HEADER_ERROR], [<includes>])
##
AC_DEFUN([AX_JPW_REQUIRE_CXX_HEADERS],
[
  AX_JPW_CHECK_CXX_HEADERS([$1], [], [AX_JPW_HEADER_ERROR], [$2])
])


## A canned error message for missing headers.
##
## Typically used as follows:
##
##     AC_CHECK_FUNCS([strerror fopen], [], [AX_JPW_FUNC_ERROR])
##
AC_DEFUN([AX_JPW_FUNC_ERROR],
[
  AC_MSG_ERROR([Error:  Failed to find one or more 
                required library functions.  Cannot continue.])
])


## Run this macro if building solely on Linux systems.
##
## On Linux systems, software whose binaries, data, and documents are
## installed under "/usr" install their configuration files under "/etc" and
## their state under "/var", not "/usr/etc" or "/usr/var".  Using this macro
## will eliminate the need to set the "--sysconfdir", "--sharedstatedir", and
## "--localstatedir" options when running 'configure'.
##
AC_DEFUN([AX_JPW_USE_FHS_DEFAULTS],
[
   AC_CONFIG_COMMANDS_PRE(
   [
     if test "$prefix" = /usr; then
       test "$sysconfdir" = '${prefix}/etc' && sysconfdir=/etc
       test "$sharedstatedir" = '${prefix}/com' && sharedstatedir=/var
       test "$localstatedir" = '${prefix}/var' && localstatedir=/var
     fi
   ])
])


## AX_JPW_CREATING_DEB_RPM([<path-to-.in-files>],
##                         [<deb-file-list>],
##                         [<rpm-file-list>])
##
## Run this macro if building on Linux systems.
##
## Both arguments are optional, and should specify lists of *.in files
## required by the packaging software.
##
## `configure' will also "install" the generated files if you set the envvar
## REBUILD_PACKAGING_FILES to any nonempty string.
##
## <path-to-.in-files>
##   This is the path containing the *.in files specified in the
##   <deb-file-list> and <rpm-file-list> arguments.
##
## <deb-file-list>
##   The each file should contain its path, relative to $(top_srcdir).
##   Usually will be the Debian packaging file, "control.in".  Each file is
##   copied to $(top_srcdir)/debian; if a file's name has the prefix
##   "debian.", the prefix will be removed after being copied.
##
## <rpm-file-list>
##   The each file should contain its path, relative to $(top_srcdir).
##   Usually will be just a *.spec.in file.  Each file is copied to
##   $(top_srcdir)
##
AC_DEFUN([AX_JPW_CREATING_DEB_RPM],
[
  jpw__path_ftb="$1"
  jpw__deb_ftb="$2"
  jpw__rpm_ftb="$3"
  jpw__bpf_cmds=""
  jpw__bpf_cflst=""

  AC_ARG_VAR([REBUILD_PACKAGING_FILES],
             [Used by maintainers to recreate static files.  Safe
              to ignore.])

  # Add the Debian packaging file(s), if there are any.
  if test "x$jpw__deb_ftb" != "x"; then
    for jpw__deb_file in $jpw__deb_ftb; do
      jpw__deb_file_src="${jpw__path_ftb}/${jpw__deb_file}"
      jpw__bpf_cflst="${jpw__bpf_cflst} ${jpw__deb_file_src}"
      jpw__deb_file_targ="debian/${jpw__deb_file#debian.}"
      jpw__deb_file_cp_cmd="cp $jpw__deb_file_src $jpw__deb_file_targ;"
      jpw__bpf_cmds="${jpw__bpf_cmds} ${jpw__deb_file_cp_cmd}"
    done
    unset jpw__deb_file
    unset jpw__deb_file_src
    unset jpw__deb_file_targ
    unset jpw__deb_file_cp_cmd
  fi

  # Add the RPM *.spec file(s), if there are any.
  if test "x$jpw__rpm_ftb" != "x"; then
    for jpw__rpm_file in $jpw__rpm_ftb; do
      jpw__rpm_file_src="${jpw__path_ftb}/${jpw__rpm_file}"
      jpw__bpf_cflst="${jpw__bpf_cflst} ${jpw__rpm_file_src}"
      jpw__bpf_cmds="${jpw__bpf_cmds} cp ${jpw__path_ftb}/${jpw__rpm_ftb} ./;"
    done
    unset jpw__rpm_file
    unset jpw__rpm_file_src
  fi


  # Now, add the "installation" commands, if we need them.
  AC_CONFIG_FILES([${jpw__bpf_cflst}])
  AC_CONFIG_COMMANDS_PRE([if test -n "${REBUILD_PACKAGING_FILES}"; then
                            if test -n "$jpw__bpf_cmds"; then
                              eval "$jpw__bpf_cmds"
                            fi
                          fi])
])


##################
## Local Variables:
## mode: autoconf
## End:
