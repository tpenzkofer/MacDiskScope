import SwiftUI

struct InfoPanelView: View {
    let node: FileNode
    let rootSize: Int64

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: node.isDirectory ? "folder.fill" : iconName)
                    .foregroundColor(node.isDirectory ? .accentColor : .secondary)
                    .font(.title3)
                Text(node.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(FormatUtils.formatBytes(node.size))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Stats grid
            ScrollView {
                VStack(spacing: 1) {
                    if node.isDirectory {
                        directoryStats
                    } else {
                        fileStats
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Directory stats

    @ViewBuilder
    private var directoryStats: some View {
        statRow("Files", FormatUtils.formatCount(node.fileCount))
        statRow("Folders", FormatUtils.formatCount(node.subDirCount))
        statRow("Total items", FormatUtils.formatCount(node.fileCount + node.subDirCount))
        statRow("Tree depth", "\(node.depth) level\(node.depth == 1 ? "" : "s")")

        Divider().padding(.vertical, 4)

        statRow("% of scanned", FormatUtils.percentString(node.size, of: rootSize))
        statRow("Avg file size", FormatUtils.formatBytes(node.averageFileSize))

        if let largest = node.largestFile() {
            statRow("Largest file", "\(largest.name) (\(FormatUtils.formatBytes(largest.size)))")
        }

        let extCount = node.uniqueExtensionCount()
        statRow("File types", "\(extCount) unique extension\(extCount == 1 ? "" : "s")")

        Divider().padding(.vertical, 4)

        // Top 5 extensions
        let topExts = Array(node.collectExtensionStats()
            .sorted { $0.value > $1.value }
            .prefix(5))
        if !topExts.isEmpty {
            HStack {
                Text("Top extensions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)

            ForEach(topExts, id: \.key) { ext, size in
                HStack(spacing: 6) {
                    Circle()
                        .fill(FileTypeColorMap.color(for: ext))
                        .frame(width: 8, height: 8)
                    Text(".\(ext)")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 70, alignment: .leading)
                    Text(FormatUtils.formatBytes(size))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(FormatUtils.percentString(size, of: node.size))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }
        }

        Divider().padding(.vertical, 4)

        if let oldest = node.oldestDate {
            statRow("Oldest file", Self.dateFormatter.string(from: oldest)
                    + " (\(Self.relativeDateFormatter.localizedString(for: oldest, relativeTo: Date())))")
        }
        if let newest = node.newestDate {
            statRow("Newest file", Self.dateFormatter.string(from: newest)
                    + " (\(Self.relativeDateFormatter.localizedString(for: newest, relativeTo: Date())))")
        }

        statRow("Path", node.path)
    }

    // MARK: - File stats

    @ViewBuilder
    private var fileStats: some View {
        statRow("Size", FormatUtils.formatBytes(node.size))
        statRow("% of scanned", FormatUtils.percentString(node.size, of: rootSize))

        if !node.fileExtension.isEmpty {
            HStack(spacing: 6) {
                Text("Type")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
                Circle()
                    .fill(FileTypeColorMap.color(for: node.fileExtension))
                    .frame(width: 8, height: 8)
                Text(".\(node.fileExtension)")
                    .font(.system(.caption, design: .monospaced))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }

        if let date = node.modificationDate {
            statRow("Modified", Self.dateFormatter.string(from: date)
                    + " (\(Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())))")
        }

        statRow("Path", node.path)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch node.fileExtension {
        case "swift", "py", "js", "ts", "c", "cpp", "h", "m", "rs", "go", "java", "rb":
            return "doc.text"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "svg", "webp":
            return "photo"
        case "mp4", "avi", "mkv", "mov", "wmv":
            return "film"
        case "mp3", "wav", "flac", "aac", "m4a":
            return "music.note"
        case "zip", "tar", "gz", "rar", "7z", "dmg":
            return "archivebox"
        case "pdf":
            return "doc.richtext"
        default:
            return "doc"
        }
    }
}

// MARK: - Multi-selection summary

struct MultiSelectionInfoView: View {
    let nodes: [FileNode]
    let rootSize: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                Text("\(nodes.count) items selected")
                    .font(.headline)
                Spacer()
                Text(FormatUtils.formatBytes(totalSize))
                    .font(.system(.title3, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 1) {
                    statRow("Total size", FormatUtils.formatBytes(totalSize))
                    statRow("% of scanned", FormatUtils.percentString(totalSize, of: rootSize))
                    statRow("Files", FormatUtils.formatCount(fileCount))
                    statRow("Folders", FormatUtils.formatCount(dirCount))
                    statRow("Total items", FormatUtils.formatCount(totalItems))

                    if let largest = nodes.max(by: { $0.size < $1.size }) {
                        statRow("Largest", "\(largest.name) (\(FormatUtils.formatBytes(largest.size)))")
                    }
                    if let smallest = nodes.filter({ $0.size > 0 }).min(by: { $0.size < $1.size }) {
                        statRow("Smallest", "\(smallest.name) (\(FormatUtils.formatBytes(smallest.size)))")
                    }

                    statRow("Avg size", FormatUtils.formatBytes(fileCount > 0 ? totalSize / Int64(fileCount) : 0))

                    let extCount = Set(nodes.compactMap { $0.isDirectory ? nil : ($0.fileExtension.isEmpty ? nil : $0.fileExtension) }).count
                    if extCount > 0 {
                        statRow("File types", "\(extCount) unique extension\(extCount == 1 ? "" : "s")")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var totalSize: Int64 { nodes.reduce(0) { $0 + $1.size } }
    private var fileCount: Int {
        nodes.reduce(0) { $0 + ($1.isDirectory ? $1.fileCount : 1) }
    }
    private var dirCount: Int {
        nodes.reduce(0) { $0 + ($1.isDirectory ? 1 + $1.subDirCount : 0) }
    }
    private var totalItems: Int { fileCount + dirCount }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }
}
