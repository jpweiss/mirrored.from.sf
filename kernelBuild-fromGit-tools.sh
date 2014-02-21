#!/bin/bash
#
# Copyright (C) 2014 by John P. Weiss
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
############


############
#
# Configuration Variables
#
############


KBUILD_BASEDIR=${KBUILD_BASEDIR:-~/src/tpX40.kernelBuilds}


############
#
# Includes & Other Global Variables
#
############


kernelGitUrl='git://git.kernel.org/pub/scm/linux/kernel/git'
kernelGitUrl="$kernelGitUrl/stable/linux-stable.git"
export kernelGitUrl


buildBranchBase="build-v"


############
#
# Functions
#
############


# # This would work, but is space-inefficient in the long-term.
# #
# get_kernelFromGit_justOneBranchOnly() {
#     local theSingleBranch="$1"
#     shift
#
#     git clone --verbose --progress \
#         --single-branch --branch $theSingleBranch \
#         ${kernelGitUrl} linux-stable.git
# }
# # Example:
# #get_kernelFromGit_justOneBranchOnly linux-3.13.y


utl_kBfG__getBranchNames() {
    local brType="$1"
    shift
    local how="$1"
    shift

    local dflOpts="--no-color -q"
    if [ "$how" = "--raw" ]; then
        git branch $brType $dflOpts | grep 'origin/linux' | sort -V
        return $?
    fi
    # else:

    if [ "$how" = "--current" ]; then
        git branch $dflOpts | grep '^\*' | awk '{ print $2 }'
        return $?
    fi
    # else:

    git branch $brType $dflOpts | grep 'origin/linux' | \
        sed -e 's|^.*origin/||' | sort -V
}


utl_kBfG__notaBuildBranch() {
    local currentBranch="$1"

    if [ -z "$currentBranch" ]; then
        currentBranch=$(utl_kBfG__getBranchNames '' --current)
    fi

    if echo $currentBranch | grep -q $buildBranchBase; then
        return 1
    fi
    #else

    echo ">>"
    echo ">> Not on a build branch!"
    return 0
}


utl_kBfG__nukeCurrentBranch() {
    git reset --hard HEAD || return $?
    git clean -f -d || return $?
}


get_kernelFromGit_startingFromBranch() {
    local theMinBranch="${1:-linux-3.}"
    shift

    local gitStat
    local logFile=${KBUILD_BASEDIR}/kernel-retrieval.log

    local wrkDir=${KBUILD_BASEDIR}/linux-stable.git
    if [[ ! -d $wrkDir ]]; then
        git clone --verbose --progress --depth 1 --no-single-branch \
            ${kernelGitUrl} ${wrkDir} |& tee $logFile
        gitStat=$?

        if [ $gitStat -ne 0 ]; then
            {
                echo "#!!!"
                echo "#!!!"
                echo "#!!! 'git clone' of kernel-repo failed!"
                echo "#!!! Cannot continue."
                echo "#!!!"
                echo "#!!!"
            } |& tee $logFile
            return $?
        fi
    fi

    pd $wrkDir

    local rmBrFile=${KBUILD_BASEDIR}/tmp.branches.list
    {
        echo "#"
        echo "# Uncomment any branches you want to remove."
        echo "#"
        echo "# Comment out any branches you want to keep."
        echo "#" >>$rmBrFile
        echo "# [Some branches have been commented out for you already.]"
        echo "#"
        echo "#"
        echo "# Save & Quit to continue."
        echo "#"
        echo "#"

        utl_kBfG__getBranchNames -r --raw | \
            sed -e "/${theMinBranch//./\\.}/,\$s/^/\#/"
    } >$rmBrFile
    ${EDITOR:-vim} $rmBrFile

    local finalRetStat=0
    {
        # Drop all of the tags
        #
        git tag -d $(git tag -l) |& tee -a $logFile
        gitStat=$?
        if [ $gitStat -ne 0 ]; then
            echo "#!!!"
            echo "#!!! Deletion of git tags failed!"
            echo "#!!! Manual intervention required."
            echo "#!!!"
            finalRetStat=1
        fi

        # Remove the unnecessary remote branches
        #
        local b tpat
        for b in $(grep -v '^#' $rmBrFile); do
            git branch -D -r "$b" |& tee -a $logFile
            gitStat=$?
            if [ $gitStat -ne 0 ]; then
                echo "#!!!"
                echo "#!!! Deletion of branch \"$b\" failed!"
                echo "#!!! Manual intervention required."
                echo "#!!!"
                finalRetStat=1
            fi
        done

        if [ $finalRetStat -eq 0 ]; then
            git remote set-branches origin $(utl_kBfG__getBranchNames -r)
        else
            echo "#!!!"
            echo "#!!! Could not setup remote branches due to earlier errors."
            echo "#!!!"
        fi
    } |& tee $logFile

    # Don't log this, or we won't see the progress message [if any].
    #
    git gc --prune=all

    popd

    return $finalRetStat
}


update_kernelFromGit() {
    local resetMaster runGC
    while [ -n "$1" ]; do
        case "$1" in
            --reset)
                resetMaster=y
                ;;
            --gc)
                runGC=y
                ;;
            *)
                echo "usage:  update_kernelFromGit [--reset] [--gc]"
                return 1
                ;;
        esac
        shift
    done


    local logFile=${KBUILD_BASEDIR}/update-kernel.log

    {
        local curBranch="$(utl_kBfG__getBranchNames '' --current)"
        if [ "$curBranch" != "master" ]; then
            echo ">> Hard-resetting the current branch, \"$curBranch\","
            echo ">> and changing to 'master'..."
            utl_kBfG__nukeCurrentBranch
            git checkout master
            resetMaster=y
        fi
        if [ -n "$resetMaster" ]; then
            echo ">>"
            echo ">> Hard-resetting..."
            utl_kBfG__nukeCurrentBranch
        fi

        if [ -n "$runGC" ]; then
            echo ">>"
            echo ">> Cleaning up the repository..."
            git gc --prune
        fi

        git pull --verbose --progress --depth=1 --no-tags -- origin
    } |& tee $logFile
}


kernel_prep_buildBranch() {
    local trackingBranch="${1#origin/}"
    shift
    local initialKCfg="${1}"
    shift

    # Verify Args
    if [ -z "$trackingBranch" -o -z "$initialKCfg" ] \
        || [[ ! -r $initialKCfg ]]
    then
        if [ -n "$initialKCfg" ] && [[ ! -r $initialKCfg ]]; then
            echo "No such kernel config file:  \"$initialKCfg\""
        else
            echo "Missing arg(s)."
        fi
        echo ""

        echo -n "usage:  kernel_prep_buildBranch <remoteBranchName> "
        echo "<kernelCfgFile>"
        return 1
    fi

    local buildBranch=${buildBranchBase}${trackingBranch#linux-}
    local logFile=${KBUILD_BASEDIR}/${buildBranch}.log

    {
        local hasTrackingBranch
        if utl_kBfG__getBranchNames -r | grep -q "^$trackingBranch\$"; then
            hasTrackingBranch=y
        fi

        local currentBranch=$(utl_kBfG__getBranchNames '' --current)

        # Make sure it exists, or abort.
        if [ -n "$hasTrackingBranch" ]; then
            if [ "$currentBranch" = "$trackingBranch" ]; then
                echo ">>"
                echo -n ">> Already checked out in branch:  "
                echo "\"$trackingBranch\".  Good."
                echo ">>"
            elif [ "$currentBranch" != "$buildBranch" ]; then
                git checkout $trackingBranch || return $?
            fi
        else
            echo ">>"
            echo ">> No such remote branch:  \"$trackingBranch\"."
            echo ">>"
            echo ">> Cowardly refusing to continue."
            return 1
        fi

        if [ "$currentBranch" != "$buildBranch" ]; then
            local bbCheckoutOpt='-b'
            if git branch --no-color -q | grep -q "$buildBranch\$"; then
                bbCheckoutOpt=''
            fi

            git checkout $bbCheckoutOpt $buildBranch || return $?
        fi
        echo ">>"
        echo ">> Build Branch [\"$buildBranch\"] checked out."
        echo ">>"

        cp -vi --backup=t $initialKCfg .config || return $?
        echo ">>"
        echo ">> Copied config file.  Listing new config options:"
        echo ">>"

        make listnewconfig
        echo ">>"
        echo ">> Run 'make xconfig' and use this list to tweak appropriately."
        echo ">>"
    } |& tee -a $logFile

    echo ">> Output appended to log file:  \"$logFile\"."
}


kernel_make_xconfig_qt4() {
    local runsudo=''
    if [ "$1" = "--sudo" ]; then
        runsudo=sudo
        shift
    fi

    QTDIR=/usr/share/qt4
    export QTDIR
    $runsudo make "$@" xconfig
    unset QTDIR
}


kernel_stash_config() {
    local kver=$(make kernelversion)
    cp -vi --backup=t .config $KBUILD_BASEDIR/tpx40-${kver}.config
}


kernel_do_build() {
    local currentBranch=$(utl_kBfG__getBranchNames '' --current)
    local logFile=${KBUILD_BASEDIR}/${currentBranch}.log

    if utl_kBfG__notaBuildBranch $currentBranch; then
        echo ">> Refusing to proceed."
        echo ">>"
        return 10
    fi

    local retStat
    {
        echo ">>"
        echo ">> Starting Build of \"currentBranch\""
        echo ">>"
        echo ">>"

        mv .git Tmp-Disabled-dot.git || return $?
        make "$@" deb-pkg
        retStat=$?

        mv Tmp-Disabled-dot.git .git
        let retStat+=$?
    } |& tee -a $logFile

    echo ">> Output appended to log file:  \"$logFile\"."
    return $retStat
}


kernel_nuke_buildBranch() {
    local buildBranch=$(utl_kBfG__getBranchNames '' --current)
    if utl_kBfG__notaBuildBranch $buildBranch; then
        echo ">> Can't do anything here."
        echo ">>"
        return 1
    fi

    local logFile=${KBUILD_BASEDIR}/cleanup-${buildBranch}.log
    local retStat
    {
        echo ">> Cleaning build..."
        echo ">> "
        make mrproper || return $?

        echo ">> Hard-resetting build branch..."
        echo ">>"
        utl_kBfG__nukeCurrentBranch || return $?

        echo ">> Returning to \"master\" branch..."
        echo ">> "
        git checkout master || return $?

        echo ">> Deleting the build branch..."
        echo ">> "
        git branch -D $buildBranch
        retStat=$?
    } |& tee -a $logFile

    return $retStat
}


kernel_tools_help() {
    cat <<EOF | less
    Functions:
    ----------

    get_kernelFromGit_startingFromBranch [<theMinBranch>]
            Clone the entire stable kernel's repository from \$kernelGitUrl
            into \$KBUILD_BASEDIR, then remove old branches and all tags.
            After that, prune and garbage-collect the repository.

            '<theMinBranch>' is a regexp matching [part of] the name of the
            first branch to keep.  Defaults to "linux-3.".
            (You'll typically use something like "linux-3.8".)

            Prior to removing anything, a list of branches will open in 'vim'
            [or your current \$EDITOR] with instructions for how to tweak the
            list of branches to remove.

    update_kernelFromGit
            Resets everything in the current working directory and performs a
            series of 'git pull's on all of the remote branches.

            DON'T perform a 'git pull' directly on the repository cloned by
            'get_kernelFromGit_startingFromBranch'.  You'll end up grabbing
            all of the pruned branches again.

    kernel_prep_buildBranch
            Run w/o args for usage.
            Sets up the current directory for building the kernel.  Creates &
            checks out branches as needed.

            The next step after this might be a 'make xconfig' of some form
            followed by a 'kernel_stash_config'.

    kernel_make_xconfig_qt4 [--sudo] [V={0|1|2}]
            Do a 'make xconfig', but forcing use of Qt4.  Versions of the
            kernel past 3.12.* seem to have problems with Qt3.

    kernel_stash_config
            Save a copy of the current '.config' file to the \$KBUILD_BASEDIR,
            using a filename containing the Makefile's version.

    kernel_do_build [V={0|1|2}]
            Builds the kernel "deb-pkg".  You must be in the working dir and
            on a "build-branch" or this won't work.

    kernel_nuke_buildBranch
            Does the final step:  cleans up everything, return to the 'master'
            branch, and delete the "build-branch".


    Aliases:
    --------

    None at present.


    Envvars:
    --------

    \$kernelGitUrl - The URL of the Linux kernel's git repository.
    \$KBUILD_BASEDIR - The path to do all of the work in.
                       You can set this variable.
EOF
}


############
#
# Main
#
############


case "$0" in
    *bash)
        echo "Run \"kernel_tools_help\" for a list of the tools created by"
        echo "this file."

        ;;
    *)
        # Was run as a script.
        echo "# $0: You must source this script."
        ;;
esac


#####################
# Local Variables:
# mode: Shell-script
# eval: (sh-set-shell "bash" nil nil)
# End:
