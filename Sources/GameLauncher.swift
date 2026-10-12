import Foundation
import AppKit

struct GameLauncher {
    static let steamAppID = "311210"

    private static let offlineModeKey = "launchWithoutSteam"

    static var launchWithoutSteam: Bool {
        get { UserDefaults.standard.bool(forKey: offlineModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: offlineModeKey) }
    }

    static func launch() {
        guard MacFixInstaller.isGamePresent else {
            MacFixInstaller.promptInstallIfNeeded()
            return
        }

        if Paths.installType == .nonSteam {
            launchWithoutSteam = true
        }

        if !MacFixInstaller.isInstalled {
            MacFixInstaller.promptInstallIfNeeded()
            guard MacFixInstaller.isInstalled else { return }
        }

        launchWithFix()
    }

    private static func launchWithFix() {
        let bo3Root = Paths.bo3Root
        let gameExe = bo3Root + "/CoDBlkOps3.app/Contents/MacOS/CoDBlkOps3_Exe"
        let gameDir = bo3Root + "/CoDBlkOps3.app/Contents/MacOS"
        let fixDylib = bo3Root + "/BO3MacFix/BO3MacFix.dylib"
        let winePrefix = bo3Root + "/BO3MacFix/pfx"

        guard FileManager.default.fileExists(atPath: gameExe) else {
            launchViaCLI()
            return
        }

        ControllerManager.shared.suspend()

        let rumbleDylib = bo3Root + "/BO3MacFix/DualSenseRumble.dylib"

        var env = ProcessInfo.processInfo.environment
        var dylibs = fixDylib
        if FileManager.default.fileExists(atPath: rumbleDylib) {
            dylibs += ":" + rumbleDylib
        }
        if let existing = env["DYLD_INSERT_LIBRARIES"] {
            dylibs += ":" + existing
        }
        env["DYLD_INSERT_LIBRARIES"] = dylibs
        env["WINEPREFIX"] = winePrefix
        env["SteamAppId"] = steamAppID
        if launchWithoutSteam {
            env["BO3MACFIX_OFFLINE"] = "1"
        }

        let pid = spawnDetached(exe: gameExe, dir: gameDir, env: env)
        if pid > 0 {
            DispatchQueue.main.async { LoadingOverlay.shared.show() }
            monitorPid(pid)
        } else {
            ControllerManager.shared.resume()
            launchViaCLI()
        }
    }

    private static func launchViaCLI() {
        ControllerManager.shared.suspend()

        let cliPath = Paths.macFixBinary
        let cliDir = Paths.macFixDir

        var env = ProcessInfo.processInfo.environment
        env["SteamAppId"] = steamAppID
        if launchWithoutSteam {
            env["BO3MACFIX_OFFLINE"] = "1"
        }

        let pid = spawnDetached(exe: cliPath, dir: cliDir, env: env, args: ["9"])
        if pid > 0 {
            DispatchQueue.main.async { LoadingOverlay.shared.show() }
            monitorPid(pid)
        } else {
            ControllerManager.shared.resume()
            launchViaSteam()
        }
    }

    /// Spawn a process in its own session so it doesn't inherit our HID claims.
    private static func spawnDetached(exe: String, dir: String, env: [String: String], args: [String] = []) -> pid_t {
        var pid: pid_t = 0
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        let envStrings = env.map { "\($0.key)=\($0.value)" }
        var cEnv = envStrings.map { strdup($0)! as UnsafeMutablePointer<CChar>? }
        cEnv.append(nil)

        var cArgs: [UnsafeMutablePointer<CChar>?] = [strdup(exe)]
        for arg in args { cArgs.append(strdup(arg)) }
        cArgs.append(nil)

        let savedDir = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(dir)

        let result = posix_spawn(&pid, exe, nil, &attr, &cArgs, &cEnv)

        FileManager.default.changeCurrentDirectoryPath(savedDir)
        posix_spawnattr_destroy(&attr)
        cArgs.compactMap({ $0 }).forEach { free($0) }
        cEnv.compactMap({ $0 }).forEach { free($0) }

        return result == 0 ? pid : -1
    }

    private static func monitorPid(_ pid: pid_t) {
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            DispatchQueue.main.async {
                LoadingOverlay.shared.dismiss()
                ControllerManager.shared.resume()
            }
        }
    }

    static func launchViaSteam() {
        if let url = URL(string: "steam://rungameid/\(steamAppID)") {
            NSWorkspace.shared.open(url)
        }
    }

    static var isGameInstalled: Bool {
        FileManager.default.fileExists(atPath: Paths.macFixBinary)
    }

    static var isSteamIntegrated: Bool {
        let backupPath = Paths.bo3Root + "/CoDBlkOps3.app/Contents/MacOS/AppBundleExe_original"
        return FileManager.default.fileExists(atPath: backupPath)
    }

    private static let pendingSteamIntegrationKey = "pendingSteamIntegration"

    static func resumeSteamIntegrationIfNeeded() {
        if UserDefaults.standard.bool(forKey: pendingSteamIntegrationKey) {
            UserDefaults.standard.removeObject(forKey: pendingSteamIntegrationKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                installSteamIntegration()
            }
        }
    }

    static func installSteamIntegration() {
        if !AppMover.isInApplications {
            UserDefaults.standard.set(true, forKey: pendingSteamIntegrationKey)
            if AppMover.moveToApplicationsIfNeeded() {
                return
            }
            UserDefaults.standard.removeObject(forKey: pendingSteamIntegrationKey)
            if !AppMover.isInApplications {
                showAlert("Steam Integration", "Steam integration requires BO3 Launcher to be in /Applications.\n\nMove the app there and try again.")
                return
            }
        }

        let appBundleExe = Paths.bo3Root + "/CoDBlkOps3.app/Contents/MacOS/AppBundleExe"
        let backupPath = Paths.bo3Root + "/CoDBlkOps3.app/Contents/MacOS/AppBundleExe_original"

        guard let builtRedirector = buildRedirector() else {
            showAlert("Build Failed", "Could not compile the Steam redirector. Make sure Xcode command line tools are installed.")
            return
        }

        // Back up original (only if not already backed up)
        if !FileManager.default.fileExists(atPath: backupPath) {
            do {
                try FileManager.default.moveItem(atPath: appBundleExe, toPath: backupPath)
            } catch let error as NSError {
                showAlert("Backup Failed", permissionMessage(for: error, path: appBundleExe))
                return
            }
        }

        // Copy redirector
        do {
            if FileManager.default.fileExists(atPath: appBundleExe) {
                try FileManager.default.removeItem(atPath: appBundleExe)
            }
            try FileManager.default.copyItem(atPath: builtRedirector, toPath: appBundleExe)

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["755", appBundleExe]
            try chmod.run()
            chmod.waitUntilExit()

            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", appBundleExe]
            try xattr.run()
            xattr.waitUntilExit()

            showAlert("Steam Integration Installed", "When you click Play in Steam, it will now open BO3 Launcher.")
        } catch let error as NSError {
            showAlert("Install Failed", permissionMessage(for: error, path: appBundleExe))
        }
    }

    static func uninstallSteamIntegration() {
        let appBundleExe = Paths.bo3Root + "/CoDBlkOps3.app/Contents/MacOS/AppBundleExe"
        let backupPath = Paths.bo3Root + "/CoDBlkOps3.app/Contents/MacOS/AppBundleExe_original"

        guard FileManager.default.fileExists(atPath: backupPath) else {
            showAlert("No Backup Found", "Cannot restore — no backup of the original launcher was found.")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: appBundleExe) {
                try FileManager.default.removeItem(atPath: appBundleExe)
            }
            try FileManager.default.moveItem(atPath: backupPath, toPath: appBundleExe)
            showAlert("Steam Integration Removed", "The original launcher has been restored. Steam will open the default Aspyr launcher again.")
        } catch let error as NSError {
            showAlert("Restore Failed", permissionMessage(for: error, path: appBundleExe))
        }
    }

    private static func buildRedirector() -> String? {
        guard let sourceFile = Bundle.main.path(forResource: "SteamRedirector", ofType: "m") else {
            return nil
        }
        let outputPath = NSTemporaryDirectory() + "SteamRedirector"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        process.arguments = [
            "-arch", "x86_64",
            "-framework", "Foundation",
            "-framework", "AppKit",
            "-o", outputPath,
            sourceFile
        ]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return outputPath
            }
        } catch {}
        return nil
    }

    private static func permissionMessage(for error: NSError, path: String) -> String {
        if error.domain == NSCocoaErrorDomain &&
           (error.code == NSFileWriteNoPermissionError || error.code == NSFileReadNoPermissionError) {
            return "Permission denied for:\n\(path)\n\nTry running the app as an administrator, or check that your user has write access to the game folder."
        }
        return error.localizedDescription
    }

    private static func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    static var gameVersion: String {
        "v1.1.0"
    }
}
