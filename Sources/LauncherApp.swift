import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuObserver: Any?

    /// Runs before the window is built, so ContentView sees a resolved path.
    func applicationWillFinishLaunching(_ notification: Notification) {
        Paths.autoDetectIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        stripMenuBar()
        AccountGate.enforce()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            PermissionChecker.promptIfNeeded()
            MacFixInstaller.promptInstallIfNeeded()
            GameLauncher.resumeSteamIntegrationIfNeeded()
        }
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification,
            object: NSApp.mainMenu,
            queue: .main
        ) { [weak self] _ in self?.stripMenuBar() }
    }

    private func stripMenuBar() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let removeTitles: Set<String> = ["File", "Edit", "View", "Window", "Format"]
        for item in mainMenu.items {
            let title = item.submenu?.title ?? item.title
            if removeTitles.contains(title) {
                mainMenu.removeItem(item)
            }
        }

        if let appMenu = mainMenu.items.first?.submenu {
            let keep = appMenu.items.filter {
                $0.title.lowercased().contains("about") ||
                $0.title.lowercased().contains("quit") ||
                ($0.isSeparatorItem && $0 == appMenu.items.last(where: { $0.isSeparatorItem }))
            }
            appMenu.removeAllItems()
            for item in keep { appMenu.addItem(item) }
        }
    }
}

@main
struct LauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 1024, height: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1024, height: 640)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .help) {
                Button("BO3 Community Discord") {
                    NSWorkspace.shared.open(URL(string: "https://discord.gg/2dw7A7p3cA")!)
                }
            }
        }
    }
}
