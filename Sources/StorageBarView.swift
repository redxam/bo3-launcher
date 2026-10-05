import SwiftUI

/// Segmented bar showing how the game drive is being used.
struct StorageBarView: View {
    let info: StorageInfo

    private var segments: [(label: String, bytes: Int64, color: Color)] {
        [
            ("Game", info.game, Theme.orange),
            ("Mods", info.mods, Color(red: 0.45, green: 0.62, blue: 0.85)),
            ("Other", info.other, Theme.bgLight),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text(info.volumeName.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(Theme.textMuted)

                Spacer()

                Text("\(StorageInfo.format(info.free)) free of \(StorageInfo.format(info.total))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(info.free < 10_000_000_000 ? Theme.orange : Theme.textSecondary)
            }

            bar

            HStack(spacing: 16) {
                ForEach(segments, id: \.label) { segment in
                    legendItem(segment.label, segment.bytes, segment.color)
                }
                legendItem("Free", info.free, Theme.bgMedium)
                Spacer()
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Theme.headerBg)
    }

    private var bar: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments, id: \.label) { segment in
                    segment.color
                        .frame(width: width(for: segment.bytes, in: geo.size.width))
                }
                Theme.bgMedium
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 10)
    }

    private func width(for bytes: Int64, in totalWidth: CGFloat) -> CGFloat {
        guard info.total > 0 else { return 0 }
        let fraction = CGFloat(bytes) / CGFloat(info.total)
        // Keep non-zero slices visible rather than collapsing to a hairline.
        return max(fraction * totalWidth, bytes > 0 ? 3 : 0)
    }

    private func legendItem(_ label: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
            Text(StorageInfo.format(bytes))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
        }
    }
}
