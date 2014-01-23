#!/bin/bash
#
# Copyright (C) 2003-2011 by John P. Weiss
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


MYVERSION='2_0_1'

BIN_DIR=${PWD}


############
#
# Includes & Other Global Variables
#
############


#DEVEL="" # Set this var in the environment to run this script in development
          # mode.

CONFIG_FILE=''
VERBOSE_CRON=''
AR_DIR=''
AR_PREFIX=''
WRK_DIR=''
INCR_CRON_SH='./cron/pkgBackup.incr'
INCR_CRON_INSTALLPATH="/etc/cron.weekly"
FULL_CRON_SH='./cron/pkgBackup.full'
FULL_CRON_INSTALLPATH="/etc/cron.monthly"
DO_FULL_NOW=''

DEFL_AR_DIR=''
DEFL_AR_PREFIX=''
DEFL_WRK_DIR=''
BAD_PUNCT=$'[]{}|<>!@$%^&*?()=~"`;#\'\\'
# ' # Fixes Emacs font-lock
CTRLCHAR1=$'\001\002\003\004\005\006\a\b\016\017'
CTRLCHAR2=$'\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036'
CTRLCHARS="${CTRLCHAR1}${CTRLCHAR1}"
WS=$' \t\v\f\r'
INCR_CRON_EXISTS=''
FULL_CRON_EXISTS=''
CHANGED_FILES=''

TARBALL_EXCLUDES='*/CVS */.svn TAGS */research *.tar.* '
TARBALL_EXCLUDES="${TARBALL_EXCLUDES}"'*.t[bg]z *~ */test-results'


############
#
# Functions
#
############


usage() {
    echo "$0 - Semi-user-friendly setup of rpmBackup/debBackup."
    echo ""
    echo "You must run this script from the directory where the"
    echo "backup scripts reside.  \"$0\" will ask you some"
    echo "questions to assist customizing the config file and automated"
    echo "cron-job scripts to your site."
    echo ""
    echo "You may type Ctrl-C at any time to abort the changes."
    echo ""
    echo "Options:"
    echo ""
    echo "--conf <configfile>"
    echo "    Specify an alternate configuration file.  By default, \"$0\""
    echo "    uses the default config file, \"pkgBackup.conf\"."
    echo ""

    if [ -z "${DEVEL}" ]; then
        exit 1
    fi

    echo "Devel Options:"
    echo ""
    echo "--make_man"
    echo "    (Re)Generate all of the man pages, using \"pod2man\"."
    echo ""
    echo "--tarball"
    echo "    Collects everything into a tarball for distribution."
    echo ""
    echo "--all"
    echo "    Same as a \"--make_man\" followed by the normal installation."
    echo ""
    exit 1
}


set_traps() {
    trap "$1" 1 2 3 4 5 6 7 8 10 11 12 15 19
}


terminate() {
    set_traps '-'
    echo ""
    not_changed_msg="No changes made."
    for f in ${CHANGED_FILES}; do
        not_changed_msg=''
        of="${f}.orig"
        if [ -e ${of} ]; then
            echo "Restoring original version of \"${f}\"."
            mv ${of} ${f}
        fi
    done
    echo "Terminated at user's request.  ${not_changed_msg}"
    exit 0
}


do_pod2man() {
    if [ ! -d ./man.devel ]; then
        mkdir man.devel
    fi
    for pm in *.pm; do
        pod2man --section=3pm ${pm} | gzip -c > man.devel/${pm%.pm}.3pm.gz
    done

    if [ -e ./pkgBackup.8.gz ]; then
        return
    fi
    pod2man --section=8 pkgBackup.pl | gzip -c > pkgBackup.8.gz
}


create_tarball() {
    mydir=${PWD##*/}
    cd ..
    # To protect any unescaped wildcard chars.
    exclusions="--exclude='${TARBALL_EXCLUDES// /' --exclude='}'"
    # To get tar to recognize the --exclude options.
    cmd="tar -zcv --dereference "
    cmd="${cmd} -f pkgBackup-${MYVERSION}.tar.gz ${mydir} ${exclusions}"
    eval ${cmd}
    mv pkgBackup-${MYVERSION}.tar.gz ${mydir}
    cd ${mydir}
}


read_cfg_defaults() {
    while read varnm sep val; do
        # Can't use '-z' op when the string contains a '=' char
        if [ "x${sep}" != "x=" ]; then
            continue
        fi
        case $varnm in
            Archive_Prefix)
                if [ -n "${val}" ]; then
                    DEFL_AR_PREFIX="${val}"
                fi
                ;;
            Archive_Destination_Dir)
                if [ -n "${val}" ]; then
                    DEFL_AR_DIR="${val}"
                fi
                ;;
            Working_Dir)
                if [ -n "${val}" ]; then
                    DEFL_WRK_DIR="${val}"
                fi
                ;;
        esac
    done
    # Possible default values for the archive prefix.
    if [ -n "${DEFL_AR_PREFIX}" -a \
         "${DEFL_AR_PREFIX}" != "localhostname-backup" ]; then
        AR_PREFIX="${DEFL_AR_PREFIX}"
    else
        AR_PREFIX=`hostname`-backup
    fi
    # Check existence of work directory if set.
    if [ -n "${DEFL_WRK_DIR}" ]; then
        if [ ! -d ${DEFL_WRK_DIR} ]; then
            echo "\"./pkgBackup.conf\" misconfigured."
            echo -n "Config variable 'Working_Dir' set to nonexistent "
            echo "directory: \"${DEFL_WRK_DIR}\"."
            echo "Will reset this to a sane default."
            DEFL_WRK_DIR=''
        fi
    fi
    WRK_DIR="${DEFL_WRK_DIR}"
    # Set the default value for the archive dir.
    if [ -n "${DEFL_AR_DIR}" ]; then
        if [ -d ${DEFL_AR_DIR} ]; then
            AR_DIR="${DEFL_AR_DIR}"
        fi
    fi
}


is_emptyStr() {
    [ "$1" = '""' -o "$1" = "''" ] && return 0
    return 1
}


is_valid_fname() {
    fname="$1"
    shift
    include_path="$1"
    shift
    empty_allowed="$1"
    shift

    # Special Cases:
    # Accept Default
    if [ -z "${fname}" ]; then
        return 0
    fi
    # Empty-String Escape.
    if [ -n "${empty_allowed}" ]; then
        if is_emptyStr "${fname}"; then
            return 0
        fi
    fi

    # Not the special case empty-string escape; do usual checks.
    oldIFS="${IFS}"
    IFS="${WS}${CTRLCHARS}${BAD_PUNCT}"
    if [ -z "${include_path}" ]; then
        IFS="${IFS}/"
    fi
    set -- ${fname}
    IFS="${oldIFS}"
    # Set will return ${fname} exactly if there were only valid chars in it.
    if [ $# -eq 1 ]; then
        return 0
    fi
    echo "ERROR:  At least $# invalid characters in input path/filename."
    echo "  Invalid input:  ${fname}"
    echo "    Valid parts:  $@"
    echo "  Please re-input, using only alphanumeric characters or punctuation"
    echo "  marks: \".,:_-+\"."
    return 1
}


read_fname() {
    rf_varnm="$1"
    shift
    prompt="$1"
    shift
    include_path="$1"
    shift
    empty_allowed="$1"
    shift

    read -e -p "${prompt}" rval
    until is_valid_fname "${rval}" "${include_path}" "${empty_allowed}"; do
        read -e -p "${prompt}" rval
    done

    eval "export ${rf_varnm}=\"${rval}\""
}


ask_yn() {
    prompt="$1"
    shift

    while [ 1 -eq 1 ]; do
        read -n 1 -p "{'y'|'n'}  ${prompt}" flg
        case $flg in
            [Yy])
                echo ""
                return 1
                ;;
            [Nn])
                echo ""
                return 0
                ;;
        esac
        echo "    Please enter 'y' or 'n'."
    done
}


check_directoryExists() {
    dir="$1"
    shift
    empty_allowed="$1"
    shift

    if [ -z "$dir" ]; then
        if [ -n "${empty_allowed}" ]; then
            return 0
        fi
        # else  -n "$dir"
    elif [ -d ${dir} ]; then
        return 0
    fi

    # else
    echo ""
    echo "ERROR:  Directory \"${dir}\" does not exist."
    return 1
}


core_user_input_dir() {
    cuid_varnm="$1"
    shift
    prompt_mesg="$1"
    shift
    default="$1"
    shift
    empty_allowed="$1"
    shift

    # Get the input and postprocess.
    local dir_in
    prompt="${prompt_mesg} [${default}]: "
    read_fname dir_in "${prompt}" 'y' "${empty_allowed}"
    if [ -z "${dir_in}" ]; then
        dir_in="${default}"
    fi
    # Strip quotes if empties are permitted.
    if [ -n "${empty_allowed}" -a \
            \( "${dir_in}" = "''" -o "${dir_in}" = '""' \) \
        ]; then
        dir_in=''
    fi

    # Validate the input.
    if check_directoryExists "${dir_in}" "${empty_allowed}"; then
        eval "export ${cuid_varnm}=\"${dir_in}\""
        return 0
    elif [ -n "${dir_in}" ]; then
        ask_yn "Do you wish to create \"${dir_in}\"? "
        response=$?
        if [ $response -eq 1 ]; then
            mkdir -vp "${dir_in}"
            if [ $? -eq 0 ]; then
                eval "export ${cuid_varnm}=\"${dir_in}\""
                return 0
            fi
        fi
    fi
    # else: "${dir_in}" doesn't exist and user chose not to create
    #    OR ${dir_in} == '', which is invalid for this call.

    echo "Use the name of an existing directory, or quit this script and"
    echo "create your desired target directory."
    echo ""
    eval "export ${cuid_varnm}=''"
    return 1
}


get_user_input_dir() {
    until core_user_input_dir "$@"; do
        noop=0
    done
}


get_user_opts() {
    uses_customconf="$1"
    shift

    local u_in

    echo "You'll now enter in some configuration values.  After each question,"
    echo "enter your answer at the prompt, followed by <Return>."
    echo "The prompt will end with \"[...]\" surrounding the default value, if"
    echo "there is one.  To use the default, hit <Return> without entering"
    echo "anything."
    echo ""

    echo ""
    echo "First, you need to choose an archive name prefix.  This is a"
    echo "filename prefix (without any directory name) that will be used for"
    echo "the backup archive file (tarball, cpio archive, etc....)."
    echo "\"pkgBackup\" will construct archive names using this prefix and"
    echo "various, appropriate suffixes."
    echo ""
    read_fname u_in "Enter the backup archive prefix [${AR_PREFIX}]: "
    if [ -n "${u_in}" ]; then
        AR_PREFIX="${u_in}"
    fi

    echo ""
    echo "Where do you want to store your backups?"
    echo "Enter the name of a directory where \"pkgBackup\" should create"
    echo "backup archives (tarballs, etc....) .  It should be on a disk with"
    echo "sufficient space (so that automated backups do not fail) that is"
    echo "always mounted but not automatically cleaned (such as \"/tmp\" and"
    echo "parts of \"/var\")."
    echo ""
    get_user_input_dir u_in \
        "Enter the backup storage directory" "${AR_DIR}" ''
    AR_DIR="${u_in}"

    echo ""
    echo "Enter the name of a directory where \"pkgBackup\" will keep its"
    echo "working files."
    echo "The working files are used from run to run, so \"pkgBackup\" should"
    echo "have a working directory on a disk that isn't automatically cleaned"
    echo "(such as \"/tmp\" and parts of \"/var\").  However, the contents of"
    echo "the working directory have a limited size (seldom more than 1-4 MB"
    echo "in toto).  So, the working directory can be on a drive with limited"
    echo "space or under disk quota control."
    echo ""
    echo "If you enter the empty string, \"pkgBackup\" will use the backup"
    echo "storage directory as the working directory."
    echo "(If you want to specify the empty string as an input value, you can"
    echo "enter a literal pair of '' or \"\" quotes.)"
    echo ""
    echo "It is safe to hit <Return> and use the default for this."
    echo ""
    get_user_input_dir u_in "Enter working directory" "${WRK_DIR}" 'y'
    WRK_DIR="${u_in}"

    # Ask for a configfile if not the default.
    if [ -n "${uses_customconf}" ]; then
        echo ""
        echo "You specified a custom configuration file, \"${CONFIG_FILE}\","
        echo "when running this script.  In case you want to use a custom copy"
        echo "of this file in some other location, you can do that now."
        echo ""
        echo "It is safe to hit <Return> and use the default for this."
        echo ""
        read_fname u_in \
            "Enter custom configuration file [${CONFIG_FILE}]: " 'y'
        if [ -n "${u_in}" ]; then
            CONFIG_FILE="${u_in}"
        fi
    fi

    # Check for previously-installed cronjob runner scripts.
    echo ""
    echo "You can have \"cron\" auto-execute runner-scripts to perform full"
    echo "and incremental backups at regular intervals.  These runner-scripts"
    echo "are always created for you, but will only be installed if you wish."
    echo ""
    if [ -e ${INCR_CRON_INSTALLPATH}/`basename ${INCR_CRON_SH}` ]; then
        INCR_CRON_SH="${INCR_CRON_INSTALLPATH}/`basename ${INCR_CRON_SH}`"
        INCR_CRON_EXISTS='y'
    else
        ask_yn "Install the incremental backup runner-script? "
        response=$?
        if [ $response -eq 0 ]; then
            INCR_CRON_INSTALLPATH=''
        fi
    fi
    if [ -e ${FULL_CRON_INSTALLPATH}/`basename ${FULL_CRON_SH}` ]; then
        FULL_CRON_SH="${FULL_CRON_INSTALLPATH}/`basename ${FULL_CRON_SH}`"
        FULL_CRON_EXISTS='y'
    else
        ask_yn "Install the full backup runner-script? "
        response=$?
        if [ $response -eq 0 ]; then
            FULL_CRON_INSTALLPATH=''
        fi
    fi

    # Ask what the user wants to do about a first full backup.
    echo ""
    echo "One Last Question:"
    echo ""
    echo "The very first backup you perform with \"pkgBackup\" must be a full"
    echo "one.  Incremental backups (like those auto-run by \"cron\") will"
    echo "flat-out fail otherwise."
    echo "You can perform this initial full backup now, as part of the"
    echo "installation, or you can do it yourself later."
    echo ""
    ask_yn "Perform full backup as the final installation step? "
    response=$?
    if [ $response -eq 1 ]; then
        DO_FULL_NOW='y'
    fi
}


cron_runner_mesg() {
    already_installed="$1"
    shift
    instPath="$1"
    shift
    runner="$1"
    shift
    what="$1"
    shift

    echo "  ${what} Backup Cron Job Script"
    if [ -n "${already_installed}" ];then
        echo "    Editing existing script: \"${runner}\""
    else
        echo "    Editing script: \"${runner}\""
        if [ -z "${instPath}" ]; then
            return
        fi
        echo "    and installing to \"${instPath}\"."
    fi
}


show_chosen_opts() {
    case "${CONFIG_FILE}" in
        /*)
            cfgfile_msg="${CONFIG_FILE}"
            ;;
        *)
            cfgfile_msg="${BIN_DIR}/`basename ${CONFIG_FILE}`"
            ;;
    esac
    wrkdir_msg="\"${WRK_DIR}\""
    if [ -z "${WRK_DIR}" ]; then
        wrkdir_msg=' {same as Backup Storage Dir}'
    fi

    echo "You have chosen the following configuration options:"
    echo "  Script Path:              \"${BIN_DIR}\""
    echo "  Configuration File:       \"${cfgfile_msg}\""
    echo "  Backup Storage Directory: \"${AR_DIR}\""
    echo "  Script Working Directory: ${wrkdir_msg}"
    echo "  Backup Archive-Prefix:    \"${AR_PREFIX}\""
    echo ""
    cron_runner_mesg "${FULL_CRON_EXISTS}" \
        "${FULL_CRON_INSTALLPATH}" "${FULL_CRON_SH}"  "Full"
    cron_runner_mesg "${INCR_CRON_EXISTS}" \
        "${INCR_CRON_INSTALLPATH}" "${INCR_CRON_SH}"  "Incremental"

    if [ -n "${DO_FULL_NOW}" ]; then
        echo ""
        echo "  Performing full backup at the end of the installation."
    fi

    echo ""
    echo "This is your last chance to quit before the Configuration File and"
    echo "cron-job runner scripts are modified."
    ask_yn "Do you wish to continue? "
    response=$?
    if [ $response -ne 1 ]; then
        terminate
    fi
}


edit_config() {
    conffile="$1"
    shift

    changer=""

    if [ "${AR_PREFIX}" != "${DEFL_AR_PREFIX}" ]; then
        changer="${changer} s|^(Archive_Prefix\s*=\s*).+\$|\$1${AR_PREFIX}|;"
    fi
    if [ "${AR_DIR}" != "${DEFL_AR_DIR}" ]; then
        changer="${changer} s|^(Archive_Destination_Dir\s*=\s*).+\$"
        changer="${changer}|\$1${AR_DIR}|;"
    fi
    if [ "${WRK_DIR}" != "${DEFL_WRK_DIR}" ]; then
        changer="${changer} s|^(Working_Dir\s*=\s*).+\$|\$1${WRK_DIR}|;"
    fi

    # Nothing to change?  Then stop.
    if [ -z "${changer}" ]; then
        echo "# No changes required for \"${conffile}\"."
        return 0
    fi

    perl -p -i.orig -e "${changer}" ${conffile}
    status=$?
    if [ ${status} -eq 0 ]; then
        CHANGED_FILES="${CHANGED_FILES} ${conffile}"
    fi
    return $status
}


edit_runner_sh() {
    runner_sh="$1"
    shift
    custom_conffile="$1"
    shift

    changer="s|^(BIN_PATH=).+\$|\$1${BIN_DIR}|;"
    changer="${changer} s|^(CFGFILE=).+\$|\$1"
    if [ -z "${custom_conffile}" ]; then
        changer="${changer}\\044{BIN_PATH}/${CONFIG_FILE}|;"
    else
        changer="${changer}${CONFIG_FILE}|;"
    fi
    perl -p -i.orig -e "${changer}" ${runner_sh}
    status=$?
    if [ ${status} -eq 0 ]; then
        CHANGED_FILES="${CHANGED_FILES} ${runner_sh}"
    fi
    return $status
}


checked_copy() {
    src="$1"
    shift
    targ="$1"
    shift

    cp -av --backup ${src} ${targ}
    status=$?
    if [ ${status} -eq 0 ]; then
        echo "# Install of \"${src}\" failed.  To retry, "
        echo "# run the following command:"
        echo "#     cp -av --backup ${src} ${targ}"
        echo "# Continuing..."
    fi
    return $status
}


############
#
# Main
#
############


# Start by checking the $PWD and required installation files.
if [ ! -x ./pkgBackup.pl -o \
     ! -d ./cron -o \
     ! -f ./pkgBackup.conf \
    ]; then
    echo "You must run this script from the directory where the"
    echo "\"pkgBackup.pl\" script and the default \"pkgBackup.conf\""
    echo "files reside."
    echo ""
    usage
fi
if [ ! -x ${INCR_CRON_SH} -o \
     ! -x ${FULL_CRON_SH} \
    ]; then
    echo "The files in \"./cron/\" have been damaged since you untarred"
    echo "the \"pkgBackup\" files.  Cannot continue."
    echo ""
    usage
fi

set_traps terminate

# Read the cmdline options.
myconf="./pkgBackup.conf"
customconf=''
install='y'
makeMan=''
tarball=''
if [ -n "$1" ]; then
    install=''
fi
while [ -n "$1" ]; do
    case $1 in
        --help|-h)
            usage
            ;;
        --devel*|--expert|-d)
            DEVEL="y"
            ;;
        --make_man|--makeMan)
            makeMan="y"
            ;;
        --tarball)
            tarball="y"
            ;;
        -c|--conf*)
            shift
            myconf="$1"
            install='y'
            customconf='y'
            ;;
        --all)
            makeMan="y"
            install='y'
            ;;
    esac
    shift
done


if [ -n "${DEVEL}" ]; then
    if [ -n "${tarball}" ]; then
        create_tarball
    fi

    if [ -n "${makeMan}" ]; then
        do_pod2man
    fi
fi

if [ -z "${install}" ]; then
    exit 0
fi

read_cfg_defaults <"${myconf}"
CONFIG_FILE="${myconf}"
get_user_opts "${customconf}"
show_chosen_opts

using_custom_config_file=''
if [ "${CONFIG_FILE}" != "${myconf}" ]; then
    using_custom_config_file='y'
fi

# For each op, fail the script if the operation fails.
edit_config "${myconf}"
if [ $? -ne 0 ]; then
    terminate
fi

# Edit the cron job runners.
for script in "${FULL_CRON_SH}" "${INCR_CRON_SH}"; do
    edit_runner_sh "${script}" "${using_custom_config_file}"
    if [ $? -ne 0 ]; then
        terminate
    fi
done


install_errors=''

# Copy the config file to the custom location, if requested.
if [ -n "${using_custom_config_file}" ]; then
    checked_copy ${myconf} ${CONFIG_FILE}
    if [ $? -ne 0 ]; then
        install_errors='y'
    fi
fi

# Install the cron job runners.
if [ -z "${INCR_CRON_EXISTS}" -a -n "${INCR_CRON_INSTALLPATH}" ]; then
    checked_copy ${INCR_CRON_SH} ${INCR_CRON_INSTALLPATH}
    if [ $? -ne 0 ]; then
        install_errors='y'
    fi
fi
if [ -z "${FULL_CRON_EXISTS}" -a -n "${FULL_CRON_INSTALLPATH}" ]; then
    checked_copy ${FULL_CRON_SH} ${FULL_CRON_INSTALLPATH}
    if [ $? -ne 0 ]; then
        install_errors='y'
    fi
fi


# Finally, run the initial backup in the background.
if [ -n "${DO_FULL_NOW}" ]; then
    if [ -n "${install_errors}" ]; then
        echo "# Install errors.  Skipping initial backup."
        echo "# To run manually, execute the following command:"
        echo "#     nohup ${FULL_CRON_SH} >/tmp/pkgBackup-1st.log 2>&1 &"
        exit 1
    fi
    echo "Starting first-time full backup.  Output redirected to "
    echo "file \"/tmp/pkgBackup-1st.log\"."
    nohup ${FULL_CRON_SH} >/tmp/pkgBackup-1st.log 2>&1 &
fi


#################
#
#  End
