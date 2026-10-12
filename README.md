# BO3 Launcher for macOS

A native macOS launcher for **Call of Duty: Black Ops III** that makes Steam
Workshop mods and custom zombies maps actually work on a Mac.

**[Download the latest build](https://bo3.redxam.com/BO3Launcher.zip)** ·
[Project page](https://maxawad.imake.lol/blackopsiii)

![BO3 Launcher](https://maxawad.imake.lol/bo3-launcher-hero.png)

## The problem

The Aspyr macOS port of Black Ops III ships without mod support. Subscribe to a
Workshop map on a Mac and nothing happens: the game never loads it, and there is
no in-game mods menu like the Windows version has.

[BO3MacFix](https://github.com/InvoxiPlayGames/BO3MacFix) by Emma
(InvoxiPlayGames) and Anthony (serious) solves the hard part by patching the
game at runtime. Installing it, though, means a terminal, a hand-edited app
bundle, and redoing the whole thing every time Steam verifies your files.

This launcher wraps that in something you can hand to a friend.

## What it does

- **One-click BO3MacFix install.** Bundles a forked build of the patch and
  installs it into your game, no terminal involved.
- **Workshop mod browser.** Lists every mod you're subscribed to, with sizes,
  thumbnails and descriptions pulled from Steam.
- **Real uninstall.** Deleting a mod unsubscribes you on Steam first, then
  permanently removes the files. Deleting the folder alone does nothing: Steam
  re-downloads it on next launch.
- **Storage breakdown.** Shows how much of your drive the game, the mods, and
  everything else are using, so you know what you're reclaiming.
- **Works from any drive.** Detects Steam libraries on external drives by
  reading `libraryfolders.vdf`, not by assuming a path under your home folder.
- **Skips the intro videos.** Straight to the main menu.
- **Steam integration.** Optionally makes Steam's Play button open the launcher.
- **DualSense rumble**, for up to four controllers at once. The Mac port's
  ForceFeedback path does nothing on a DualSense, so the launcher injects a shim
  that turns the game's effects into Bluetooth output reports.
- **PlayStation button prompts and icons**, everywhere the game would otherwise
  draw Xbox ones: the HUD, the keybind list, the menu footers, and the
  controller diagram on the layout screens.
- **A loading screen** over the black gap between launching and the game's first
  window, which can run close to a minute.

## Requirements

- macOS 14 or later, Apple Silicon or Intel
- A legitimate Steam copy of Call of Duty: Black Ops III (app ID 311210)
- Steam installed and signed in

The launcher does not distribute the game, any game assets, or Valve's
Steamworks libraries. You need to own and install the game yourself.

## Install

1. Download `BO3Launcher.zip` and drag the app to **Applications**.
2. Open it. If macOS asks for permission to read removable volumes, allow it:
   that is how the launcher finds a game installed on an external drive.
3. If it doesn't find your game automatically, drag the game folder onto the
   drop zone. In Steam: right-click **Call of Duty: Black Ops III** →
   **Manage** → **Browse local files**.
4. Click install when it offers to patch the game.

## Building from source

Requires Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
# Build the BO3MacFix payload the launcher installs (~81 MB output)
./scripts/build-macfix-payload.sh

xcodegen generate
./build-and-run.sh
```

`rumble-shim/dualsense_rumble.c` is compiled by a build phase and bundled into
the app, which installs it next to the game. It is **x86_64** because the game
is, and it carries both the rumble bridge and the PlayStation glyph swap.
`rumble-shim/build.sh` also builds `rumbletest`, a native binary that pulses a
connected DualSense so you can check the Bluetooth path without the game.

`vendor/steam-unsub/steam-unsub.c` is compiled as a separate **x86_64** helper
by a build phase. It has to be: Valve's `libsteam_api.dylib` shipped with the
game is Intel-only, so an arm64 launcher cannot link against it directly. The
helper runs under Rosetta and handles Workshop unsubscribes.

## Licensing and credits

`vendor/BO3MacFix-src/` is a fork of
[InvoxiPlayGames/BO3MacFix](https://github.com/InvoxiPlayGames/BO3MacFix),
licensed under the **LGPL 2.1** (see `vendor/BO3MacFix-src/LICENSE.txt`). The
fork changes the in-game watermark branding only; the source is published here
to satisfy the license. All the patching work is theirs.

Credit also to Alyssa / alltheamps for t7patch and the cod2map64 patch, and to
[Dobby](https://github.com/jmpews/Dobby) for the macOS code hooking.

Not affiliated with, endorsed by, or supported by Activision, Treyarch, Aspyr,
or Valve.
