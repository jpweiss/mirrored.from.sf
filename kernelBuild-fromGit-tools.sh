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


kernelGitUrl='git://git.kernel.org/pub/scm/linux/kernel/git'
kernelGitUrl="$kernelGitUrl/stable/linux-stable.git"
export kernelGitUrl


############
#
# Includes & Other Global Variables
#
############


#. some.include.sh

GREP=grep
SED=sed
AWK=awk
LS=ls


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


get_kernelFromGit_startingFromBranch() {
    local theMinBranch="${1:-linux-3.}"
    shift

    local gitStat
    local baseDir=~/src/tpX40.kernelBuilds
    local logFile=${baseDir}/kernel-retrieval.log

    local wrkDir=${baseDir}/linux-stable.git
    if [[ ! -d $wrkDir ]]; then
        git clone --verbose --progress --depth 1 --no-single-branch \
            ${kernelGitUrl} ${wrkDir} |& tee $logFile
        gitStat=$?

        if [ $gitStat -ne 0 ]; then
            (   echo "#!!!"
                echo "#!!!"
                echo "#!!! 'git clone' of kernel-repo failed!"
                echo "#!!! Cannot continue."
                echo "#!!!"
                echo "#!!!"
                ) |& tee $logFile
            return $?
        fi
    fi

    pd $wrkDir

    local rmBrFile=${baseDir}/tmp.branches.list
    echo "#" >$rmBrFile

    echo "# Uncomment any branches you want to remove." >>$rmBrFile
    echo "#" >>$rmBrFile
    echo "# Comment out any branches you want to keep." >>$rmBrFile
    echo "#" >>$rmBrFile
    echo "# [Some branches have been commented out for you already.]" \
        >>$rmBrFile
    echo "#" >>$rmBrFile
    echo "#" >>$rmBrFile
    echo "# Save & Quit to continue." \
        >>$rmBrFile
    echo "#" >>$rmBrFile
    echo "#" >>$rmBrFile

    git branch -r | grep 'origin/linux' | sort -V | \
        sed -e "/${theMinBranch//./\\.}/,\$s/^/\#/" \
        >>$rmBrFile
    ${EDITOR:-vim} $rmBrFile

    local finalRetStat=0

    # Drop all of the tags
    #
    git tag -d $(git tag -l) |& tee -a $logFile
    gitStat=$?
    if [ $gitStat -ne 0 ]; then
        (   echo "#!!!"
            echo "#!!! Deletion of git tags failed!"
            echo "#!!! Manual intervention required."
            echo "#!!!"
        ) |& tee $logFile
        finalRetStat=1
    fi

    # Remove the unnecessary remote branches
    #
    local b tpat
    for b in $(grep -v '^#' $rmBrFile); do
        git branch -D -r "$b" |& tee -a $logFile
        gitStat=$?
        if [ $gitStat -ne 0 ]; then
            (   echo "#!!!"
                echo "#!!! Deletion of branch \"$b\" failed!"
                echo "#!!! Manual intervention required."
                echo "#!!!"
                ) |& tee $logFile
            finalRetStat=1
        fi
    done

    git gc --prune=all

    popd

    return $finalRetStat
}


update_kernelFromGit() {
    local curBranch=$(git branch --no-color -q | awk '{ print $2 }')
    if [ "$curBranch" != "master" ]; then
        echo ">> Hard-resetting the current branch, \"$curBranch\","
        echo ">> and changing to 'master'..."
        git reset --hard
        git checkout master
    fi
    echo ">> Hard-resetting..."
    git reset --hard

    local r b
    for r in $(git branch --no-color -r -q | grep -v -- '->'); do
        b="refs/heads/${r#origin/}"
        git pull --verbose --progress --no-tags -- origin $b
    done
}


#####################
# Local Variables:
# mode: Shell-script
# eval: (sh-set-shell "bash" nil nil)
# End:
