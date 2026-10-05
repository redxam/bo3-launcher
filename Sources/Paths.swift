import Foundation
import AppKit

enum Paths {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    private static let defaultSteamApps = home + "/Library/Application Support/Steam/steamapps"
    private static let defaultBo3Root = defaultSteamApps + "/common/Call of Duty Black Ops III"
    static let defaultSteamCommon = defaultSteamApps + "/common"
    static let nonSteamDefault = home + "/Documents/Call of Duty Black Ops III"
    static let nonSteamParent = home + "/Documents"
    private static let customPathKey = "customBO3Path"

    enum InstallType {
        case steam
        case nonSteam
        case none
    }

    static var installType: InstallType {
        if let custom = UserDefaults.standard.string(forKey: customPathKey),
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom + "/CoDBlkOps3.app") {
            // A Steam library can live on any volume, so identify it by layout
            // rather than by matching the default path.
            if steamAppsRoot(for: custom) != nil { return .steam }
            return .nonSteam
        }
        if FileManager.default.fileExists(atPath: defaultBo3Root + "/CoDBlkOps3.app") {
            return .steam
        }
        if FileManager.default.fileExists(atPath: nonSteamDefault + "/CoDBlkOps3.app") {
            return .nonSteam
        }
        return .none
    }

    static var bo3Root: String {
        if let custom = UserDefaults.standard.string(forKey: customPathKey),
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return custom
        }
        if FileManager.default.fileExists(atPath: defaultBo3Root) {
            return defaultBo3Root
        }
        if FileManager.default.fileExists(atPath: nonSteamDefault) {
            return nonSteamDefault
        }
        return defaultBo3Root
    }

    /// The parent folder that `tar xf` should extract into.
    /// The archive contains "Call of Duty Black Ops III/" at the root,
    /// so extracting to the parent creates the game folder.
    static var extractionParent: String {
        if let custom = UserDefaults.standard.string(forKey: customPathKey),
           !custom.isEmpty {
            return (custom as NSString).deletingLastPathComponent
        }
        switch installType {
        case .steam: return defaultSteamCommon
        case .nonSteam: return nonSteamParent
        case .none: return nonSteamParent
        }
    }

    static var macFixBinary: String { bo3Root + "/BO3MacFix/Install_BO3MacFix" }
    static var macFixDir: String { bo3Root + "/BO3MacFix" }
    /// Workshop content lives in `<library>/steamapps/workshop`, which only exists
    /// when the game sits in a real Steam library. Walking three levels up blindly
    /// lands on `/` for a loose copy, so require the `steamapps/common` layout.
    static var workshopMods: String? {
        guard let steamApps = steamAppsRoot(for: bo3Root) else { return nil }
        return steamApps + "/workshop/content/311210"
    }

    /// `<library>/steamapps` if `path` is `<library>/steamapps/common/<game>`.
    static func steamAppsRoot(for path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let common = url.deletingLastPathComponent()
        guard common.lastPathComponent == "common" else { return nil }
        let steamApps = common.deletingLastPathComponent()
        guard steamApps.lastPathComponent == "steamapps" else { return nil }
        return steamApps.path
    }

    static var isUsingCustomPath: Bool {
        UserDefaults.standard.string(forKey: customPathKey) != nil
    }

    static func setCustomPath(_ path: String?) {
        UserDefaults.standard.set(path, forKey: customPathKey)
    }

    /// A path was chosen earlier but is gone now, usually an unmounted drive.
    /// Distinct from "never set up", which should show onboarding instead.
    static var savedPathIsMissing: Bool {
        guard let custom = UserDefaults.standard.string(forKey: customPathKey),
              !custom.isEmpty else { return false }
        return !FileManager.default.fileExists(atPath: custom + "/CoDBlkOps3.app")
    }

    static var savedPath: String? {
        UserDefaults.standard.string(forKey: customPathKey)
    }

    enum DropResult {
        case accepted(String)
        case wrongFolder
        case notAFolder
    }

    /// Accepts either the game folder or `CoDBlkOps3.app` itself, since dragging
    /// from "Browse local files" gives the folder but dragging the icon gives the app.
    static func resolveDroppedPath(_ url: URL) -> DropResult {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return .notAFolder
        }

        let candidate: URL = url.lastPathComponent == "CoDBlkOps3.app"
            ? url.deletingLastPathComponent()
            : url

        guard FileManager.default.fileExists(atPath: candidate.path + "/CoDBlkOps3.app") else {
            return .wrongFolder
        }
        return .accepted(candidate.path)
    }

    @discardableResult
    static func acceptDroppedGameFolder(_ url: URL) -> DropResult {
        let result = resolveDroppedPath(url)
        if case let .accepted(path) = result {
            setCustomPath(path)
        }
        return result
    }

    // MARK: - Auto-detection

    private static let gameFolderName = "Call of Duty Black Ops III"

    /// Every Steam library Steam knows about, including ones on other drives.
    static func steamLibraryPaths() -> [String] {
        let candidates = [
            home + "/Library/Application Support/Steam/steamapps/libraryfolders.vdf",
            home + "/Library/Application Support/Steam/config/libraryfolders.vdf",
        ]

        var paths: [String] = []
        for file in candidates {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            // Entries look like:  "path"<tab>"/Volumes/Games/SteamLibrary"
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "\"").map(String.init)
                guard parts.count >= 4, parts[0].trimmingCharacters(in: .whitespaces).isEmpty,
                      parts[1] == "path" else { continue }
                paths.append(parts[3])
            }
        }
        return Array(Set(paths))
    }

    /// Looks for the game wherever Steam has a library, then in the usual
    /// non-Steam spots. Returns the game folder, not the .app.
    static func autoDetectGamePath() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []

        for library in steamLibraryPaths() {
            candidates.append(library + "/steamapps/common/" + gameFolderName)
        }
        candidates.append(defaultBo3Root)
        candidates.append(nonSteamDefault)

        return candidates.first { fm.fileExists(atPath: $0 + "/CoDBlkOps3.app") }
    }

    /// Runs at startup. Only fills in a path when we don't already have a working
    /// one, so it never overrides a folder the user picked deliberately.
    @discardableResult
    static func autoDetectIfNeeded() -> Bool {
        if let custom = savedPath, !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom + "/CoDBlkOps3.app") {
            return false
        }
        guard let found = autoDetectGamePath() else { return false }
        setCustomPath(found)
        return true
    }

    static func promptForGameFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Select your Call of Duty Black Ops III folder"
        panel.message = "Navigate to the folder containing CoDBlkOps3.app"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            let appPath = url.appendingPathComponent("CoDBlkOps3.app").path
            if FileManager.default.fileExists(atPath: appPath) {
                setCustomPath(url.path)
                return true
            } else {
                let alert = NSAlert()
                alert.messageText = "Invalid Folder"
                alert.informativeText = "CoDBlkOps3.app was not found in the selected folder. Make sure you selected the correct game directory."
                alert.alertStyle = .warning
                alert.runModal()
                return false
            }
        }
        return false
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: customPathKey)
    }
}
