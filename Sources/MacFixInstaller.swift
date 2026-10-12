import Foundation
import AppKit

struct MacFixInstaller {
    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Paths.macFixBinary)
    }

    static var isGamePresent: Bool {
        FileManager.default.fileExists(atPath: Paths.bo3Root)
    }

    static func promptInstallIfNeeded() {
        if !isGamePresent {
            let alert = NSAlert()
            alert.messageText = "Game Not Found"
            alert.informativeText = "Could not find Call of Duty: Black Ops III at the default Steam path.\n\nIf the game is installed on a different drive or location, click \"Browse\" to select it."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Browse...")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            guard Paths.promptForGameFolder() else { return }
        }

        guard !isInstalled else { return }

        let alert = NSAlert()
        alert.messageText = "BO3MacFix Not Installed"
        alert.informativeText = "BO3MacFix is required to run Black Ops III on macOS.\n\nThis will extract the fix into your game folder. Wine must be installed separately (brew install --cask wine-stable)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Now")
        alert.addButton(withTitle: "Later")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        install()
    }

    static func install() {
        guard let tarPath = Bundle.main.path(forResource: "BO3MacFix", ofType: "tar.gz") else {
            showAlert(title: "Error", message: "BO3MacFix.tar.gz not found in app bundle.", style: .critical)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", tarPath, "-C", Paths.bo3Root]
        process.currentDirectoryURL = URL(fileURLWithPath: Paths.bo3Root)

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 && isInstalled {
                removeQuarantine()
                syncRumbleDylib()
                showAlert(
                    title: "BO3MacFix Installed",
                    message: "Successfully installed BO3MacFix to your game folder.\n\nMake sure Wine is installed:\nbrew install --cask --no-quarantine wine-stable",
                    style: .informational
                )
            } else {
                showAlert(title: "Installation Failed", message: "tar exited with code \(process.terminationStatus). Try extracting manually.", style: .critical)
            }
        } catch {
            showAlert(title: "Installation Failed", message: error.localizedDescription, style: .critical)
        }
    }

    /// Refreshes the patch itself, for the same reason as `syncRumbleDylib`.
    ///
    /// Only `BO3MacFix.dylib` is replaced. The tarball also carries the
    /// installer and `AppBundleExe`, but re-extracting the whole archive over a
    /// live install risks the Wine prefix sitting in the same directory.
    static func syncMacFixDylib() {
        guard let tar = Bundle.main.path(forResource: "BO3MacFix", ofType: "tar.gz") else { return }
        let dest = Paths.macFixDir + "/BO3MacFix.dylib"
        let fm = FileManager.default

        // Staged beside the destination, not in NSTemporaryDirectory.
        // `replaceItemAt` fails across volumes and the game usually lives on a
        // separate disk from the system drive.
        let scratch = Paths.macFixDir + "/.bo3macfix-sync-\(UUID().uuidString)"
        try? fm.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: scratch) }

        let untar = Process()
        untar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        untar.arguments = ["-xzf", tar, "-C", scratch, "BO3MacFix/BO3MacFix.dylib"]
        guard (try? untar.run()) != nil else { return }
        untar.waitUntilExit()
        guard untar.terminationStatus == 0 else { return }

        let fresh = scratch + "/BO3MacFix/BO3MacFix.dylib"
        guard let new = fm.contents(atPath: fresh) else { return }
        if let current = fm.contents(atPath: dest), current == new { return }

        guard (try? fm.replaceItemAt(URL(fileURLWithPath: dest),
                                     withItemAt: URL(fileURLWithPath: fresh))) != nil else { return }
        clearQuarantine(dest)
    }

    /// Copies the bundled shim into the game folder whenever the two differ.
    ///
    /// Call this before every launch, not just on install. `install()` is gated
    /// behind `!isInstalled`, so a player who already had BO3MacFix kept their
    /// original shim through every launcher update and never received a fix
    /// that lived in the shim rather than the launcher.
    static func syncRumbleDylib() {
        guard let src = Bundle.main.path(forResource: "DualSenseRumble", ofType: "dylib") else { return }
        let dest = Paths.macFixDir + "/DualSenseRumble.dylib"
        let fm = FileManager.default

        guard let fresh = fm.contents(atPath: src) else { return }
        if let current = fm.contents(atPath: dest), current == fresh { return }

        // Staged then moved. Overwriting in place has handed dyld a partially
        // written file, which it rejects as a signature not covering the whole
        // file and the game refuses to start.
        let staged = Paths.macFixDir + "/.DualSenseRumble.dylib.new"
        try? fm.removeItem(atPath: staged)
        guard (try? fm.copyItem(atPath: src, toPath: staged)) != nil else { return }
        guard (try? fm.replaceItemAt(URL(fileURLWithPath: dest),
                                     withItemAt: URL(fileURLWithPath: staged))) != nil else {
            try? fm.removeItem(atPath: staged)
            return
        }

        clearQuarantine(dest)
    }

    /// The copy inherits the app bundle's quarantine flag, and dyld will not
    /// inject a quarantined library into the game.
    private static func clearQuarantine(_ path: String) {
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-c", path]
        try? xattr.run()
        xattr.waitUntilExit()
    }

    private static func removeQuarantine() {
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", Paths.macFixDir]
        try? xattr.run()
        xattr.waitUntilExit()
    }

    private static func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
}
