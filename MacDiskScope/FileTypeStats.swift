import SwiftUI

struct FileTypeStatsView: View {
    let stats: [(ext: String, size: Int64)]
    let totalSize: Int64

    @State private var hoveredExt: String?

    private var displayStats: [(ext: String, size: Int64)] {
        Array(stats.prefix(50))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("File Types")
                    .font(.headline)
                Spacer()
                Text("\(stats.count) types")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Column headers
            HStack(spacing: 0) {
                Text("")
                    .frame(width: 14)
                Text("Extension")
                    .frame(width: 90, alignment: .leading)
                Text("Size")
                    .frame(width: 80, alignment: .trailing)
                Text("%")
                    .frame(width: 50, alignment: .trailing)
                Text("")
                    .frame(maxWidth: .infinity)
            }
            .font(.system(.caption, design: .default).weight(.medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            // Stats list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayStats, id: \.ext) { stat in
                        FileTypeRow(ext: stat.ext, size: stat.size, totalSize: totalSize, isHovered: hoveredExt == stat.ext)
                            .onHover { isHovering in
                                hoveredExt = isHovering ? stat.ext : nil
                            }
                    }
                }
            }
        }
    }
}

private struct FileTypeRow: View {
    let ext: String
    let size: Int64
    let totalSize: Int64
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Color dot
            Circle()
                .fill(FileTypeColorMap.color(for: ext))
                .frame(width: 10, height: 10)
                .frame(width: 14)

            // Extension name
            Text(".\(ext)")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)

            // Size
            Text(FormatUtils.formatBytes(size))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 80, alignment: .trailing)

            // Percentage
            Text(FormatUtils.percentString(size, of: totalSize))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 50, alignment: .trailing)

            // Bar
            GeometryReader { geo in
                let fraction = totalSize > 0 ? CGFloat(size) / CGFloat(totalSize) : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(FileTypeColorMap.color(for: ext).opacity(0.5))
                    .frame(width: geo.size.width * min(fraction, 1.0))
            }
            .frame(height: 10)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}
