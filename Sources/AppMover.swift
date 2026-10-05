import Foundation
import AppKit

enum AppMover {
    private static let applicationsDir = "/Applications"

    static var isInApplications: Bool {
        Bundle.main.bundlePath.hasPrefix(applicationsDir + "/")
    }

    /// Returns `true` if the app was moved and relaunched (caller should bail out).
    @discardableResult
    static func moveToApplicationsIfNeeded() -> Bool {
        guard let bundlePath = Bundle.main.bundlePath as String?,
              let bundleName = Bundle.main.bundlePath.components(separatedBy: "/").last
        else { return false }

        let destination = (applicationsDir as NSString).appendingPathComponent(bundleName)

        if bundlePath == destination { return false }
        if bundlePath.hasPrefix(applicationsDir + "/") { return false }

        // Ask the user for confirmation
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage

        let fm = FileManager.default
        let alreadyExists = fm.fileExists(atPath: destination)

        if alreadyExists {
            alert.messageText = "Update BO3 Launcher in Applications?"
            alert.informativeText = "An older version exists in /Applications. This will replace it with the current version and relaunch the app."
        } else {
            alert.messageText = "Move to Applications?"
            alert.informativeText = "BO3 Launcher needs to be in /Applications to work properly.\n\nThe app will be moved from its current location and relaunched automatically."
        }

        alert.addButton(withTitle: alreadyExists ? "Replace & Relaunch" : "Move & Relaunch")
        alert.addButton(withTitle: "Not Now")

        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        // Remove existing copy if present
        if alreadyExists {
            do { try fm.removeItem(atPath: destination) } catch {
                showError("Could not remove old copy: \(error.localizedDescription)")
                return false
            }
        }

        // Move (not copy) the app to /Applications
        do {
            try fm.moveItem(atPath: bundlePath, toPath: destination)
        } catch {
            // moveItem can fail across volumes; fall back to copy + delete
            do {
                try fm.copyItem(atPath: bundlePath, toPath: destination)
                try fm.removeItem(atPath: bundlePath)
            } catch let innerError as NSError {
                if innerError.domain == NSCocoaErrorDomain &&
                   (innerError.code == NSFileWriteNoPermissionError || innerError.code == NSFileReadNoPermissionError) {
                    showError("Permission denied.\n\nYour user account doesn't have write access to /Applications. Try dragging the app there manually, or run the app as an administrator.")
                } else {
                    showError("Could not move app to /Applications: \(innerError.localizedDescription)")
                }
                return false
            }
        }

        // Strip quarantine from the new location
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", destination]
        try? xattr.run()
        xattr.waitUntilExit()

        relaunch(at: destination)
        return true
    }

    private static func relaunch(at path: String) {
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Move Failed"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}
