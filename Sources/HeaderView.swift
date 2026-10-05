import SwiftUI

struct HeaderView: View {
    @Binding var selectedTab: LauncherTab
    var showDownloadAction: Bool = false
    @ObservedObject private var controller = ControllerManager.shared
    @ObservedObject private var downloader = GameDownloader.shared

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(Theme.divider)
            navBar
            Divider().background(Theme.divider)
        }
        .background(Theme.headerBg)
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            logoBlock
            Spacer()
            HStack(spacing: 16) {
                if showDownloadAction {
                    downloadStatusBadge
                } else {
                    installTypeBadge

                    Text(GameLauncher.gameVersion)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)

                    playButton
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var logoBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("CALL")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(Theme.textPrimary)
                Text("OF")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(Theme.textPrimary)
                    .baselineOffset(6)
                    .padding(.horizontal, 3)
                Text("DUTY")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(Theme.textPrimary)
            }
            HStack(spacing: 6) {
                Text("BLACK OPS")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(Theme.textPrimary)
                Text("III")
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(Theme.orange)
                Text("for macOS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
                    .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private var installTypeBadge: some View {
        switch Paths.installType {
        case .nonSteam:
            Text("NON-STEAM")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(Theme.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.orange.opacity(0.12))
                .cornerRadius(3)
        case .steam, .none:
            EmptyView()
        }
    }

    @State private var offlineMode = GameLauncher.launchWithoutSteam

    private var playButton: some View {
        HStack(spacing: 8) {
            if controller.isConnected {
                controllerHint
            }

            Button(action: {
                let isNonSteam = Paths.installType == .nonSteam
                offlineMode = isNonSteam
                GameLauncher.launchWithoutSteam = isNonSteam
                GameLauncher.launch()
            }) {
                Text("PLAY")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 120, height: 42)
                    .background(Theme.orange)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .cursorHand()

            Button(action: {
                offlineMode = true
                GameLauncher.launchWithoutSteam = true
                GameLauncher.launch()
            }) {
                Text("OFFLINE")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 72, height: 42)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .cursorHand()
            .help("Launch without Steam — no downloads, no updates, just play")
        }
        .onAppear {
            controller.onAction = { GameLauncher.launch() }
        }
    }

    private var controllerHint: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(controller.controllerType == .playstation
                          ? Color(red: 0.15, green: 0.35, blue: 0.65)
                          : Color(red: 0.15, green: 0.55, blue: 0.15))
                    .frame(width: 26, height: 26)

                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 26, height: 26)

                Text(controller.buttonLabel)
                    .font(.system(size: controller.controllerType == .playstation ? 16 : 14, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .animation(.easeInOut(duration: 0.2), value: controller.isConnected)
    }

    private var navBar: some View {
        HStack(spacing: 0) {
            ForEach(LauncherTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer()
            optionsMenu
        }
        .padding(.horizontal, 24)
    }

    private func tabButton(_ tab: LauncherTab) -> some View {
        Button(action: { selectedTab = tab }) {
            Text(tab.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(selectedTab == tab ? Theme.orange : Theme.textSecondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .cursorHand()
    }

    private var downloadStatusBadge: some View {
        Group {
            switch downloader.phase {
            case .idle:
                Text("GAME NOT INSTALLED")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(Theme.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.orange.opacity(0.15))
                    .cornerRadius(4)
            case .downloading:
                HStack(spacing: 8) {
                    ProgressView(value: downloader.overallProgress)
                        .progressViewStyle(.linear)
                        .tint(Theme.orange)
                        .frame(width: 80)
                    Text("\(downloader.completedChunkCount)/\(downloader.totalChunkCount)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                    if !downloader.speedText.isEmpty {
                        Text(downloader.speedText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.orange)
                    }
                }
            case .paused:
                HStack(spacing: 6) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.orange)
                    Text("PAUSED \(downloader.completedChunkCount)/\(downloader.totalChunkCount)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(Theme.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.orange.opacity(0.15))
                .cornerRadius(4)
            case .decompressing:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Theme.orange)
                    Text("Extracting...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
            case .finished:
                Text("DOWNLOAD COMPLETE")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.green)
            default:
                EmptyView()
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Button("Open Game Folder") {
                let url = URL(fileURLWithPath: Paths.bo3Root)
                if FileManager.default.fileExists(atPath: Paths.bo3Root) {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Change Game Folder...") {
                _ = Paths.promptForGameFolder()
            }
            if Paths.isUsingCustomPath {
                Button("Reset to Default Path") {
                    Paths.resetToDefault()
                }
            }
            Divider()
            if Paths.installType == .none {
                Button("Download Game...") {
                    downloader.startDownload(to: Paths.nonSteamParent)
                }
            }
            if !MacFixInstaller.isInstalled {
                Button("Install BO3MacFix...") {
                    MacFixInstaller.promptInstallIfNeeded()
                }
            }
            Divider()
            if GameLauncher.isSteamIntegrated {
                Button("Remove Steam Integration") {
                    GameLauncher.uninstallSteamIntegration()
                }
            } else if Paths.installType == .steam {
                Button("Install Steam Integration...") {
                    GameLauncher.installSteamIntegration()
                }
            }
            Divider()
            Button("Check for Updates") {
                UpdateChecker.checkForUpdates()
            }
            Button("About") { NSApp.orderFrontStandardAboutPanel(nil) }
        } label: {
            Text("Options")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
        }
        .menuStyle(.borderlessButton)
    }
}

enum LauncherTab: String, CaseIterable, Identifiable {
    case whatsNew = "What's New"
    case dlc = "Downloadable Content"
    case mods = "Mods"

    var id: String { rawValue }
    var title: String { rawValue }
}
