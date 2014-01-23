##                                               -*- Makefile -*-
## Process this file with automake to produce Makefile.in
## 
## (Note:  Use double-comments with autoconf files.)
## 
## $Id$
#############


SUBDIRS = src manpage

sysconf_DATA = examples/msnek4k_driverd.conf
autoconf_automake_files = COPYING WARRANTY INSTALL NEWS AUTHORS \
	README ChangeLog
nobase_doc_DATA = $(autoconf_automake_files) examples/*

CLEANFILES = debian/files debian/*.debhelper.log


##
## Files to Package
##


package_template_files = *.spec pkgTemplates/*.in
## [jpw]  Note that we can't use debian/*, or we'll drag in files created
## during the package build.  And that's a Bad Thing.
debian_build_files = debian/changelog debian/compat debian/conffiles \
	debian/control debian/copyright debian/docs debian/rules

## [jpw]  I don't get why I need to specify the stuff in $(nobase_doc_DATA)
## here.  I thought that *_DATA macros added their files to the
## dist-manifest...
EXTRA_DIST = $(nobase_doc_DATA) $(debian_build_files) \
	$(package_template_files)


##
## [jpw]  Doxygen Support
##


include $(top_srcdir)/doxygen.am


##
## [jpw] Rules & vars for binary-only distribution.
##


rr__tar = $(am__tar) --owner=root --group=root
bindistdir_base = $(abs_top_srcdir)/bindist
bindistdir = $(distdir)-$${arch}
top_bindistdir = $(bindistdir_base)/$(bindistdir)
bindist_archive = $(PACKAGE_TARNAME)_$(PACKAGE_VERSION)-$${arch}


clean-bindist:
	-rm -rf $(bindistdir_base)

mostlyclean-local: clean-bindist

bindist-install-recurse:
	arch="bin_`uname -m`" && \
		$(MAKE) DESTDIR=$(top_bindistdir) install

bindist: bindist-install-recurse
	arch="bin_`uname -m`" && \
		cd $(top_bindistdir) && \
		tardir=. && \
		$(rr__tar) | \
			GZIP=$(GZIP_ENV) \
				gzip -c >$(bindistdir_base)/$(bindist_archive).tar.gz

bindist-bzip2: bindist-install-recurse
	arch="bin_`uname -m`" && \
		cd $(top_bindistdir) && \
		tardir=. && \
		$(rr__tar) | \
			bzip2 -9 -c >$(bindistdir_base)/$(bindist_archive).tar.bz2
