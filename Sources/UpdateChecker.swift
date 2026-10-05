import Foundation
import AppKit

struct UpdateChecker {
    // maxawad.com is down under a registrar hold, so the feed lives on redxam.com.
    private static let versionURL = URL(string: "https://bo3.redxam.com/bo3-launcher-version.json")!

    struct RemoteVersion: Decodable {
        let version: String
        let build: Int
        let download_url: String
        let release_notes: String
        let page_url: String
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1
    }

    static func checkForUpdates(silent: Bool = false) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: versionURL)
                let remote = try JSONDecoder().decode(RemoteVersion.self, from: data)

                if remote.build > currentBuild {
                    await MainActor.run {
                        promptUpdate(remote)
                    }
                } else if !silent {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "You're Up to Date"
                        alert.informativeText = "BO3 Launcher \(currentVersion) is the latest version."
                        alert.alertStyle = .informational
                        alert.runModal()
                    }
                }
            } catch {
                if !silent {
                    await MainActor.run {
                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = "Could not reach the update server.\n\n\(error.localizedDescription)"
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }
    }

    private static func promptUpdate(_ remote: RemoteVersion) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "BO3 Launcher \(remote.version) is available (you have \(currentVersion)).\n\n\(remote.release_notes)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: remote.download_url) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
