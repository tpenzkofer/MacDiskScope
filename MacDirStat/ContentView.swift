import SwiftUI

struct ContentView: View {
    @StateObject private var scanState = ScanState()
    @StateObject private var hoverState = HoverState()
    @State private var selectedPath: String = ""
    @State private var treeAction: TreeAction = .none

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 280)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarContent }
        .frame(minWidth: 900, minHeight: 600)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        if let root = scanState.rootNode {
            VStack(spacing: 0) {
                // Expand/Collapse toolbar
                HStack(spacing: 8) {
                    Button { treeAction = .collapseAll } label: {
                        Image(systemName: "minus.square")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help("Collapse All")

                    Button { treeAction = .expandToDepth(1) } label: {
                        Image(systemName: "plus.square")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help("Expand to 1 Level")

                    Button { treeAction = .expandToDepth(2) } label: {
                        Image(systemName: "square.stack")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help("Expand to 2 Levels")

                    Button { treeAction = .expandToDepth(3) } label: {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help("Expand to 3 Levels")

                    Button { treeAction = .expandAll } label: {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help("Expand All (may be slow for large trees)")

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                DirectoryTreeView(
                    node: root,
                    selectedNodeID: $scanState.selectedNodeID,
                    treeAction: $treeAction,
                    onNavigate: { scanState.navigateInto($0) },
                    onSelect: { scanState.selectNode($0) },
                    onDelete: { scanState.deleteNode($0) },
                    onMove: { node, url in scanState.moveNode(node, to: url) }
                )
            }
        } else if scanState.isScanning {
            VStack(spacing: 12) {
                ProgressView().scaleEffect(0.8)
                Text("Scanning...").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Select a folder to scan")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("Use the toolbar button or\npress \u{2318}O to choose a folder")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        VStack(spacing: 0) {
            if scanState.rootNode != nil {
                breadcrumbBar
                Divider()
            }

            if let displayNode = scanState.displayRoot {
                HSplitView {
                    VStack(spacing: 0) {
                        TreemapView(
                            node: displayNode,
                            totalSize: displayNode.size,
                            colorMode: scanState.colorMode,
                            globalOldestDate: scanState.globalOldestDate,
                            globalNewestDate: scanState.globalNewestDate,
                            maxFileSize: scanState.maxFileSize,
                            hoverState: hoverState,
                            onSelect: { scanState.selectNode($0) },
                            onNavigate: { scanState.navigateInto($0) }
                        )

                        if scanState.colorMode != .fileType {
                            heatmapLegend
                        }
                    }
                    .frame(minWidth: 400, minHeight: 300)

                    // Right panel: stats + info
                    VStack(spacing: 0) {
                        FileTypeStatsView(
                            stats: scanState.extensionStats,
                            totalSize: scanState.rootNode?.size ?? 0
                        )

                        if let selected = scanState.selectedNode {
                            Divider()
                            InfoPanelView(
                                node: selected,
                                rootSize: scanState.rootNode?.size ?? 1
                            )
                            .frame(minHeight: 160, idealHeight: 220)
                        }
                    }
                    .frame(minWidth: 270, idealWidth: 320, maxWidth: 420)
                }
            } else if scanState.isScanning {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(scanState.scanProgress)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }

            statusBar
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                openFolder()
            } label: {
                Label("Open Folder", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("o")
            .help("Open a folder to scan (\u{2318}O)")

            if scanState.isScanning {
                Button {
                    scanState.cancelScan()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop scanning")
            } else if scanState.rootNode != nil {
                Button {
                    scanState.rescan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .help("Rescan current folder (\u{2318}R)")
            }

            if scanState.rootNode != nil {
                Picker("Color", selection: $scanState.colorMode) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .help("Color mode for treemap")

                Button {
                    scanState.toggleMonitoring()
                } label: {
                    Label(
                        scanState.isMonitoring ? "Monitoring" : "Monitor",
                        systemImage: scanState.isMonitoring ? "eye.fill" : "eye.slash"
                    )
                }
                .foregroundColor(scanState.isMonitoring ? .green : .secondary)
                .help(scanState.isMonitoring ? "Click to stop monitoring" : "Click to monitor for real-time changes")
            }
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            if scanState.treemapRoot != nil {
                Button {
                    scanState.navigateToRoot()
                } label: {
                    Image(systemName: "house").font(.caption)
                }
                .buttonStyle(.borderless)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }

            let crumbs = buildBreadcrumbs()
            ForEach(Array(crumbs.enumerated()), id: \.offset) { idx, crumb in
                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                Button(crumb.name) {
                    if crumb === scanState.rootNode {
                        scanState.navigateToRoot()
                    } else {
                        scanState.navigateInto(crumb)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            Spacer()

            if scanState.treemapRoot != nil {
                Button {
                    scanState.navigateUp()
                } label: {
                    Label("Up", systemImage: "arrow.up").font(.caption)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var heatmapLegend: some View {
        HStack(spacing: 8) {
            if scanState.colorMode == .age {
                Text("Old").font(.caption2).foregroundColor(.secondary)
                LinearGradient(
                    colors: [
                        Color(hue: 0.65, saturation: 0.7, brightness: 0.6),
                        Color(hue: 0.33, saturation: 0.7, brightness: 0.75),
                        Color(hue: 0.16, saturation: 0.7, brightness: 0.85),
                        Color(hue: 0.08, saturation: 0.8, brightness: 0.9),
                        Color(hue: 0.0, saturation: 0.9, brightness: 0.85),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 10).cornerRadius(2)
                Text("New").font(.caption2).foregroundColor(.secondary)

                Spacer().frame(width: 8)

                let formatter = DateFormatter()
                let _ = formatter.dateStyle = .medium
                Text(formatter.string(from: scanState.globalOldestDate))
                    .font(.caption2).foregroundColor(.secondary)
                Text("-").font(.caption2).foregroundColor(.secondary)
                Text(formatter.string(from: scanState.globalNewestDate))
                    .font(.caption2).foregroundColor(.secondary)
            } else if scanState.colorMode == .size {
                Text("Small").font(.caption2).foregroundColor(.secondary)
                LinearGradient(
                    colors: [
                        Color(hue: 0.33, saturation: 0.5, brightness: 0.7),
                        Color(hue: 0.16, saturation: 0.7, brightness: 0.85),
                        Color(hue: 0.0, saturation: 0.9, brightness: 0.8),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 10).cornerRadius(2)
                Text("Large").font(.caption2).foregroundColor(.secondary)

                Spacer().frame(width: 8)
                Text("Max: \(FormatUtils.formatBytes(scanState.maxFileSize))")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    private func buildBreadcrumbs() -> [FileNode] {
        guard let display = scanState.displayRoot else { return [] }
        var crumbs: [FileNode] = [display]
        var current = display.parent
        while let node = current {
            crumbs.insert(node, at: 0)
            if node === scanState.rootNode { break }
            current = node.parent
        }
        return crumbs
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            HoverInfoView(hoverState: hoverState, scanState: scanState)
            Spacer()
            Text(scanState.scanProgress)
                .font(.caption)
                .foregroundColor(.secondary)
            if scanState.isScanning {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Actions

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to analyze disk usage"
        panel.prompt = "Scan"

        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
            scanState.scanURL(url)
        }
    }
}

/// Lightweight view that only re-renders on hover changes, isolated from sidebar
private struct HoverInfoView: View {
    @ObservedObject var hoverState: HoverState
    let scanState: ScanState

    var body: some View {
        if let hovered = hoverState.hoveredNode {
            HStack(spacing: 4) {
                Image(systemName: hovered.isDirectory ? "folder.fill" : "doc")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(hovered.name)
                    .font(.caption)
                    .lineLimit(1)
                Text("--")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(FormatUtils.formatBytes(hovered.size))
                    .font(.system(.caption, design: .monospaced))
                if let root = scanState.rootNode {
                    Text(FormatUtils.percentString(hovered.size, of: root.size))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        } else if let selected = scanState.selectedNode {
            HStack(spacing: 4) {
                Image(systemName: selected.isDirectory ? "folder.fill" : "doc")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(selected.path)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }
}
