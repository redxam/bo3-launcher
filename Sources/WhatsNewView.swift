import SwiftUI

struct WhatsNewView: View {
    var body: some View {
        HStack(spacing: 0) {
            mainBanner
            sidePanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgDark)
    }

    private var mainBanner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.18, green: 0.22, blue: 0.12),
                    Color(red: 0.12, green: 0.14, blue: 0.08),
                    Theme.bgDark,
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 0) {
                        Image(systemName: "scope")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.orange)
                            .padding(.trailing, 8)
                        Text("by redxam gaming")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(Theme.orange)
                    }

                    Text("YOUR GAME,\nYOUR RULES")
                        .font(.system(size: 36, weight: .black))
                        .foregroundColor(Theme.textPrimary)
                        .lineSpacing(2)

                    Text("Launch with custom mods, configs, and tweaks.\nTake full control of your Black Ops III experience.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .lineSpacing(4)

                    actionButton("LAUNCH GAME", icon: "play.fill") {
                        GameLauncher.launch()
                    }
                    .padding(.top, 8)
                }
                .padding(32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .heavy))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Theme.orange)
            .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .cursorHand()
    }

    private var sidePanel: some View {
        VStack(spacing: 2) {
            changelogCard

            sideCard(
                title: "ZOMBIES",
                subtitle: "Survive the undead",
                icon: "figure.walk",
                gradient: [Color(red: 0.15, green: 0.18, blue: 0.12), Color(red: 0.10, green: 0.12, blue: 0.08)],
                clickable: true,
                action: { GameLauncher.launch() }
            )

            sideCard(
                title: "WORKSHOP",
                subtitle: "Browse & download mods",
                icon: "wrench.and.screwdriver.fill",
                gradient: [Color(red: 0.18, green: 0.15, blue: 0.22), Color(red: 0.10, green: 0.08, blue: 0.14)],
                clickable: true,
                action: {
                    NSWorkspace.shared.open(URL(string: "https://steamcommunity.com/app/311210/workshop/")!)
                }
            )
        }
        .frame(width: 280)
    }

    private var changelogCard: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.25, green: 0.20, blue: 0.12), Color(red: 0.15, green: 0.12, blue: 0.08)],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.orange)
                        Text(GameLauncher.gameVersion)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(Theme.textPrimary)
                    }

                    changelogItem("Game audio follows your Mac's output device, switch to headphones mid-game")
                    changelogItem("PlayStation button prompts and controller diagrams")
                    changelogItem("Rumble for up to four DualSense controllers")
                    changelogItem("Loading screen over the black gap at startup")
                    changelogItem("Non-Steam installation, download and play without Steam")

                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.vertical, 2)

                    Text("COMING NEXT")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(Theme.textMuted)

                    changelogItem("Injector integration for non-Steam launch", pending: true)
                    changelogItem("Custom launch arguments", pending: true)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func changelogItem(_ text: String, pending: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: pending ? "circle" : "checkmark.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(pending ? Theme.textMuted : Theme.orange)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(pending ? Theme.textMuted : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sideCard(title: String, subtitle: String, icon: String, gradient: [Color], clickable: Bool, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: gradient, startPoint: .topTrailing, endPoint: .bottomLeading)

            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(clickable ? Theme.orange : Theme.textMuted)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundColor(clickable ? Theme.textPrimary : Theme.textMuted)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textMuted)
                }

                Spacer()

                if clickable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Theme.textMuted)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if clickable { action() } }
        .onHover { h in
            if clickable {
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}
