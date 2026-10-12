import AppKit
import SwiftUI

/// Covers the screen between launching the game and its first window appearing.
/// That gap is a minute or more of pure black with no sign the game is alive,
/// which reads as a failed launch.
///
/// The overlay sits above everything, so it always offers a way out: it clears
/// itself when the game's window shows up, when the game exits, on Esc or a
/// click, and on a hard timeout if window detection ever fails.
@MainActor
final class LoadingOverlay {
    static let shared = LoadingOverlay()

    private var windows: [NSWindow] = []
    private var poll: Timer?
    private var keyMonitor: Any?
    private var deadline = Date.distantPast

    private let timeout: TimeInterval = 240

    private init() {}

    var isShowing: Bool { !windows.isEmpty }

    func show() {
        guard windows.isEmpty else { return }
        deadline = Date().addingTimeInterval(timeout)

        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame,
                                  styleMask: .borderless,
                                  backing: .buffered,
                                  defer: false)
            window.level = .screenSaver
            window.isOpaque = true
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = false
            window.contentView = NSHostingView(rootView: LoadingOverlayView { [weak self] in
                self?.dismiss()
            })
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.dismiss()
                return nil
            }
            return event
        }

        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func dismiss() {
        poll?.invalidate()
        poll = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
    }

    private func tick() {
        if Date() >= deadline || Self.gameWindowIsUp() {
            dismiss()
        }
    }

    /// Owner name is readable without the screen-recording permission that
    /// window titles require, so match on that.
    private static func gameWindowIsUp() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        for window in list {
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner.contains("Black Ops III"),
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double
            else { continue }
            if width > 150 && height > 150 { return true }
        }
        return false
    }
}

private struct LoadingOverlayView: View {
    let onDismiss: () -> Void

    @State private var sweep: CGFloat = -1

    var body: some View {
        ZStack {
            Theme.bgDark.ignoresSafeArea()

            VStack(spacing: 22) {
                Text("LOADING")
                    .font(.system(size: 34, weight: .heavy, design: .default))
                    .tracking(14)
                    .foregroundColor(Theme.orange)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.bgLight)
                        Rectangle()
                            .fill(Theme.orange)
                            .frame(width: geo.size.width * 0.3)
                            .offset(x: sweep * geo.size.width)
                    }
                    .clipped()
                }
                .frame(width: 320, height: 3)

                Text("Black Ops III can sit on a black screen for a minute or two before it opens.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)

                Text("Press Esc or click to hide this")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
    }
}
