%define mySrcRoot /home/candide/src/xkb

%define _builddir %mySrcRoot/tpX40
%define _topdir /tmp
%define _rpmdir  %mySrcRoot/RPMS
%undefine makeinstall
%undefine make

###
# 
Name: xkb-thinkpad
Summary: Extra "xkb" files for supporting the ThinkPad X40.
Version: 1.1
Release: 0.fc8
Source: file://%{_builddir}
URL: http://does.not.have.src.file/
License: Artistic
Group: User Interface/X

BuildRoot: %{_tmppath}/%{name}-buildroot
BuildArchitectures: noarch
Prefix: %{_prefix}


%description
xkb-support for the IBM ThinkPad X40.

To Use:
-------
In your "/etc/X11/xorg.conf" file, create a section for the keyboard as
follows:

    Section "InputDevice"
        Identifier  "ThinkPadX40_Keys"
        Driver      "kbd"
        Option      "XkbModel"   "thinkpadx40"
        Option      "XkbRules"   "thinkpadx40"
        # Put whatever default options you want below; this is only an example.
        ##Option      "XkbOptions" "invert_numlock+unnumlock:ctrl"
    EndSection

See the bottom of the file "/usr/share/X11/xkb/rules/thinkpadx40.lst" for the
valid keyboard options.


%prep
rm -rf %{buildroot}/*
mkdir -p %{buildroot}/usr/share/X11/xkb
if [ ! -d %_rpmdir ]; then mkdir -p %_rpmdir; fi
rm -f %{_topdir}/SOURCES
ln -s %{mySrcRoot} %{_topdir}/SOURCES

%build

%postun

%post

%install
%__cp -a --parents */thinkpad* %{buildroot}/usr/share/X11/xkb

%clean
rm -rf %{buildroot}/*
rm -f %{_topdir}/SOURCES

%files
    %defattr(-,root,root)
    %{_datadir}/*

%changelog
* Fri Sep 25 2009 John Weiss <jpw_public@frontiernet.net> 1.0
- Renamed files from thinkpad to thinkpadx40.
* Fri Dec 05 2008 John Weiss <jpw_public@frontiernet.net> 1.0
- Updated to work with Fedora8/XOrg 7.3
* Tue May 27 2008 John Weiss <jpw_public@frontiernet.net> 1.0
- Initial version.
