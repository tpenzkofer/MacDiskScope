import SwiftUI
import AppKit
import Quartz

/// Controls expand/collapse from outside the tree view
enum TreeAction: Equatable {
    case none
    case expandAll
    case collapseAll
    case expandToDepth(Int)
}

struct DirectoryTreeView: NSViewRepresentable {
    let node: FileNode
    @Binding var selectedNodeID: UUID?
    @Binding var treeAction: TreeAction
    let onNavigate: (FileNode) -> Void
    let onSelect: (FileNode) -> Void
    let onDelete: (FileNode) -> Void
    let onMove: (FileNode, URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate, onSelect: onSelect, onDelete: onDelete, onMove: onMove)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let outlineView = ContextMenuOutlineView()
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .small
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.indentationPerLevel = 16
        outlineView.floatsGroupRows = false
        outlineView.coordinator = context.coordinator

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.delegate = context.coordinator
        outlineView.dataSource = context.coordinator
        outlineView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        outlineView.target = context.coordinator

        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let outlineView = coordinator.outlineView!

        coordinator.onNavigate = onNavigate
        coordinator.onSelect = onSelect
        coordinator.onDelete = onDelete
        coordinator.onMove = onMove

        // Only reload if root changed
        if coordinator.rootNode !== node {
            coordinator.rootNode = node
            outlineView.reloadData()
            // Auto-expand first level
            for child in node.sortedBySize {
                if child.isDirectory {
                    outlineView.expandItem(child, expandChildren: false)
                }
            }
        }

        // Sync selection
        if let targetID = selectedNodeID {
            if let currentSel = coordinator.selectedNode, currentSel.id == targetID {
                // Already in sync
            } else {
                let row = outlineView.row(forItem: coordinator.findNode(id: targetID, in: node))
                if row >= 0 {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    outlineView.scrollRowToVisible(row)
                }
            }
        }

        // Handle expand/collapse actions
        if treeAction != .none {
            let action = treeAction
            DispatchQueue.main.async { self.treeAction = .none }
            switch action {
            case .expandAll:
                coordinator.expandAll()
            case .collapseAll:
                coordinator.collapseAll()
            case .expandToDepth(let depth):
                coordinator.expandToDepth(depth)
            case .none:
                break
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var rootNode: FileNode?
        var selectedNode: FileNode?
        var quickLookNode: FileNode?
        weak var outlineView: NSOutlineView?
        var onNavigate: (FileNode) -> Void
        var onSelect: (FileNode) -> Void
        var onDelete: (FileNode) -> Void
        var onMove: (FileNode, URL) -> Void

        private let byteFormatter: ByteCountFormatter = {
            let f = ByteCountFormatter()
            f.countStyle = .file
            return f
        }()

        init(onNavigate: @escaping (FileNode) -> Void, onSelect: @escaping (FileNode) -> Void,
             onDelete: @escaping (FileNode) -> Void, onMove: @escaping (FileNode, URL) -> Void) {
            self.onNavigate = onNavigate
            self.onSelect = onSelect
            self.onDelete = onDelete
            self.onMove = onMove
        }

        // MARK: Expand / Collapse

        func expandAll() {
            guard let ov = outlineView else { return }
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            ov.expandItem(nil, expandChildren: true)
            NSAnimationContext.endGrouping()
        }

        func collapseAll() {
            guard let ov = outlineView else { return }
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            ov.collapseItem(nil, collapseChildren: true)
            NSAnimationContext.endGrouping()
        }

        func expandToDepth(_ maxDepth: Int) {
            guard let ov = outlineView, let root = rootNode else { return }
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            ov.collapseItem(nil, collapseChildren: true)
            for child in root.sortedBySize {
                expandRecursive(item: child, outlineView: ov, currentDepth: 0, maxDepth: maxDepth)
            }
            NSAnimationContext.endGrouping()
        }

        private func expandRecursive(item: FileNode, outlineView: NSOutlineView, currentDepth: Int, maxDepth: Int) {
            guard item.isDirectory && currentDepth < maxDepth else { return }
            outlineView.expandItem(item, expandChildren: false)
            for child in item.sortedBySize {
                expandRecursive(item: child, outlineView: outlineView, currentDepth: currentDepth + 1, maxDepth: maxDepth)
            }
        }

        func findNode(id: UUID, in node: FileNode) -> FileNode? {
            if node.id == id { return node }
            for child in node.children {
                if let found = findNode(id: id, in: child) { return found }
            }
            return nil
        }

        // MARK: DataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return rootNode?.sortedBySize.count ?? 0
            }
            guard let node = item as? FileNode else { return 0 }
            return node.sortedBySize.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return rootNode!.sortedBySize[index]
            }
            return (item as! FileNode).sortedBySize[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? FileNode else { return false }
            return node.isDirectory && !node.children.isEmpty
        }

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileNode else { return nil }

            let cellID = NSUserInterfaceItemIdentifier("TreeCell")
            let cell: TreeCellView
            if let reused = outlineView.makeView(withIdentifier: cellID, owner: self) as? TreeCellView {
                cell = reused
            } else {
                cell = TreeCellView()
                cell.identifier = cellID
            }

            let totalSize = rootNode?.size ?? 1
            cell.configure(node: node, totalSize: totalSize, formatter: byteFormatter)
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            22
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = outlineView else { return }
            let row = outlineView.selectedRow
            guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
            selectedNode = node
            onSelect(node)

            // Update Quick Look if the panel is open — Finder-like behavior
            if let panel = QLPreviewPanel.shared(), panel.isVisible {
                if !node.isDirectory {
                    quickLookNode = node
                    panel.reloadData()
                }
            }
        }

        @objc func doubleClicked(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0, let node = sender.item(atRow: row) as? FileNode else { return }
            if node.isDirectory {
                onNavigate(node)
            }
        }

        // MARK: Context Menu

        func outlineView(_ outlineView: NSOutlineView, menuForItem item: Any) -> NSMenu? {
            guard let node = item as? FileNode else { return nil }
            let menu = NSMenu()

            let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(contextReveal(_:)), keyEquivalent: "")
            revealItem.target = self
            revealItem.representedObject = node
            menu.addItem(revealItem)

            let openItem = NSMenuItem(title: "Open", action: #selector(contextOpen(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = node
            menu.addItem(openItem)

            let qlItem = NSMenuItem(title: "Quick Look", action: #selector(contextQuickLook(_:)), keyEquivalent: " ")
            qlItem.target = self
            qlItem.representedObject = node
            menu.addItem(qlItem)

            let copyPathItem = NSMenuItem(title: "Copy Path", action: #selector(contextCopyPath(_:)), keyEquivalent: "")
            copyPathItem.target = self
            copyPathItem.representedObject = node
            menu.addItem(copyPathItem)

            menu.addItem(NSMenuItem.separator())

            let moveItem = NSMenuItem(title: "Move to...", action: #selector(contextMove(_:)), keyEquivalent: "")
            moveItem.target = self
            moveItem.representedObject = node
            menu.addItem(moveItem)

            menu.addItem(NSMenuItem.separator())

            let deleteItem = NSMenuItem(title: "Move to Trash", action: #selector(contextDelete(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = node
            menu.addItem(deleteItem)

            return menu
        }

        @objc func contextReveal(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? FileNode else { return }
            NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
        }

        @objc func contextOpen(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? FileNode else { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: node.path))
        }

        @objc func contextQuickLook(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? FileNode else { return }
            quickLookNode = node
            if let panel = QLPreviewPanel.shared() {
                if panel.isVisible {
                    panel.reloadData()
                } else {
                    panel.makeKeyAndOrderFront(nil)
                }
            }
        }

        @objc func contextCopyPath(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? FileNode else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.path, forType: .string)
        }

        @objc func contextMove(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? FileNode else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.message = "Choose destination for \"\(node.name)\""
            panel.prompt = "Move Here"
            if panel.runModal() == .OK, let url = panel.url {
                onMove(node, url)
                outlineView?.reloadData()
            }
        }

        @objc func contextDelete(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? FileNode else { return }
            let alert = NSAlert()
            alert.messageText = "Move \"\(node.name)\" to Trash?"
            let sizeStr = byteFormatter.string(fromByteCount: node.size)
            if node.isDirectory {
                alert.informativeText = "This folder contains \(FormatUtils.formatCount(node.fileCount)) files (\(sizeStr))."
            } else {
                alert.informativeText = "This file is \(sizeStr)."
            }
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                onDelete(node)
                outlineView?.reloadData()
            }
        }

        // MARK: Quick Look

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            // Return number of rows in the outline so QL can navigate
            outlineView?.numberOfRows ?? 0
        }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
            guard let ov = outlineView,
                  index >= 0, index < ov.numberOfRows,
                  let node = ov.item(atRow: index) as? FileNode else { return nil }
            return URL(fileURLWithPath: node.path) as NSURL
        }

        func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
            guard let ov = outlineView else { return false }

            if event.type == .keyDown {
                let keyCode = event.keyCode
                // Spacebar closes
                if keyCode == 49 {
                    panel.close()
                    return true
                }
                // Up/Down arrow keys — move selection in the outline view, QL follows
                if keyCode == 125 || keyCode == 126 { // down / up
                    ov.keyDown(with: event)
                    let row = ov.selectedRow
                    if row >= 0 {
                        panel.currentPreviewItemIndex = row
                    }
                    return true
                }
            }
            return false
        }

        // Called when QL navigates — sync outline selection
        func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
            // Sync outline view selection to match QL's current item
            let idx = panel.currentPreviewItemIndex
            if let ov = outlineView, idx >= 0, idx < ov.numberOfRows {
                ov.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
                ov.scrollRowToVisible(idx)
                if let node = ov.item(atRow: idx) as? FileNode {
                    selectedNode = node
                    onSelect(node)
                }
            }
            return .zero
        }

        /// Toggle Quick Look for the currently selected item
        func toggleQuickLook() {
            guard let sel = selectedNode else { return }
            quickLookNode = sel
            if let panel = QLPreviewPanel.shared() {
                if panel.isVisible {
                    panel.close()
                } else {
                    // Set the current index to match the selected row
                    if let ov = outlineView {
                        let row = ov.selectedRow
                        if row >= 0 {
                            panel.currentPreviewItemIndex = row
                        }
                    }
                    panel.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
}

// MARK: - NSOutlineView subclass for context menu

private final class ContextMenuOutlineView: NSOutlineView {
    weak var coordinator: DirectoryTreeView.Coordinator?

    override func keyDown(with event: NSEvent) {
        // Spacebar toggles Quick Look
        if event.keyCode == 49 {
            coordinator?.toggleQuickLook()
            return
        }
        super.keyDown(with: event)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = coordinator
        panel.delegate = coordinator
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0, let node = item(atRow: row) as? FileNode else { return nil }
        // Select the row so it's visually highlighted
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return coordinator?.outlineView(self, menuForItem: node)
    }
}

// MARK: - Native cell view with recycling

private final class TreeCellView: NSView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let barView = SizeBarView()

    private var isSetUp = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setUp() {
        guard !isSetUp else { return }
        isSetUp = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(nameLabel)

        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.alignment = .right
        sizeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(sizeLabel)

        barView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(barView)

        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.alignment = .right
        percentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(percentLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            sizeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 4),
            sizeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            sizeLabel.widthAnchor.constraint(equalToConstant: 72),

            barView.leadingAnchor.constraint(equalTo: sizeLabel.trailingAnchor, constant: 4),
            barView.centerYAnchor.constraint(equalTo: centerYAnchor),
            barView.widthAnchor.constraint(equalToConstant: 50),
            barView.heightAnchor.constraint(equalToConstant: 10),

            percentLabel.leadingAnchor.constraint(equalTo: barView.trailingAnchor, constant: 4),
            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            percentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            percentLabel.widthAnchor.constraint(equalToConstant: 46),
        ])
    }

    func configure(node: FileNode, totalSize: Int64, formatter: ByteCountFormatter) {
        setUp()

        let iconName: String
        if node.isDirectory {
            iconName = "folder.fill"
        } else {
            switch node.fileExtension {
            case "swift", "py", "js", "ts", "c", "cpp", "h", "m", "rs", "go", "java", "rb":
                iconName = "doc.text"
            case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "svg", "webp":
                iconName = "photo"
            case "mp4", "avi", "mkv", "mov", "wmv":
                iconName = "film"
            case "mp3", "wav", "flac", "aac", "m4a":
                iconName = "music.note"
            case "zip", "tar", "gz", "rar", "7z", "dmg":
                iconName = "archivebox"
            case "pdf":
                iconName = "doc.richtext"
            default:
                iconName = "doc"
            }
        }
        iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
        iconView.contentTintColor = node.isDirectory ? .controlAccentColor : .secondaryLabelColor

        nameLabel.stringValue = node.name
        sizeLabel.stringValue = formatter.string(fromByteCount: node.size)

        let fraction: Double = totalSize > 0 ? Double(node.size) / Double(totalSize) : 0
        barView.fraction = fraction
        barView.needsDisplay = true

        percentLabel.stringValue = FormatUtils.percentString(node.size, of: totalSize)
    }
}

// MARK: - Lightweight bar drawn with Core Graphics

private final class SizeBarView: NSView {
    var fraction: Double = 0

    override func draw(_ dirtyRect: NSRect) {
        let ctx = NSGraphicsContext.current!.cgContext
        let r = bounds

        // Background
        ctx.setFillColor(NSColor.quaternaryLabelColor.cgColor)
        ctx.fill(r)

        // Filled portion
        let barWidth = r.width * min(CGFloat(fraction), 1.0)
        if barWidth > 0 {
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor)
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: barWidth, height: r.height))
        }
    }
}
