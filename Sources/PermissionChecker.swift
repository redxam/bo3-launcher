import Foundation
import AppKit
import CoreGraphics

struct PermissionChecker {
    private static let hasPromptedKey = "hasPromptedInputMonitoring"

    static var hasInputMonitoring: Bool {
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        )
        return tap != nil
    }

    static func promptIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasPromptedKey) else { return }
        UserDefaults.standard.set(true, forKey: hasPromptedKey)

        if !hasInputMonitoring {
            showPermissionAlert()
        }
    }

    private static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Input Monitoring Required"
        alert.informativeText = "BO3 Launcher needs Input Monitoring permission to launch the game with the Mac fix.\n\nClick \"Open Settings\" and enable BO3 Launcher in the list."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            openInputMonitoringSettings()
        }
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
