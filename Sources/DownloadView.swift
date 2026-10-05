import SwiftUI

struct DownloadView: View {
    @ObservedObject private var downloader = GameDownloader.shared
    @State private var selectedFolder: String = Paths.nonSteamParent
    private let concurrency: Int = 5

    private var partialChunkCount: Int {
        downloader.partialDownloadCount()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            content
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgDark)
        .onAppear {
            if let saved = downloader.loadSavedDestination() {
                selectedFolder = saved
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch downloader.phase {
        case .idle:
            idleView
        case .fetchingManifest:
            spinnerView(title: "Connecting...", subtitle: "Fetching game manifest from server")
        case .downloading:
            downloadingView
        case .paused:
            pausedView
        case .decompressing:
            spinnerView(
                title: "Extracting",
                subtitle: "Decompressing game files — this may take several minutes\n(\(downloader.decompressedChunkCount)/\(downloader.totalChunkCount) chunks processed)"
            )
        case .finished:
            finishedView
        case let .failed(message):
            failedView(message: message)
        }
    }

    // MARK: - Idle (Install Prompt)

    private var idleView: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56))
                .foregroundColor(Theme.orange)

            VStack(spacing: 8) {
                Text(partialChunkCount > 0 ? "Installation In Progress" : "No Game Detected")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                if partialChunkCount > 0 {
                    Text("\(partialChunkCount) chunks already downloaded.\nPress Install to continue where you left off.")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                } else {
                    Text("Would you like to install the non-Steam version\nof Black Ops III? (~69 GB compressed)")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }

            VStack(spacing: 14) {
                folderSelector

                Button(action: { beginDownload() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 14, weight: .semibold))
                        Text("INSTALL GAME")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundColor(.white)
                    .frame(width: 340, height: 44)
                    .background(Theme.orange)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .cursorHand()
            }
        }
        .padding(48)
    }

    private var folderSelector: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundColor(Theme.textMuted)

            Text(displayPath(selectedFolder))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)

            Spacer()

            Button("Browse...") { pickFolder() }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.orange)
                .buttonStyle(.plain)
                .cursorHand()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.bgMedium)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.divider, lineWidth: 1))
        .frame(width: 400)
    }

    private func concurrencyStepper(value: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            Text("Parallel Downloads")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textSecondary)

            Spacer()

            HStack(spacing: 0) {
                Button(action: { if value.wrappedValue > 1 { value.wrappedValue -= 1 } }) {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(value.wrappedValue > 1 ? Theme.textSecondary : Theme.textMuted.opacity(0.4))
                        .frame(width: 32, height: 28)
                        .background(Color.white.opacity(0.06))
                }
                .buttonStyle(.plain)
                .cursorHand()
                .disabled(value.wrappedValue <= 1)

                Text("\(value.wrappedValue)")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 28)
                    .background(Theme.orange)

                Button(action: { value.wrappedValue += 1 }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 32, height: 28)
                        .background(Color.white.opacity(0.06))
                }
                .buttonStyle(.plain)
                .cursorHand()
            }
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
        .frame(width: 400)
    }

    // MARK: - Downloading

    private var downloadingView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Downloading")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                Text("\(downloader.completedChunkCount) of \(downloader.totalChunkCount) chunks complete")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }

            VStack(spacing: 8) {
                let sortedActive = downloader.activeChunkProgress
                    .sorted { $0.key < $1.key }

                ForEach(sortedActive, id: \.key) { index, progress in
                    chunkProgressBar(progress: progress, label: "Chunk \(index)")
                }

                overallProgressBar

                HStack {
                    Text(formatBytes(downloader.downloadedBytes))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                    if !downloader.speedText.isEmpty {
                        Text(downloader.speedText)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.orange)
                    }
                    Spacer()
                    Text(formatBytes(downloader.totalBytes))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                }
            }
            .frame(width: 400)

            concurrencyStepper(value: liveConcurrencyBinding)

            HStack(spacing: 12) {
                Button(action: { downloader.pause() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11))
                        Text("Pause")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .cursorHand()

                Button(action: { downloader.cancel() }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .cursorHand()
            }
        }
        .padding(48)
    }

    // MARK: - Paused

    private var pausedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(Theme.orange)

            VStack(spacing: 8) {
                Text("Download Paused")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                Text("\(downloader.completedChunkCount) of \(downloader.totalChunkCount) chunks downloaded")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textSecondary)

                Text(formatBytes(downloader.downloadedBytes) + " of " + formatBytes(downloader.totalBytes))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
            }

            overallProgressBar
                .frame(width: 400)

            HStack(spacing: 16) {
                Button(action: { downloader.resume() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Resume")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundColor(.white)
                    .frame(width: 140, height: 40)
                    .background(Theme.orange)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .cursorHand()

                Button(action: { downloader.cancel() }) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 120, height: 40)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .cursorHand()
            }
        }
        .padding(48)
    }

    // MARK: - Finished

    private var finishedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("Installation Complete")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text("Black Ops III has been downloaded and extracted.\nYou can now install BO3MacFix and play.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button(action: {
                downloader.phase = .idle
                MacFixInstaller.promptInstallIfNeeded()
            }) {
                Text("INSTALL BO3MACFIX & PLAY")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 280, height: 44)
                    .background(Theme.orange)
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .cursorHand()
        }
        .padding(48)
    }

    // MARK: - Failed

    private func failedView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Download Failed")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 16) {
                Button(action: { beginDownload() }) {
                    Text("Retry")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 120, height: 36)
                        .background(Theme.orange)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .cursorHand()

                Button(action: { downloader.cancel() }) {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 120, height: 36)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .cursorHand()
            }
        }
        .padding(48)
    }

    // MARK: - Shared Components

    private func chunkProgressBar(progress: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.orange)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.bgLight)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.orange)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))))
                }
            }
            .frame(height: 8)
        }
    }

    private var overallProgressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Overall")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Text("\(Int(downloader.overallProgress * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.orange)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.bgLight)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.orange.opacity(0.7))
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, downloader.overallProgress))))
                }
            }
            .frame(height: 6)
        }
    }

    private func spinnerView(title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.2)
                .tint(Theme.orange)

            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(48)
    }

    private var liveConcurrencyBinding: Binding<Int> {
        Binding(
            get: { downloader.concurrentSlots },
            set: { downloader.setConcurrency($0) }
        )
    }

    // MARK: - Actions

    private func beginDownload() {
        downloader.startDownload(to: selectedFolder, concurrency: concurrency)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Install Location"
        panel.message = "Select where to install Black Ops III.\nA \"Call of Duty Black Ops III\" folder will be created here."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: selectedFolder)

        if panel.runModal() == .OK, let url = panel.url {
            selectedFolder = url.path
        }
    }

    // MARK: - Formatting

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Cursor Helper

extension View {
    func cursorHand() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
