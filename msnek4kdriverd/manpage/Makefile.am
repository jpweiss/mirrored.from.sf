##                                               -*- Makefile -*-
## Process this file with automake to produce Makefile.in
## 
## (Note:  Use double-comments with autoconf files.)
## 
## $Id$
#############


## [jpw]  Define targets and sources:
##
msnek4k_mansrc = msnek4k_driverd.sgml
msnek4k_mantarg = msnek4k_driverd.1
dist_man_MANS = $(msnek4k_mantarg)
EXTRA_DIST = $(msnek4k_mansrc) msnek4k_driverd.lyx docbook-refentry.layout

CLEANFILES = manpage.*


##
## [jpw] Rules for building the manpage
##

# The First 'perl' Command:
#   Remaps the UTF-8 encoded single-quote, double-quote, right-arrow, and (R)
#   characters.
# The Second 'perl' Command:
#   'docbook2man' forcibly uppercases the text of subsection headings, for
#   some reason.  This perl changes them to properly-capitalized headings.
$(msnek4k_mantarg):  $(msnek4k_mansrc)
	perl -p -i -e 's/&hellip;/.../g;' \
		-e 's/\xC2\xAE/\xAE/g;' \
		-e 's/\xE2\x80[\x9C\x9D]/"/g;' \
		-e 's/\xE2\x80[\x98\x99]/'"'"'/g;' \
		-e 's/\xE2\x86\x92/->/g;' \
		-e 's/&[lr]dquo;/"/g;' \
		-e 's/&[lr]squo;/'"'"'/g;' $?
	docbook2man $?
	perl -p -i -e 'if (m/^\.SS/) { \
		  s/\b([[:upper:]]+)\b/ucfirst(lc($$1))/ge; \
		  s/^\.Ss/.SS/i; \
		  s/\b(A[ns]?|For|From|Of|The|With)\b/lc($$1)/ge; \
		1; }' $@
