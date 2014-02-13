mirrored.from.sf
================

The "sf" == "SourceForge"

---

# Overview #

This repository contains the source-code of my SourceForge projects:

* msnek4kdriverd
  - The `msnek4kDriverDaemon`, an X11-based driver for the handful of
    keys on the "Microsoft Natural® Ergonomic Keyboard 4000" that
    aren't supported by the Linux kernel.
  - Written in C++
  - http://sourceforge.net/projects/msnek4kdriverd/

* pkgBackup
  - Back up your `*.rpm`- or `*.deb`-based system by only saving the
    *changes* you've made to the files installed from a package.
    You're already backing up your packages, so why back up the same
    files twice?
  - Written in Perl.
  - http://sourceforge.net/projects/pkgbackup/

* mrtgAddons4Dsl
  - Perl scripts and configuration files for MRTG.
    Both scripts provide information about a home DSL modem (which
    usually doesn't have an SNMP agent in it).
  - http://sourceforge.net/projects/mrtgaddons4dsl/

* tp-x40-tools
  - ThinkPad X40 Tools.  This is the least-complete of my SourceForge
    projects.
  - http://sourceforge.net/projects/tp-x40-tools/


# Differences from SourceForge #

Each of the subdirectories in this repository contains the contents of
one SourceForge project.  *However*:  the structure of some of them
differs:

* All Projects:

  I use Subversion on SourceForge (and at home) for all of my
  projects.  As is normal for a SVN repository, the top-level has the
 `branch`, `tag` and `trunk` subdirectories.  The contents of `trunk`
  on SourceForge are what you'll find here on GitHub.

* mrtgAddons4Dsl
  - `trunk` on SourceForge is `mrtgAddons4Dsl/mrtgAddons` here.
  - `trunk/cfgfiles/mrtg` on SourceForge is
    `mrtgAddons4Dsl/mrtgAddons/cfgfiles` here.
  - `trunk/cfgfiles/scripts` on SourceForge is
    `mrtgAddons4Dsl/mrtgAddons/etc` here.
  - Why is it like this?

    I have a centralized `perl` section in my personal SVN repository
    where I keep all of my standalone scripts.  Since my MRTG addons
    are just a perl-script + a config-file, I had them just tossed in
    my `perl` section, in a subdirectory called (drum-roll)
    `mrtgAddons`.

* tp-x40-tools
  - `perl/trunk` on SourceForge is `tp-x40-tools/perl` here.
  - `xkb/trunk` on SourceForge is `tp-x40-tools/xkb` here.
  - `sh.scripts/trunk` on SourceForge is `tp-x40-tools/sh.scripts` here.
  - Bonus!  The following subdirectores (and their contents) are only
    here on GitHub:
    + `tp-x40-tools/sh.scripts/laptop/acpi`
    + `tp-x40-tools/sh.scripts/laptop/powersave-modules-cfgs`
    + `tp-x40-tools/sh.scripts/laptop/pm`<br/>
      This one might be Ubuntu-centric.

 

Now, why all of these differences?

 

Explaining my workflow should help make things clear.  I keep a
Subversion repository on my Linux machine at home.  This SVN
repository is organized by major-project, or in the case of standalone
scripts and files not part of a major-project, by language.  (That
should explain the `perl`, `sh.scripts` and `xkb` subdirectories.)

Obviously, I program against this personal SVN repository.  When
working on code for one of my SourceForge projects, I make lots of
local commits.  (Commit Early and Often!)  Then, when it's time to
"release" a bundle of changes to the project's SourceForge repository,
I use a combination of `cp` commands, patches, and exported
commit-logs.  For major-projects, I can just create a bulk-patch,
since I use the same directory-structure on SourceForge that I'm using
at home.

For the smaller projects — or ones in flux — I'll organize the files
differently on SourceForge.  I usually just copy the changed files
from their working-directory to my SourceForge staging area, then
export the files' commit-logs into a single file, which I'll edit and
use when I commit to SourceForge.

 

The code *here* on GitHub, however, came **directly** from my personal
Subversion repository (using `git svn`).  So it reflects, *exactly*,
my coding process.
