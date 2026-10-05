import SwiftUI

struct ModsView: View {
    @State private var mods: [ModEntry] = []
    @State private var workshopInfo: [String: WorkshopItem] = [:]
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var storage: StorageInfo?

    private static let workshop = SteamWorkshop()

    var filteredMods: [ModEntry] {
        if searchText.isEmpty { return mods }
        return mods.filter {
            let name = workshopInfo[$0.workshopID]?.title ?? $0.workshopID
            return name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Theme.divider)

            if let storage {
                StorageBarView(info: storage)
                Divider().background(Theme.divider)
            }

            if isLoading {
                loadingState
            } else if filteredMods.isEmpty {
                emptyState
            } else {
                modList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgDark)
        .task { await loadMods() }
    }

    private func loadMods() async {
        let scanned = ModEntry.scan()
        mods = scanned
        refreshStorage()
        let ids = scanned.map(\.workshopID)
        if !ids.isEmpty {
            workshopInfo = await Self.workshop.fetchDetails(ids: ids)
        }
        isLoading = false
    }

    private var toolbar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textMuted)
            TextField("Search mods...", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundColor(Theme.textPrimary)
                .font(.system(size: 13))

            Spacer()

            Button(action: {
                isLoading = true
                Task { await loadMods() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)

            Button(action: openModsFolder) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("Open Folder")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Theme.bgMedium)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
                .colorScheme(.dark)
            Text("Loading Workshop mods...")
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted)
            Text("No Mods Found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            Text(Paths.workshopMods == nil
                 ? "Workshop mods only load from a Steam library copy of the game.\nThis copy isn't in one, so there's nothing to list."
                 : "Subscribe to mods on the Steam Workshop\nand they'll show up here.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
            if Paths.workshopMods != nil {
                Button("Open Mods Folder") { openModsFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.orange)
                    .padding(.top, 4)
            }
            Spacer()
        }
    }

    private var modList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredMods) { mod in
                    modRow(mod)
                }
            }
            .padding(16)
        }
    }

    private func modRow(_ mod: ModEntry) -> some View {
        let item = workshopInfo[mod.workshopID]
        let title = item?.title ?? mod.workshopID

        return HStack(spacing: 16) {
            Button(action: {
                if let item { NSWorkspace.shared.open(item.workshopURL) }
            }) {
                HStack(spacing: 16) {
                    thumbnailView(item?.previewURL)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)
                        Text("ID: \(mod.workshopID)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.textMuted)
                    }

                    Spacer()

                    Text(mod.sizeOnDisk)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.textSecondary)

                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textMuted)
                }
            }
            .buttonStyle(.plain)
            .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

            Button(action: { deleteMod(mod) }) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.red.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.bgMedium)
        .cornerRadius(6)
    }

    private func deleteMod(_ mod: ModEntry) {
        let item = workshopInfo[mod.workshopID]
        let name = item?.title ?? mod.workshopID

        // Deleting the folder while Steam is closed does nothing lasting: Steam
        // re-downloads every subscribed item the next time it starts. Unsubscribing
        // is the only thing that sticks, and that needs Steam running.
        guard SteamWorkshop.isSteamRunning else {
            let alert = NSAlert()
            alert.messageText = "Open Steam First"
            alert.informativeText = "Steam isn't running. If you delete this mod now, Steam will download it again the next time you open it, along with everything else you're subscribed to.\n\nOpen Steam, then unsubscribe from \"\(name)\" so it stays gone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Steam")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                SteamWorkshop.launchSteam()
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete \"\(name)\"?"
        alert.informativeText = "This unsubscribes you on Steam and permanently deletes the \(mod.sizeOnDisk) of files. It does not go to the Trash and can't be undone.\n\nYou can resubscribe on the Workshop later if you change your mind."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Unsubscribe & Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if case let .failure(error) = SteamUnsubscriber.unsubscribe(id: mod.workshopID) {
            let failure = NSAlert()
            failure.messageText = "Couldn't Unsubscribe"
            failure.informativeText = "\(error.localizedDescription)\n\nNothing was deleted. Deleting the files while you're still subscribed would just make Steam download them again."
            failure.alertStyle = .critical
            failure.runModal()
            return
        }

        // Steam usually clears the folder itself once the unsubscribe lands.
        // removeItem is a permanent delete, not a move to the Trash.
        try? FileManager.default.removeItem(atPath: mod.path)
        mods.removeAll { $0.id == mod.id }
        refreshStorage()
    }

    private func refreshStorage() {
        storage = StorageInfo.load(modsBytes: mods.reduce(0) { $0 + $1.byteSize })
    }

    @ViewBuilder
    private func thumbnailView(_ urlString: String?) -> some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .cornerRadius(6)
                        .clipped()
                default:
                    placeholderThumb
                }
            }
        } else {
            placeholderThumb
        }
    }

    private var placeholderThumb: some View {
        Image(systemName: "puzzlepiece.fill")
            .font(.system(size: 18))
            .foregroundColor(Theme.orange)
            .frame(width: 48, height: 48)
            .background(Theme.bgLight)
            .cornerRadius(6)
    }

    private func openModsFolder() {
        guard let modsPath = Paths.workshopMods,
              FileManager.default.fileExists(atPath: modsPath) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: modsPath))
    }
}

struct ModEntry: Identifiable {
    let id = UUID()
    let workshopID: String
    let path: String
    let byteSize: Int64

    var sizeOnDisk: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }

    static func scan() -> [ModEntry] {
        guard let modsPath = Paths.workshopMods,
              FileManager.default.fileExists(atPath: modsPath),
              let contents = try? FileManager.default.contentsOfDirectory(atPath: modsPath) else {
            return []
        }
        var isDir: ObjCBool = false
        return contents
            .filter { !$0.hasPrefix(".") }
            .filter {
                FileManager.default.fileExists(atPath: modsPath + "/" + $0, isDirectory: &isDir)
                return isDir.boolValue
            }
            .map { ModEntry(workshopID: $0, path: modsPath + "/" + $0, byteSize: Self.folderSize(modsPath + "/" + $0)) }
    }

    private static func folderSize(_ path: String) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            let full = path + "/" + file
            if let attrs = try? fm.attributesOfItem(atPath: full),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }
}
