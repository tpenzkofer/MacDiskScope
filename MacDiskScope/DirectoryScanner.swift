import Foundation

final class DirectoryScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    private var _scannedFiles: Int = 0
    private var _scannedBytes: Int64 = 0

    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey,
        .isSymbolicLinkKey, .contentModificationDateKey
    ]
    private static let keysArray = Array(keys)

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    func cancel() {
        lock.lock(); _cancelled = true; lock.unlock()
    }

    private func addProgress(files: Int, bytes: Int64) {
        lock.lock()
        _scannedFiles += files
        _scannedBytes += bytes
        lock.unlock()
    }

    private func getProgress() -> (Int, Int64) {
        lock.lock(); defer { lock.unlock() }
        return (_scannedFiles, _scannedBytes)
    }

    // MARK: - Public API

    func scan(
        path: String,
        progressCallback: @Sendable @escaping (Int, Int64) -> Void,
        phaseCallback: @Sendable @escaping (String) -> Void = { _ in }
    ) async -> FileNode? {
        lock.lock()
        _cancelled = false; _scannedFiles = 0; _scannedBytes = 0
        lock.unlock()

        let name = (path as NSString).lastPathComponent
        let root = FileNode(name: name, path: path, isDirectory: true)

        // Background progress reporter
        let progressTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard let self else { return }
                let (f, b) = self.getProgress()
                progressCallback(f, b)
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                self.scanRecursive(node: root)
                continuation.resume()
            }
        }

        progressTask.cancel()
        guard !isCancelled else { return nil }

        let (f, b) = getProgress()
        progressCallback(f, b)
        phaseCallback("\(FormatUtils.formatCount(f)) files, \(FormatUtils.formatBytes(b))")

        return root
    }

    func scanSingleDirectory(path: String) async -> FileNode? {
        let name = (path as NSString).lastPathComponent
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        let node = FileNode(name: name, path: path, isDirectory: isDir.boolValue)
        if isDir.boolValue {
            scanRecursive(node: node)
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            node.size = (attrs?[.size] as? Int64) ?? 0
            node.allocatedSize = node.size
        }
        return node
    }

    // MARK: - Recursive per-directory scan
    //
    // Instead of flat enumeration + expensive nodeMap + depth-sort,
    // enumerate each directory non-recursively and recurse into subdirs.
    // FileManager.contentsOfDirectory(at:includingPropertiesForKeys:)
    // uses getattrlistbulk internally — this is the fastest macOS API
    // when called per-directory.

    private func scanRecursive(node: FileNode) {
        guard !isCancelled else { return }

        let url = URL(fileURLWithPath: node.path)
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Self.keysArray,
            options: []
        ) else { return }

        var localFiles = 0
        var localBytes: Int64 = 0

        for childURL in contents {
            if isCancelled { return }

            guard let rv = try? childURL.resourceValues(forKeys: Self.keys) else { continue }

            if rv.isSymbolicLink == true { continue }

            let isDir = rv.isDirectory == true
            let child = FileNode(
                name: childURL.lastPathComponent,
                path: childURL.path,
                isDirectory: isDir
            )
            child.modificationDate = rv.contentModificationDate
            child.parent = node

            if isDir {
                scanRecursive(node: child)
                node.children.append(child)
            } else {
                let sz = Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
                child.size = sz
                child.allocatedSize = sz
                node.children.append(child)
                localFiles += 1
                localBytes += sz
            }
        }

        addProgress(files: localFiles, bytes: localBytes)
        node.updateSizeFromChildren()
    }
}
