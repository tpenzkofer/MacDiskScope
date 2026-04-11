import Foundation

final class FileNode: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let fileExtension: String

    var size: Int64 = 0
    var children: [FileNode] = []
    var fileCount: Int = 0

    weak var parent: FileNode?

    var allocatedSize: Int64 = 0
    var modificationDate: Date?
    var oldestDate: Date?
    var newestDate: Date?
    var subDirCount: Int = 0
    var depth: Int = 0          // max depth of subtree (0 for files, 1 for flat dirs)

    // Cached sorted children — invalidated when children changes
    private var _sortedBySize: [FileNode]?

    init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.fileExtension = isDirectory ? "" : (name as NSString).pathExtension.lowercased()
    }

    var totalSize: Int64 { size }

    /// Pre-sorted and filtered children for display. Cached after first call.
    var sortedBySize: [FileNode] {
        if let cached = _sortedBySize { return cached }
        let result = children
            .filter { $0.isDirectory || $0.size > 0 }
            .sorted { $0.size > $1.size }
        _sortedBySize = result
        return result
    }

    func invalidateSortCache() {
        _sortedBySize = nil
    }

    func updateSizeFromChildren() {
        guard isDirectory else { return }
        var total: Int64 = 0
        var fCount = 0
        var dCount = 0
        var maxDepth = 0
        var oldest: Date?
        var newest: Date?
        for child in children {
            total += child.size
            if child.isDirectory {
                fCount += child.fileCount
                dCount += 1 + child.subDirCount
                maxDepth = max(maxDepth, 1 + child.depth)
            } else {
                fCount += 1
            }
            let childOldest = child.isDirectory ? child.oldestDate : child.modificationDate
            let childNewest = child.isDirectory ? child.newestDate : child.modificationDate
            if let co = childOldest {
                if oldest == nil || co < oldest! { oldest = co }
            }
            if let cn = childNewest {
                if newest == nil || cn > newest! { newest = cn }
            }
        }
        size = total
        fileCount = fCount
        subDirCount = dCount
        depth = maxDepth
        oldestDate = oldest
        newestDate = newest
        invalidateSortCache()
    }

    /// Find the single largest file in this subtree
    func largestFile() -> FileNode? {
        if !isDirectory { return self }
        var best: FileNode?
        for child in children {
            let candidate = child.largestFile()
            if let c = candidate {
                if best == nil || c.size > best!.size { best = c }
            }
        }
        return best
    }

    /// Average file size in this subtree
    var averageFileSize: Int64 {
        guard fileCount > 0 else { return 0 }
        return size / Int64(fileCount)
    }

    /// Count of unique extensions in this subtree
    func uniqueExtensionCount() -> Int {
        collectExtensionStats().count
    }

    func sortedChildren(by comparator: SortComparator = .size) -> [FileNode] {
        switch comparator {
        case .size:
            return sortedBySize
        case .name:
            return children.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .fileCount:
            return children.sorted { $0.fileCount > $1.fileCount }
        }
    }

    func findNode(at targetPath: String) -> FileNode? {
        if path == targetPath { return self }
        for child in children {
            if targetPath.hasPrefix(child.path) {
                return child.findNode(at: targetPath)
            }
        }
        return nil
    }

    func removeChild(at targetPath: String) -> Bool {
        if let idx = children.firstIndex(where: { $0.path == targetPath }) {
            children.remove(at: idx)
            invalidateSortCache()
            return true
        }
        return false
    }

    func collectExtensionStats() -> [String: Int64] {
        var stats: [String: Int64] = [:]
        collectExtensionStatsHelper(into: &stats)
        return stats
    }

    private func collectExtensionStatsHelper(into stats: inout [String: Int64]) {
        if !isDirectory {
            let ext = fileExtension.isEmpty ? "(no extension)" : fileExtension
            stats[ext, default: 0] += size
        }
        for child in children {
            child.collectExtensionStatsHelper(into: &stats)
        }
    }

    /// Children for OutlineGroup — returns nil for leaves/empty dirs
    var directoryChildren: [FileNode]? {
        guard isDirectory, !children.isEmpty else { return nil }
        return sortedBySize
    }

    enum SortComparator {
        case size, name, fileCount
    }
}
