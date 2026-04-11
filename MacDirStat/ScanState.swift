import SwiftUI

enum ColorMode: String, CaseIterable, Identifiable {
    case fileType = "File Type"
    case age = "Age (Modified)"
    case size = "Size"

    var id: String { rawValue }
}

/// Separate hover state so mouse movement doesn't invalidate the entire view tree
@MainActor
final class HoverState: ObservableObject {
    @Published var hoveredNode: FileNode?
}

@MainActor
final class ScanState: ObservableObject {
    @Published var rootNode: FileNode?
    @Published var isScanning = false
    @Published var scanProgress: String = ""
    @Published var selectedNode: FileNode?
    @Published var selectedNodeID: UUID?
    @Published var treemapRoot: FileNode?
    @Published var extensionStats: [(ext: String, size: Int64)] = []
    @Published var isMonitoring = false
    @Published var monitoringEnabled = false
    @Published var colorMode: ColorMode = .fileType
    @Published var globalOldestDate: Date = Date()
    @Published var globalNewestDate: Date = Date()
    @Published var maxFileSize: Int64 = 0

    private var scanner = DirectoryScanner()
    private var monitor: FSEventsMonitor?

    /// Security-scoped URL from NSOpenPanel — must stay accessed while scanning/monitoring
    private var securityScopedURL: URL?

    var displayRoot: FileNode? {
        treemapRoot ?? rootNode
    }

    var scannedPath: String? {
        rootNode?.path
    }

    // MARK: - Scanning

    func scanURL(_ url: URL) {
        // Stop accessing any previous security-scoped resource
        stopAccessingSecurityScope()

        // Start accessing the new one
        let gained = url.startAccessingSecurityScopedResource()
        if gained {
            securityScopedURL = url
        }

        // Save bookmark for future re-access
        saveBookmark(for: url)

        scan(path: url.path)
    }

    func rescan() {
        guard let path = rootNode?.path else { return }
        // Try to restore access from bookmark if we don't have it
        if securityScopedURL == nil {
            if let restored = restoreBookmark() {
                let gained = restored.startAccessingSecurityScopedResource()
                if gained { securityScopedURL = restored }
            }
        }
        scan(path: path)
    }

    private func scan(path: String) {
        isScanning = true
        scanProgress = "Starting scan..."
        rootNode = nil
        treemapRoot = nil
        selectedNode = nil
        selectedNodeID = nil
        extensionStats = []
        stopMonitoring()

        let scannerRef = DirectoryScanner()
        self.scanner = scannerRef

        Task {
            let result = await scannerRef.scan(
                path: path,
                progressCallback: { [weak self] files, bytes in
                    Task { @MainActor in
                        self?.scanProgress = "Scanned \(FormatUtils.formatCount(files)) files (\(FormatUtils.formatBytes(bytes)))"
                    }
                },
                phaseCallback: { [weak self] phase in
                    Task { @MainActor in
                        self?.scanProgress = phase
                    }
                }
            )

            if let root = result {
                self.rootNode = root
                self.updateExtensionStats()
                self.computeDateAndSizeRanges(root: root)
                self.scanProgress = "\(FormatUtils.formatCount(root.fileCount)) files, \(FormatUtils.formatBytes(root.size))"
                if self.monitoringEnabled {
                    self.startMonitoring(path: path)
                }
            }
            self.isScanning = false
        }
    }

    func cancelScan() {
        Task {
            await scanner.cancel()
        }
        isScanning = false
        scanProgress = "Scan cancelled"
    }

    // MARK: - Security-Scoped Bookmarks

    private static let bookmarkKey = "com.macdiskscope.lastScanBookmark"

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        } catch {
            // Non-fatal — bookmark just won't persist
        }
    }

    private func restoreBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            if isStale {
                // Re-save if stale
                saveBookmark(for: url)
            }
            return url
        } catch {
            return nil
        }
    }

    private func stopAccessingSecurityScope() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    // MARK: - Navigation

    func navigateInto(_ node: FileNode) {
        if node.isDirectory {
            treemapRoot = node
            selectedNode = node
            selectedNodeID = node.id
        }
    }

    func navigateUp() {
        if let current = treemapRoot {
            treemapRoot = current.parent
            selectedNode = treemapRoot
            selectedNodeID = treemapRoot?.id
        }
    }

    func navigateToRoot() {
        treemapRoot = nil
        selectedNode = rootNode
        selectedNodeID = rootNode?.id
    }

    func selectNode(_ node: FileNode) {
        selectedNode = node
        selectedNodeID = node.id
    }

    func updateExtensionStats() {
        guard let root = rootNode else {
            extensionStats = []
            return
        }
        let stats = root.collectExtensionStats()
        extensionStats = stats
            .map { (ext: $0.key, size: $0.value) }
            .sorted { $0.size > $1.size }
    }

    // MARK: - File Operations

    func deleteNode(_ node: FileNode) {
        let url = URL(fileURLWithPath: node.path)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            removeNodeFromTree(node)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not move to Trash"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    func moveNode(_ node: FileNode, to destination: URL) {
        let sourceURL = URL(fileURLWithPath: node.path)
        let destURL = destination.appendingPathComponent(node.name)
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
            removeNodeFromTree(node)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not move item"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func removeNodeFromTree(_ node: FileNode) {
        guard let parent = node.parent else { return }
        _ = parent.removeChild(at: node.path)
        parent.updateSizeFromChildren()

        var current = parent.parent
        while let n = current {
            n.updateSizeFromChildren()
            current = n.parent
        }

        if selectedNode === node {
            selectedNode = parent
            selectedNodeID = parent.id
        }

        updateExtensionStats()
        objectWillChange.send()
    }

    // MARK: - Monitoring

    func toggleMonitoring() {
        monitoringEnabled.toggle()
        if monitoringEnabled, let path = rootNode?.path {
            startMonitoring(path: path)
        } else {
            stopMonitoring()
        }
    }

    private func computeDateAndSizeRanges(root: FileNode) {
        var oldest = Date()
        var newest = Date.distantPast
        var maxSize: Int64 = 0
        computeRangesRecursive(node: root, oldest: &oldest, newest: &newest, maxSize: &maxSize)
        globalOldestDate = oldest
        globalNewestDate = newest
        maxFileSize = maxSize
    }

    private func computeRangesRecursive(node: FileNode, oldest: inout Date, newest: inout Date, maxSize: inout Int64) {
        if !node.isDirectory {
            if let date = node.modificationDate {
                if date < oldest { oldest = date }
                if date > newest { newest = date }
            }
            if node.size > maxSize { maxSize = node.size }
        }
        for child in node.children {
            computeRangesRecursive(node: child, oldest: &oldest, newest: &newest, maxSize: &maxSize)
        }
    }

    // MARK: - FSEvents Monitoring

    private func startMonitoring(path: String) {
        stopMonitoring()
        isMonitoring = true
        monitor = FSEventsMonitor(path: path, debounceInterval: 1.5) { [weak self] changedPaths in
            Task { @MainActor in
                self?.handleFileSystemChanges(changedPaths)
            }
        }
        monitor?.start()
    }

    func stopMonitoring() {
        monitor?.stop()
        monitor = nil
        isMonitoring = false
    }

    private func handleFileSystemChanges(_ changedPaths: [String]) {
        guard let root = rootNode else { return }

        let uniqueDirs = Set(changedPaths)

        Task {
            let incrementalScanner = DirectoryScanner()

            for dirPath in uniqueDirs {
                guard dirPath.hasPrefix(root.path) else { continue }
                guard let parentNode = root.findNode(at: dirPath) else { continue }

                if let updatedNode = await incrementalScanner.scanSingleDirectory(path: dirPath) {
                    await MainActor.run {
                        parentNode.children = updatedNode.children
                        parentNode.invalidateSortCache()
                        for child in parentNode.children {
                            child.parent = parentNode
                        }
                        parentNode.updateSizeFromChildren()

                        var current = parentNode.parent
                        while let node = current {
                            node.updateSizeFromChildren()
                            current = node.parent
                        }

                        self.updateExtensionStats()
                        self.objectWillChange.send()
                    }
                }
            }
        }
    }
}
