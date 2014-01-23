# -*- Makefile -*-
#
# Variables that are compiler- and architecture-specific.  This includes any
# optimization flags, since these usually differ from platform to platform.
#
#
# Copyright (C) 2010-2011 by John P. Weiss
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
# $Id$
##########
#
# Architecture.  Not used by all compilers.
#
##########


ARCH=generic
#ARCH=pentium4
#ARCH=athlon #athlon-4 #athlon-xp #athlon-mp
#ARCH=core2
#ARCH=athlon64-sse3 #opteron-sse3
#ARCH=pentium-m


# General architecture-specific compiler flags.
ARCHFLAGS= # -m128bit-long-double
# Others, possibly set by "-march" or "-mtune":
# -m3dnow -mmmx

# Define some variables that we later append to.
COMPILE_TYPE_COMMON =
COMPILE_TYPE =
AM_CFLAGS =
AM_CXXFLAGS =
AM_FFLAGS =



##########
#
# Special Compiler Args
#
##########


# Note:  -march implies & sets -mtune
##TARGET_ARCH=-march=$(ARCH) 
#    'generic' is not a valid value for -march, but does work with -mtune.
TARGET_ARCH=-mtune=$(ARCH)
TARGET_MACH=$(TARGET_ARCH)

# GNU-make special:  The $TARGET_ARCH and $TARGET_MACH variables are part of
# every implicit command.  If your project can be built on non-Linux
# platforms, you cannot count on GNU-make being there.  In that case,
# uncomment following two lines:
##AM_CFLAGS += $(TARGET_ARCH)
##AM_FFLAGS += $(TARGET_ARCH)

# Cross-linking libraries:

# Linux g77, compat-gcc v3.2
##F_LIBS += -lg2c
# Linux gfortran, gcc v4.
##F_LIBS += -static-libgfortran -lgfortran
# Solaris; IRIX
##F_LIBS += -lfortran


##########
#
# Definitons:  Optimization/Debugging/Profiling Flags
#
##########


OPTIMIZE=-O3 -mieee-fp -malign-double \
	-fexpensive-optimizations -fprefetch-loop-arrays \
	-funroll-loops -fpeel-loops -funswitch-loops -frerun-loop-opt \
	-fno-caller-saves
# Other optimizations:
#     -mfpmath=sse
#     -msse2
#     -msse3                          # for -march=core2 only
#     -maccumulate-outgoing-args
#     -minline-all-stringops
#  We'd need to try these out, one by one, and see how they improve
#  performance.
# Agressive Inlining:
#     -finline-limit=N #Default==600
#     --param large-function-growth=M #Default 100
#     --param inline-unit-growth=L #Default 50

DEBUG=-g3 -ggdb3 -DDEBUG
DISABLE_INLINE=-fno-inline -fno-default-inline
#Other GCC debugging options: -save-temps -time
#Those last two return information about the compilation.

# Disable all optimizations for (most) regression-testing.
REGRESSION_BASE=-O0
REGRESSION_CXX=$(DISABLE_INLINE)
REGRESSION=$(REGRESSION_BASE) $(REGRESSION_CXX)

GPROF_GCC=-pg
GCOV_GCC=-fprofile-arcs -ftest-coverage
PROFILE=$(GPROF_GCC) $(GCOV_GCC)

# Google Perftools Support:
CFLAGS_TCMALLOC=-fno-builtin-malloc -fno-builtin-calloc \
	-fno-builtin-realloc -fno-builtin-free
LIB_TCMALLOC=-ltcmalloc

# Add the architecture-specific flags to each compiler that takes them.  We
# will append "CFLAGS" onto "CXXFLAGS" later.
AM_CFLAGS += $(ARCHFLAGS)
AM_FFLAGS += $(ARCHFLAGS)

#
# Warnings (Per-Language)
#

AM_CFLAGS += -Wall -W -Wformat-security -Wshadow
# What this does:
#     -Wall: Use all warnings,
#     -W: use some additional ones
#     All remaining -Wxxx options are not included in "-Wall"
# Other useful C/C++ flags:
#     -pedantic
# This next one can get very noisy:
#     -Winline
# Other Useful non"-Wall" options:
#     -Wunreachable-code -Wno-deprecated-declarations
# Uncomment this for applications in which we need to treat the floating point
# types as approximations.
#AM_CFLAGS += -Wfloat-equal

AM_CXXFLAGS += -felide-constructors \
	-Wreorder -Wold-style-cast -Woverloaded-virtual
# What this does:
#     -Wreorder: Make sure construction order matches declaration order.
#     -Wold-style-cast:  Warn if we use C-casts in C++ code.
#     -Woverloaded-virtual: Self-explanatory.
#     -felide-constructors:  Snip out temporaries created by the compiler
#                            (like in return values to the RHS of op=(), etc.)
#                            On by default in the present g++, but let's just
#                            make sure...
# Other g++ flags:
#     -Wno-deprecated:  Disable warnings about older, non-std-compliant
#                       G++-ism.
# May not work well with STL implementations (makes too much noise)
#	-fhonor-std -Weffc++

#
# Other Per-Language Options
#

# Make C++ include the same flags as C.
AM_CXXFLAGS += $(AM_CFLAGS)

# Integer default size in FORTRAN
# [jpw; 201002]  This now appears deprecated, and INT is now 4 bytes by
# 				 default.  For now.
##AM_FFLAGS += -i4


# Set up for the compilation-type:
#
COMPILE_TYPE += $(COMPILE_TYPE_COMMON)
AM_CFLAGS += $(COMPILE_TYPE)
AM_CXXFLAGS += $(COMPILE_TYPE)
AM_FFLAGS += $(COMPILE_TYPE_COMMON)


##########
#
# How to compile:  Uncomment the appropriate lines:
#
##########


### Uncomment/Set for debugging & profiling

#DEBUG_FLAGS = 
#COMPILE_TYPE_COMMON += $(DEBUG) #$(PROFILE) #$(DEBUG_FLAGS)
#COMPILE_TYPE += $(DISABLE_INLINE)
#COMPILE_TYPE += -D_BUILDING_LIB -D_ENABLE_LIB_TRACING

### Uncomment for profiling, coverage, and/or memleak debugging:

#AM_LDFLAGS += $(PROFILE)
#AM_LDFLAGS += -lefence
#AM_LDFLAGS += -ldmalloc -ldmallocxx
#AM_CFLAGS += $(CFLAGS_TCMALLOC)
#AM_LDFLAGS += $(LIB_TCMALLOC)

### Uncomment/Set for an optimized build

#COMPILE_TYPE += $(OPTIMIZE)

### Uncomment/Set for regression tests:

## For Mixed-Language Projects
## Remove if not needed
#COMPILE_TYPE_COMMON += $(REGRESSION_BASE)
#COMPILE_TYPE += $(REGRESSION_CXX)

## For C++-Only Projects
## Remove if not needed
#COMPILE_TYPE += $(REGRESSION)


#################
#
#  End
