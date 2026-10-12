#!/bin/bash
# Runs BO3MacFix's own Install_BO3MacFix menu with two things set up first:
#
#   1. An SDL mapping for the DualSense. The game's SDL is 2.0.7, which predates
#      the controller and has no entry for 054c:0ce6, so without this it sees an
#      unknown HID device and reports no controller at all.
#   2. The rumble shim in DYLD_INSERT_LIBRARIES. The installer prepends its own
#      fix dylib to whatever it inherits, so both end up injected.
#
# Run with NO_RUMBLE=1 to test input on its own.
cd "$(dirname "$0")"

# SDL 2.0.7 builds this GUID from bus 0x03, vendor 0x054c, product 0x0ce6,
# version 0x0100. Button layout mirrors the PS4 entry already in the binary.
export SDL_GAMECONTROLLERCONFIG="030000004c050000e60c000000010000,PS5 Controller,a:b1,b:b2,x:b0,y:b3,back:b8,guide:b12,start:b9,leftstick:b10,rightstick:b11,leftshoulder:b4,rightshoulder:b5,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a2,righty:a5,lefttrigger:a3,righttrigger:a4,platform:Mac OS X,"

if [ "${NO_RUMBLE:-0}" = "1" ]; then
    echo "rumble disabled, mapping only"
else
    SHIM="$PWD/DualSenseRumble.dylib"
    if [ ! -f "$SHIM" ]; then
        echo "DualSenseRumble.dylib not found next to this script" >&2
        exit 1
    fi
    if [ -n "${DYLD_INSERT_LIBRARIES:-}" ]; then
        export DYLD_INSERT_LIBRARIES="$SHIM:$DYLD_INSERT_LIBRARIES"
    else
        export DYLD_INSERT_LIBRARIES="$SHIM"
    fi
    echo "rumble shim armed, log: ~/Library/Logs/bo3-rumble.log"
fi

exec ./Install_BO3MacFix
