import Foundation

/// Space breakdown for the volume the game lives on.
struct StorageInfo {
    let volumeName: String
    let total: Int64
    let free: Int64
    let game: Int64
    let mods: Int64

    /// Everything on the drive that isn't the game, its mods, or free space.
    var other: Int64 { max(0, total - free - game - mods) }

    /// Same formatter the mod rows use, so the segment sizes add up to the total
    /// the way the reader expects.
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// `modsBytes` comes from the already-scanned mod list, so it isn't recomputed.
    static func load(modsBytes: Int64) -> StorageInfo? {
        let root = Paths.bo3Root
        guard FileManager.default.fileExists(atPath: root) else { return nil }

        let url = URL(fileURLWithPath: root)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeNameKey,
        ]),
            let total = values.volumeTotalCapacity,
            let free = values.volumeAvailableCapacity
        else { return nil }

        return StorageInfo(
            volumeName: values.volumeName ?? "this drive",
            total: Int64(total),
            free: Int64(free),
            game: gameSize(root: root),
            mods: modsBytes
        )
    }

    /// Steam already tracks the install size, which beats walking 70 GB of files.
    private static func gameSize(root: String) -> Int64 {
        if let steamApps = Paths.steamAppsRoot(for: root),
           let size = sizeFromAppManifest(steamApps: steamApps) {
            return size
        }
        return directorySize(root)
    }

    private static func sizeFromAppManifest(steamApps: String) -> Int64? {
        let path = steamApps + "/appmanifest_311210.acf"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n") where line.contains("\"SizeOnDisk\"") {
            let parts = line.split(separator: "\"").map(String.init)
            if let raw = parts.last, let size = Int64(raw) { return size }
        }
        return nil
    }

    private static func directorySize(_ path: String) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            if let attrs = try? fm.attributesOfItem(atPath: path + "/" + file),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }
}
