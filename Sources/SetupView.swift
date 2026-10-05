import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// First-run screen. The user points the launcher at their copy of the game by
/// dragging the folder in, which works regardless of which drive it lives on.
struct SetupView: View {
    /// Called once a valid game folder has been stored.
    var onGameFound: () -> Void

    @State private var isTargeted = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if Paths.savedPathIsMissing {
                missingDriveNotice
                    .padding(.bottom, 28)
            }

            dropZone
                .padding(.horizontal, 48)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red.opacity(0.9))
                    .padding(.top, 14)
            }

            instructions
                .padding(.top, 36)

            Button("Choose Folder Manually...") {
                if Paths.promptForGameFolder() { onGameFound() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.textSecondary)
            .cursorHand()
            .padding(.top, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgDark)
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "folder.fill")
                .font(.system(size: 44))
                .foregroundColor(isTargeted ? Theme.orangeHover : Theme.orange)

            Text("Drag your Black Ops III folder here")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text("The folder containing CoDBlkOps3.app, on any drive")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .background(isTargeted ? Theme.bgLight : Theme.bgMedium)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isTargeted ? Theme.orangeHover : Theme.divider,
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [7, 5])
                )
        )
        .cornerRadius(6)
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        // `dropDestination(for: URL.self)` drops Finder file URLs on the floor here,
        // so read the file-URL provider directly instead.
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { handleDrop(url) }
            }
            return true
        }
    }

    private func handleDrop(_ url: URL) {
        switch Paths.acceptDroppedGameFolder(url) {
        case .accepted:
            errorMessage = nil
            onGameFound()
        case .wrongFolder:
            errorMessage = "\"\(url.lastPathComponent)\" doesn't contain CoDBlkOps3.app. Drag the folder the game itself is in."
        case .notAFolder:
            errorMessage = "Drag a folder, not a file."
        }
    }

    // MARK: - Instructions

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE TO FIND IT")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(Theme.textMuted)
                .padding(.bottom, 2)

            step(1, "In Steam, right-click Call of Duty: Black Ops III")
            step(2, "Choose Manage, then Browse local files")
            step(3, "Drag the folder that opens into the box above")
        }
        .frame(width: 420, alignment: .leading)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(Theme.orange)
                .frame(width: 18, height: 18)
                .background(Theme.orange.opacity(0.12))
                .cornerRadius(3)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Unmounted drive

    private var missingDriveNotice: some View {
        VStack(spacing: 6) {
            Text("Your game folder isn't reachable")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text(Paths.savedPath.map { "Last seen at \($0)" } ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textMuted)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("If it's on an external drive, plug it in and reopen the launcher.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(width: 480)
    }
}
