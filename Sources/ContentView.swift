import SwiftUI

struct ContentView: View {
    @State private var selectedTab: LauncherTab = .whatsNew
    @ObservedObject private var downloader = GameDownloader.shared
    @State private var installType = Paths.installType

    var body: some View {
        VStack(spacing: 0) {
            if installType == .none {
                HeaderView(selectedTab: $selectedTab, showDownloadAction: true)
                SetupView { installType = Paths.installType }
            } else if showDownloadView {
                HeaderView(selectedTab: $selectedTab, showDownloadAction: true)
                DownloadView()
            } else {
                HeaderView(selectedTab: $selectedTab, showDownloadAction: false)

                switch selectedTab {
                case .whatsNew:
                    WhatsNewView()
                case .dlc:
                    PlaceholderTabView(title: "Downloadable Content", icon: "arrow.down.circle.fill")
                case .mods:
                    ModsView()
                }
            }
        }
        .background(Theme.bgDark)
        .onAppear { installType = Paths.installType }
        .onChange(of: downloader.phase) { _, newPhase in
            if case .finished = newPhase {
                installType = Paths.installType
            }
        }
    }

    private var showDownloadView: Bool {
        switch downloader.phase {
        case .idle, .finished:
            return false
        default:
            return true
        }
    }
}

struct PlaceholderTabView: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(Theme.textMuted)
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            Text("Coming soon")
                .font(.system(size: 14))
                .foregroundColor(Theme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgDark)
    }
}
