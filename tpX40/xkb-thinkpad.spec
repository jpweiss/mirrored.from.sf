%define mySrcRoot /home/candide/src/xkb

%define _builddir %mySrcRoot
%define _topdir /tmp
%define _rpmdir  %mySrcRoot/RPMS
%undefine makeinstall
%undefine make

###
# 
Name: xkb-thinkpad
Summary: Extra "xkb" files for supporting recent ThinkPads.
Version: 1.0
Release: 1
Source: file://%mySrcRoot
URL: http://does.not.have.src.file/
License: Artistic
Group: User Interface/X

BuildRoot: %{_tmppath}/%{name}-buildroot
BuildArchitectures: noarch
Prefix: %{_prefix}


%description
xkb-support for IBM ThinkPads, mainly for the X40.

%prep
rm -rf %{buildroot}/*
mkdir -p %{buildroot}/usr/share/X11/xkb
if [ ! -d %_rpmdir ]; then mkdir -p %_rpmdir; fi

%build

%postun

%post

%install
%__cp -a --parents */thinkpad* %{buildroot}/usr/share/X11/xkb

%clean
rm -rf %{buildroot}/*

%files
    %defattr(-,root,root)
    %{_datadir}/*

%changelog
* Tue May 27 2008 John Weiss <jpw_public@frontiernet.net> 1.0
- Initial version.
