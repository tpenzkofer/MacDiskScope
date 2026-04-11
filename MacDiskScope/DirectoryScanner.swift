import Foundation

actor DirectoryScanner {
    private var isCancelled = false

    private(set) var scannedFiles: Int = 0
    private(set) var scannedBytes: Int64 = 0

    func cancel() {
        isCancelled = true
    }

    func scan(path: String, progressCallback: @Sendable @escaping (Int, Int64) -> Void, phaseCallback: @Sendable @escaping (String) -> Void = { _ in }) async -> FileNode? {
        isCancelled = false
        scannedFiles = 0
        scannedBytes = 0

        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let root = FileNode(name: name, path: path, isDirectory: true)

        await scanDirectory(node: root, progressCallback: progressCallback, phaseCallback: phaseCallback)

        return isCancelled ? nil : root
    }

    func scanSingleDirectory(path: String) async -> FileNode? {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }

        let node = FileNode(name: name, path: path, isDirectory: isDir.boolValue)
        if isDir.boolValue {
            await scanDirectory(node: node, progressCallback: { _, _ in }, phaseCallback: { _ in })
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            node.size = (attrs?[.size] as? Int64) ?? 0
            node.allocatedSize = node.size
        }
        return node
    }

    private func scanDirectory(node: FileNode, progressCallback: @Sendable @escaping (Int, Int64) -> Void, phaseCallback: @Sendable @escaping (String) -> Void) async {
        guard !isCancelled else { return }

        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .isSymbolicLinkKey, .contentModificationDateKey]

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: node.path),
            includingPropertiesForKeys: keys,
            options: []
        ) else { return }

        var nodeMap: [String: FileNode] = [node.path: node]
        var childrenMap: [String: [FileNode]] = [:]

        var batchCount = 0
        let reportInterval = 500

        while let url = enumerator.nextObject() as? URL {
            if isCancelled { return }

            guard let resourceValues = try? url.resourceValues(forKeys: Set(keys)) else { continue }

            let isSymlink = resourceValues.isSymbolicLink ?? false
            if isSymlink {
                enumerator.skipDescendants()
                continue
            }

            let isDir = resourceValues.isDirectory ?? false
            let filePath = url.path
            let fileName = url.lastPathComponent

            let child = FileNode(name: fileName, path: filePath, isDirectory: isDir)
            child.modificationDate = resourceValues.contentModificationDate

            if !isDir {
                let fileSize = Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileSize ?? 0)
                child.size = fileSize
                child.allocatedSize = fileSize
                scannedFiles += 1
                scannedBytes += fileSize
            }

            let parentPath = (filePath as NSString).deletingLastPathComponent
            childrenMap[parentPath, default: []].append(child)
            if isDir {
                nodeMap[filePath] = child
            }

            child.parent = nodeMap[parentPath]

            batchCount += 1
            if batchCount >= reportInterval {
                batchCount = 0
                let f = scannedFiles
                let b = scannedBytes
                progressCallback(f, b)
            }
        }

        phaseCallback("Building tree (\(FormatUtils.formatCount(nodeMap.count)) folders)...")

        // Build tree bottom-up — sort by path depth (deepest first)
        // Count slashes instead of splitting into arrays — much faster
        let allDirPaths = nodeMap.keys.sorted { p1, p2 in
            var c1 = 0; for ch in p1.utf8 where ch == 0x2F { c1 += 1 }
            var c2 = 0; for ch in p2.utf8 where ch == 0x2F { c2 += 1 }
            return c1 > c2
        }

        for dirPath in allDirPaths {
            guard let dirNode = nodeMap[dirPath] else { continue }
            if let kids = childrenMap[dirPath] {
                // Assign unsorted — sortedBySize cache handles display order lazily
                dirNode.children = kids
            }
            dirNode.updateSizeFromChildren()
        }

        let f = scannedFiles
        let b = scannedBytes
        progressCallback(f, b)
    }
}
