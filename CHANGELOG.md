# Changelog

## 1.2.0 (build 3) - 2026-10-12

Published to `bo3.redxam.com`. Archive copy at `/releases/BO3Launcher-1.2.0.zip`.

- PlayStation button prompts in the HUD and the keybind list, by repointing the
  engine's glyph table at the PS3 column it already carries.
- PlayStation icons in the menus and on the Button / Stick Layout controller
  diagram, by hooking `DB_FindXAssetHeader` and swapping image names.
- Rumble for up to four DualSense controllers at once, mapped to Steam's player
  order.
- A loading screen over the black gap between launch and the game's first window.
- Payload binaries and the rumble shim are now signed with the Developer ID.
  Notarization unpacks `BO3MacFix.tar.gz` and rejects unsigned binaries inside it.

## 2026.07.11 - 2026-07-11

- Commit: `08f02b73b8690d6b1b848aadb1b0a8e08a1c7644`
- Previous version: `none`
- Previous commit: `none`
- Changed files: 47

### Commits
- `1cfd11857 fix(lowercase): BUG-001/002/003 + smooth download progress`
- `ea8916caa feat(bo3-launcher): v1.1.0 — non-Steam install, concurrent downloads, pause/resume`
- `d2800114d sync all projects — bo3 launcher, agent mobile app, lowercase iOS, dev cluster, support epic, company agents, projects board, clock, token exchange, esim, sales, and misc updates`
- `3e4b7e85b feat(projects): add agent roster, assignment UI, and expanded seed projects`
- `555c020ba uh uh random stuff.`
- `e7bb3476b production stuff.`
- `776e5fbdb feat(gaming): add BO3 custom launcher for macOS`

### Changed Files
- `.wrangler/cache/wrangler-account.json`
- `AGENT.MD`
- `BO3Launcher.xcodeproj/project.pbxproj`
- `BO3Launcher.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- `BO3Launcher.xcodeproj/project.xcworkspace/xcuserdata/promax.xcuserdatad/UserInterfaceState.xcuserstate`
- `BO3Launcher.xcodeproj/xcuserdata/promax.xcuserdatad/xcschemes/xcschememanagement.plist`
- `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.icns`
- `Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- `Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png`
- `Resources/Assets.xcassets/AppIcon.appiconset/icon_128.png`
- `Resources/Assets.xcassets/AppIcon.appiconset/icon_16.png`
- `Resources/Assets.xcassets/AppIcon.appiconset/icon_256.png`
- `Resources/Assets.xcassets/AppIcon.appiconset/icon_32.png`
- `Resources/Assets.xcassets/AppIcon.appiconset/icon_512.png`
- `Resources/Assets.xcassets/AppIcon.appiconset/icon_64.png`
- `Resources/Assets.xcassets/Contents.json`
- `Resources/BO3Launcher.entitlements`
- `Resources/Info.plist`
- `Sources/AppMover.swift`
- `Sources/ContentView.swift`
- `Sources/ControllerManager.swift`
- `Sources/DownloadView.swift`
- `Sources/FocusManager.swift`
- `Sources/GameDownloader.swift`
- `Sources/GameLauncher.swift`
- `Sources/HeaderView.swift`
- `Sources/LauncherApp.swift`
- `Sources/MacFixInstaller.swift`
- `Sources/ModsView.swift`
- `Sources/Paths.swift`
- `Sources/PermissionChecker.swift`
- `Sources/SteamWebView.swift`
- `Sources/SteamWorkshop.swift`
- `Sources/Theme.swift`
- `Sources/UpdateChecker.swift`
- `Sources/WhatsNewView.swift`
- `bg-upload.sh`
- `build-and-run.sh`
- `chunks/manifest.json`
- `crash.err`
- ...and 7 more
