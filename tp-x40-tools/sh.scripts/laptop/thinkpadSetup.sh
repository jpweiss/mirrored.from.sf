#!/bin/sh
#
# Copyright (C) 2004-2011 by John P. Weiss
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


############
#
# Includes & Other Global Variables
#
############


IBM_ACPI=/sys/devices/platform/thinkpad_acpi/
IBM_PROC_ACPI=/proc/acpi/ibm
SYS_MOUSE=/sys/class/input/mouse0/device


############
#
# Functions
#
############


set_kernel() {
    # Do nothing if the kernel file doesn't exist
    if [ ! -f $1 ]; then
        return 0
    fi
    # Punt if there's no setting
    if [ -z "$2" ]; then
        return 1
    fi

    echo -n $2 >> $1
    return 0
}


activate_ThinkPad_keys() {
    # Set the hotkey mask.
    #
    # The Mask puts specific Fn+F[x] keys under ACPI control, instead of the
    # default behavior.  In some cases, the default behavior *is* ACPI
    # control, while in others, it's BIOS control.  Each bit, when set to 1,
    # forces ACPI control for the corresponding F[x] function key.
    # E.g. 0x10000 would put only Fn+F5 under ACPI control.
    #
    # The X40 does not recognize the following keys in combination with the
    # "Fn" key:
    #     F1
    #     F2
    #     F6
    #     F10
    #     F11
    #
    # The mask '0x099C' is equal to 100110011100, which preserves default
    # behavior for Fn+F7 only.
    #
    # The mask '0x0FBF' put all keys except for Fn+F7 under ACPI control.
    #
    # The mask '0x8C7FBF' is the default value, with Fn+F7 removed
    # from ACPI control.  '0x8C7EBF' also removes Fn+F9 from ACPI control.
    ####set_kernel ${IBM_ACPI}/hotkey_mask 0x8C7FBF

    # [jpw; 20110513]  '0x8C7EFF' leaves everything but Fn+F9 under ACPI
    #                  control.  Turning off the LCD appears to be causing 
    #                  problems for Ubuntu 10.10; it won't turn back on.  
    #                  Fn+F9 is triggering some "acpid" doc/undock event,
    #                  which turns off the LCD.  So this is a workaround.
    set_kernel ${IBM_ACPI}/hotkey_mask 0x8C7EFF

    # Now we turn on the ThinkPad hotkeys.
    # [jpw; 20091226]  Causes Errors - Hotkeys always enabled.
    ####set_kernel ${IBM_ACPI}/hotkey_enable 1

    # [jpw; 20110515]  Current kernels have all of the Fn+F[x] keys under
    #                  ACPI control.  Fn+F7 should be properly translated into
    #                  an XWin keysym and sent to X-RandR.
    #
    #                  So, hardware-based monitor-switching shouldn't be
    #                  necessary anymore, making this function redundant.
    return 0
}


load_custom_keymap() {
    # This is where you set up your console keymap for the special ThinkPad
    # X40  "Fn" key and the two special window-scroll keys.
    # 
    # I DO NOT recommend changing the scancode<-->keycode mappings, as this is
    # guaranteed to break X.
    #
    # The keycode assignments for these ThinkPad keys is as follows:
    #     Fn              <--> keycode 143
    #     Left WinScroll  <--> keycode 158
    #     Right WinScroll <--> keycode 159
    #
    # The console keycode bindings default to:
    #   keycode 143 == nul
    #   keycode 158 == nul
    #   keycode 159 == nul
    #
    # Now, to prevent chaos from erupting whenever you use these keys or hit
    # them by accident, we'll unmap them all.  Only in combination with
    # modifier keys will they do anything.

    # My TPX40 Mappings:
    #  Fn              ==>  VoidSymbol Compose
    #  Left WinScroll  ==>  Scroll_Backward AltGr
    #    alt Left WinScroll  ==> Decr_Console
    #  Right WinScroll ==>  Scroll_Forward AltGr
    #    ctrl Right WinScroll ==> Macro
    #    alt Right WinScroll ==> Incr_Console


    # See keymaps(5) for details, including binding of commands to keys
    # N.B.: Debugging:
    # If the script fails here, make sure that the Here-Doc has leading TAB
    # characters, not spaces.
    loadkeys <<-EOF
		keycode 143 = VoidSymbol Do
		keycode 158 = Scroll_Backward AltGr
		control keycode 158 = Compose
		alt keycode 158 = Decr_Console
		keycode 159 = Scroll_Forward AltGr
		control keycode 159 = Macro
		alt keycode 159 = Incr_Console
EOF
# Testing the Ctrl-LWinScrl binding.
# N.B.: string F20  = "\033[34~"
#       string Menu = "\033[29~"  <==>  F16
#       Help  <==>  F15
}


mapscancodes() {
    # Scancode <--> Keycode mappings

    # The Linux 2.6 kernel series will, when ACPI is enabled, automatically
    # map *some* of the OneTouch Buttons to console keycodes that correspond
    # to the XKeycodes mapped to the XKeySyms you want for these buttons.  It
    # doesn't map all of them, however.

    # The scancodes generated by a keyboard ... any keyboard ... are distinct
    # entities from the keycodes assigned to each key by the linux kernel.
    # You then need to map these keycodes to actual key names recognized by
    # the console.  For X, there is a corresponding set of XKeycodes and
    # XKeySyms.  For most keyboards, you don't need to worry about, let alone
    # touch, any of this.
    #
    # For nonstandard keyboards, you have trouble.
    #
    # First off, the console keycodes and the XKeycodes are not the same for
    # the same key.  Oh, they may be the same for *some* keys, but not all,
    # and definitely not your special keys on that funky keyboard you have.
    # As if this weren't bad enough, there isn't even a function or an obvious
    # pattern showing which console keycodes correspond to what XKeycodes.
    # The only way to find this mapping is through empirical research.

    # The Blue "Fn" Key
    # Defaults:
    #     scancode==e063,  keycode==143,
    #     XKeycode==227
    # Map "Fn" to same keycode as Off.  No XKeycode/XKeySym needed.
    ##The default is correct in this case.  No change needed.
    ##HOTKEY_SCMAP="e063 143"
    #
	# The Left "Window-Scroll" Key
    # Default
    #     scancode==e06a,  keycode==158,
    #     XKeycode==234
    ##The default is correct in this case.  No change needed.
    ##HOTKEY_SCMAP="${HOTKEY_SCMAP} e06a 158"
    #
	# The Right "Window-Scroll" Key
    # Default:
    #     scancode==e069,  keycode==159,
    #     XKeycode==233
    ##The default is correct in this case.  No change needed.
    ##HOTKEY_SCMAP="${HOTKEY_SCMAP} e069 159"

    # Now actually set the scancode<-->console keycode mappings.
    ##setkeycodes ${HOTKEY_SCMAP}
    :
}


enableThinkPadLCD() {
    lcdIsOff=""

    # Make sure the LCD is on.  Ran into trouble with blank screen in X after
    # a resume. 
    set -- `cat ${IBM_PROC_ACPI}/video`
    while [ -n "$1" ]; do
        case "$1" in
            lcd:)
                shift
                case "$1" in
                    enabled)
                        lcdIsOff=""
                        ;;
                    disabled)
                        lcdIsOff="y"
                        ;;
                esac
                ;;
        esac
        shift
    done

    if [ -n "$lcdIsOff" ]; then
        set_kernel ${IBM_PROC_ACPI}/video lcd_enable
    fi
}


activate_TrackPoint() {
    if [ ! -d ${SYS_MOUSE} ]; then
        return 1
    fi

    case "`cat ${SYS_MOUSE}/protocol`" in
        *[Tt][Pp][Pp][Ss]*)
            :
            ;;
        *)
            return 0
            ;;
    esac

    if [ "$1" = "resume" ]; then
        flag=0
        set_kernel ${SYS_MOUSE}/power/state $flag
    fi

    set_kernel ${SYS_MOUSE}/press_to_select 1
    set_kernel ${SYS_MOUSE}/middle_btn_disable 1
}


############
#
# Main
#
############


case "$0" in
    *bash)
        file_was_sourced='y'
        ;;
    *)
        if [ ${#BASH_SOURCE[*]} -gt 1 ]; then
            file_was_sourced='y'
        fi
        ;;
esac


if [ -n "$file_was_sourced" ]; then
    # Was sourced.  Remove the temporary variable created during the startup
    # checks.
    unset file_was_sourced
else
    # Was run as a script.  Perform any execution-specific tasks here (rather
    # than pulling an unneeded "main" function into the environment.

    # Permit monitor switching via Fn.+F7
    # Use "auto_disable" to turn it off.
    ##set_kernel ${IBM_PROC_ACPI}/video auto_enable

    # Use platform-based disk hibernation
    set_kernel /sys/power/disk platform

    # Set up the ThinkPad Fn+F[x] keys.
    activate_ThinkPad_keys

    # Map the raw keyboard codes for non-ACPI keys
    mapscancodes

    # Then, bind them to something...
    load_custom_keymap

    # Set up the new (v2.6.14+) TrackPoint support
    activate_TrackPoint
fi


#################
#
#  End
