import Foundation

/// Unsubscribes from workshop items through the real Steam API.
///
/// The work happens in the bundled `steam-unsub` helper because Valve's
/// libsteam_api.dylib is x86_64 and this app is arm64. The helper loads the
/// game's own copy of the dylib, so nothing of Valve's is redistributed.
enum SteamUnsubscriber {
    enum Failure: LocalizedError {
        case helperMissing
        case steamAPIMissing
        case steamNotReady
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .helperMissing:
                return "The unsubscribe helper is missing from the app bundle."
            case .steamAPIMissing:
                return "Couldn't find libsteam_api.dylib in your game folder."
            case .steamNotReady:
                return "Steam wouldn't respond. Make sure it's running and signed in."
            case let .failed(message):
                return message.isEmpty ? "Steam rejected the unsubscribe request." : message
            }
        }
    }

    private static var steamAPIPath: String? {
        let path = Paths.bo3Root + "/CoDBlkOps3.app/Contents/MacOS/libsteam_api.dylib"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    private static var helperPath: String? {
        Bundle.main.path(forAuxiliaryExecutable: "steam-unsub")
    }

    /// Number of workshop items Steam thinks you're subscribed to.
    /// Read-only, useful for confirming the Steam connection works.
    static func subscribedCount() -> Int? {
        guard case let .success(output) = run(argument: "--count") else { return nil }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last ?? "")
    }

    static func unsubscribe(id: String) -> Result<Void, Failure> {
        switch run(argument: id) {
        case .success:
            return .success(())
        case let .failure(error):
            return .failure(error)
        }
    }

    private static func run(argument: String) -> Result<String, Failure> {
        guard let helper = helperPath else { return .failure(.helperMissing) }
        guard let api = steamAPIPath else { return .failure(.steamAPIMissing) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = [api, argument]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .failure(.failed(error.localizedDescription))
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        switch process.terminationStatus {
        case 0: return .success(out)
        case 3: return .failure(.steamNotReady)
        default:
            return .failure(.failed(err.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
    }
}
