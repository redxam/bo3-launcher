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
                installRumbleDylib()
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

    private static func installRumbleDylib() {
        guard let src = Bundle.main.path(forResource: "DualSenseRumble", ofType: "dylib") else { return }
        let dest = Paths.macFixDir + "/DualSenseRumble.dylib"
        let fm = FileManager.default
        try? fm.removeItem(atPath: dest)
        try? fm.copyItem(atPath: src, toPath: dest)
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
