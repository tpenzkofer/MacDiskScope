import Foundation

actor DirectoryScanner {
    private var isCancelled = false

    private(set) var scannedFiles: Int = 0
    private(set) var scannedBytes: Int64 = 0

    func cancel() {
        isCancelled = true
    }

    func scan(path: String, progressCallback: @Sendable @escaping (Int, Int64) -> Void) async -> FileNode? {
        isCancelled = false
        scannedFiles = 0
        scannedBytes = 0

        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let root = FileNode(name: name, path: path, isDirectory: true)

        await scanDirectory(node: root, progressCallback: progressCallback)

        return isCancelled ? nil : root
    }

    func scanSingleDirectory(path: String) async -> FileNode? {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }

        let node = FileNode(name: name, path: path, isDirectory: isDir.boolValue)
        if isDir.boolValue {
            await scanDirectory(node: node, progressCallback: { _, _ in })
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            node.size = (attrs?[.size] as? Int64) ?? 0
            node.allocatedSize = node.size
        }
        return node
    }

    private func scanDirectory(node: FileNode, progressCallback: @Sendable @escaping (Int, Int64) -> Void) async {
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

        // Build tree bottom-up
        let allDirPaths = nodeMap.keys.sorted { p1, p2 in
            p1.components(separatedBy: "/").count > p2.components(separatedBy: "/").count
        }

        for dirPath in allDirPaths {
            guard let dirNode = nodeMap[dirPath] else { continue }
            if let kids = childrenMap[dirPath] {
                dirNode.children = kids.sorted { $0.size > $1.size }
            }
            dirNode.updateSizeFromChildren()
        }

        let f = scannedFiles
        let b = scannedBytes
        progressCallback(f, b)
    }
}
