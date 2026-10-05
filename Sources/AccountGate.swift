import Foundation
import AppKit

/// Plumbing for a future sign-in requirement.
///
/// No sign-in exists yet, so `userID` is always nil and the server policy ships
/// as `off`. Flipping `auth.policy` to `required` in bo3-launcher-version.json
/// starts enforcing it on launchers already in the wild, no new build needed.
///
/// This is a soft switch, not security. Anyone can defeat it by editing a
/// preference or blocking the domain. It exists to turn the lights off politely,
/// not to stop a determined user.
enum AccountGate {
    private static let userIDKey = "accountUserID"
    private static let policyURL = URL(string: "https://bo3.redxam.com/bo3-launcher-version.json")!
    private static let signInURL = URL(string: "https://bo3.redxam.com/")!

    // MARK: - Identity

    /// Whatever a future sign-in flow stores. Move this to the Keychain once it
    /// holds anything a server actually trusts.
    static var userID: String? {
        get {
            let value = UserDefaults.standard.string(forKey: userIDKey)
            return (value?.isEmpty ?? true) ? nil : value
        }
        set { UserDefaults.standard.set(newValue, forKey: userIDKey) }
    }

    static var isSignedIn: Bool { userID != nil }

    static func signOut() {
        UserDefaults.standard.removeObject(forKey: userIDKey)
    }

    // MARK: - Policy

    enum Policy: String, Decodable {
        /// Sign-in is irrelevant. Current behaviour.
        case off
        /// Ask once per launch, but let them through.
        case warn
        /// No user ID means the launcher closes.
        case required
    }

    struct AuthPolicy: Decodable {
        let policy: Policy
        let message: String?
        /// Lets old builds be grandfathered in when enforcement starts.
        let min_build: Int?
    }

    private struct RemoteConfig: Decodable {
        let auth: AuthPolicy?
    }

    // MARK: - Enforcement

    /// Call early in launch. Unreachable server or missing `auth` block means
    /// no enforcement: a server hiccup must never brick everyone's launcher.
    static func enforce() {
        guard !isSignedIn else { return }

        Task {
            guard let policy = await fetchPolicy() else { return }
            guard policy.policy != .off else { return }
            if let minBuild = policy.min_build, UpdateChecker.currentBuild < minBuild { return }

            await MainActor.run {
                switch policy.policy {
                case .off:
                    break
                case .warn:
                    show(policy, blocking: false)
                case .required:
                    show(policy, blocking: true)
                }
            }
        }
    }

    private static func fetchPolicy() async -> AuthPolicy? {
        do {
            var request = URLRequest(url: policyURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(RemoteConfig.self, from: data).auth
        } catch {
            return nil
        }
    }

    @MainActor
    private static func show(_ policy: AuthPolicy, blocking: Bool) {
        let alert = NSAlert()
        alert.messageText = blocking ? "Sign In Required" : "Sign In Recommended"
        alert.informativeText = policy.message
            ?? (blocking
                ? "BO3 Launcher now requires an account. Sign in at bo3.redxam.com to keep using it."
                : "BO3 Launcher will soon require an account. Sign in at bo3.redxam.com.")
        alert.alertStyle = blocking ? .critical : .informational
        alert.addButton(withTitle: "Open bo3.redxam.com")
        alert.addButton(withTitle: blocking ? "Quit" : "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(signInURL)
        }

        if blocking {
            NSApp.terminate(nil)
        }
    }
}
