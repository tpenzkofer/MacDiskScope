import SwiftUI
import AppKit

struct TreemapView: NSViewRepresentable {
    let node: FileNode
    let totalSize: Int64
    let colorMode: ColorMode
    let globalOldestDate: Date
    let globalNewestDate: Date
    let maxFileSize: Int64
    let hoverState: HoverState
    let onSelect: (FileNode) -> Void
    let onNavigate: (FileNode) -> Void

    func makeCoordinator() -> TreemapCoordinator {
        TreemapCoordinator(onSelect: onSelect, onNavigate: onNavigate, hoverState: hoverState)
    }

    func makeNSView(context: Context) -> TreemapNSView {
        let view = TreemapNSView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: TreemapNSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.onNavigate = onNavigate
        coordinator.hoverState = hoverState

        let needsFullRedraw =
            coordinator.currentNodeID != node.id ||
            coordinator.currentColorMode != colorMode

        coordinator.currentNodeID = node.id
        coordinator.currentColorMode = colorMode
        coordinator.node = node
        coordinator.colorMode = colorMode
        coordinator.globalOldestDate = globalOldestDate
        coordinator.globalNewestDate = globalNewestDate
        coordinator.maxFileSize = maxFileSize

        if needsFullRedraw {
            coordinator.invalidateLayout()
            view.invalidateCache()
            view.needsDisplay = true
        }
    }
}

// MARK: - Coordinator holds layout + color state

final class TreemapCoordinator {
    var node: FileNode?
    var colorMode: ColorMode = .fileType
    var globalOldestDate: Date = Date()
    var globalNewestDate: Date = Date()
    var maxFileSize: Int64 = 0
    var hoveredNode: FileNode?
    var currentNodeID: UUID?
    var currentColorMode: ColorMode = .fileType

    var onSelect: (FileNode) -> Void
    var onNavigate: (FileNode) -> Void
    var hoverState: HoverState
    weak var view: TreemapNSView?

    // Cached layout
    var dirFrames: [TreemapRect] = []
    var leafRects: [TreemapRect] = []
    private var layoutSize: CGSize = .zero

    init(onSelect: @escaping (FileNode) -> Void, onNavigate: @escaping (FileNode) -> Void, hoverState: HoverState) {
        self.onSelect = onSelect
        self.onNavigate = onNavigate
        self.hoverState = hoverState
    }

    func invalidateLayout() {
        layoutSize = .zero
    }

    func ensureLayout(size: CGSize) {
        guard let node = node, size.width > 0, size.height > 0 else { return }
        if layoutSize == size { return }
        layoutSize = size

        let items: [FileNode] = node.isDirectory
            ? node.children.filter { $0.size > 0 }
            : [node]

        var df: [TreemapRect] = []
        var lr: [TreemapRect] = []

        let topRects = TreemapLayout.layout(nodes: items, in: CGRect(origin: .zero, size: size), minSize: 1.5)

        for rect in topRects {
            if rect.node.isDirectory && !rect.node.children.isEmpty {
                layoutHierarchical(
                    node: rect.node,
                    rect: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
                    depth: 0, maxDepth: 6,
                    cushionX: rect.cushionX, cushionY: rect.cushionY,
                    dirFrames: &df, leafRects: &lr
                )
            } else {
                lr.append(rect)
            }
        }

        df.sort { $0.depth < $1.depth }
        dirFrames = df
        leafRects = lr
    }

    private func layoutHierarchical(
        node: FileNode, rect: CGRect, depth: Int, maxDepth: Int,
        cushionX: TreemapRect.CushionAxis, cushionY: TreemapRect.CushionAxis,
        dirFrames: inout [TreemapRect], leafRects: inout [TreemapRect]
    ) {
        guard rect.width >= 2 && rect.height >= 2 else { return }

        // For small rects at deep levels, skip the frame entirely — just lay out children flat
        let tooSmallForFrame = rect.width < 20 || rect.height < 20
        let padding: Double
        let headerH: Double

        if tooSmallForFrame || depth >= 3 {
            padding = 0
            headerH = 0
            // Still emit a thin directory frame for visual separation
            if depth <= 2 {
                dirFrames.append(TreemapRect(
                    x: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
                    node: node, depth: depth, isDirectoryFrame: true,
                    cushionX: cushionX, cushionY: cushionY
                ))
            }
        } else {
            switch depth {
            case 0:  padding = 1.5
            case 1:  padding = 1.0
            default: padding = 0.5
            }
            headerH = (depth <= 1 && rect.width > 70 && rect.height > 20)
                ? min(12, rect.height * 0.1) : 0

            dirFrames.append(TreemapRect(
                x: rect.minX, y: rect.minY, width: rect.width, height: rect.height,
                node: node, depth: depth, isDirectoryFrame: true,
                cushionX: cushionX, cushionY: cushionY
            ))
        }

        let innerRect = CGRect(
            x: rect.minX + padding,
            y: rect.minY + padding + headerH,
            width: max(0, rect.width - 2 * padding),
            height: max(0, rect.height - 2 * padding - headerH)
        )

        guard innerRect.width >= 1 && innerRect.height >= 1 else { return }
        guard depth < maxDepth else {
            leafRects.append(contentsOf: TreemapLayout.layout(
                nodes: node.children.filter { $0.size > 0 }, in: innerRect, minSize: 1.0))
            return
        }

        let childRects = TreemapLayout.layout(
            nodes: node.children.filter { $0.size > 0 }, in: innerRect, minSize: 1.0)

        for cr in childRects {
            if cr.node.isDirectory && !cr.node.children.isEmpty && cr.width > 3 && cr.height > 3 {
                layoutHierarchical(
                    node: cr.node,
                    rect: CGRect(x: cr.x, y: cr.y, width: cr.width, height: cr.height),
                    depth: depth + 1, maxDepth: maxDepth,
                    cushionX: cr.cushionX, cushionY: cr.cushionY,
                    dirFrames: &dirFrames, leafRects: &leafRects
                )
            } else {
                leafRects.append(cr)
            }
        }
    }

    func hitTest(_ point: CGPoint) -> FileNode? {
        leafRects.last { r in
            point.x >= r.x && point.x < r.x + r.width &&
            point.y >= r.y && point.y < r.y + r.height
        }?.node
    }

    func hitTestDirectory(_ point: CGPoint) -> FileNode? {
        dirFrames.last { r in
            point.x >= r.x && point.x < r.x + r.width &&
            point.y >= r.y && point.y < r.y + r.height
        }?.node
    }
}

// MARK: - NSView with cached bitmap rendering

final class TreemapNSView: NSView {
    var coordinator: TreemapCoordinator!

    /// Cached full treemap render — only redrawn on layout/color change
    private var cachedImage: CGImage?
    private var cachedSize: CGSize = .zero

    /// Hover highlight layer — updated cheaply without redrawing the map
    private let hoverLayer = CAShapeLayer()

    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(hoverLayer)
        hoverLayer.fillColor = NSColor.white.withAlphaComponent(0.15).cgColor
        hoverLayer.strokeColor = NSColor.white.withAlphaComponent(0.5).cgColor
        hoverLayer.lineWidth = 1.0
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func layout() {
        super.layout()
        hoverLayer.frame = bounds
        // Size changed — invalidate
        if cachedSize != bounds.size {
            cachedImage = nil
            coordinator?.invalidateLayout()
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }

        // Reuse cached image if valid
        if cachedImage == nil || cachedSize != size {
            cachedImage = renderTreemap(size: size)
            cachedSize = size
        }

        if let img = cachedImage {
            // CGContext.draw draws images bottom-up, but our view is flipped.
            // Un-flip before drawing the pre-rendered image.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        }
    }

    func updateHoverOverlay() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let hovered = coordinator?.hoveredNode {
            // Find the rect for this node
            if let rect = coordinator.leafRects.last(where: { $0.node === hovered }) {
                let path = CGPath(rect: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), transform: nil)
                hoverLayer.path = path
                hoverLayer.isHidden = false
            } else {
                hoverLayer.isHidden = true
            }
        } else {
            hoverLayer.isHidden = true
        }
        CATransaction.commit()
    }

    // MARK: - Full treemap render to CGImage

    private func renderTreemap(size: CGSize) -> CGImage? {
        coordinator.ensureLayout(size: size)

        let scale = window?.backingScaleFactor ?? 2.0
        let w = Int(size.width * scale)
        let h = Int(size.height * scale)
        guard w > 0, h > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Flip coordinate system to match isFlipped=true
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)

        // Push as current NSGraphicsContext so NSAttributedString.draw works
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        // Background
        ctx.setFillColor(NSColor.controlBackgroundColor.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        let lightX: Double = -0.09
        let lightY: Double = -0.09
        let ambientLight: Double = 0.12

        // Draw directory frames
        for frame in coordinator.dirFrames {
            let cgRect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            let brightness: CGFloat = frame.depth == 0 ? 0.18 : min(0.14 + CGFloat(frame.depth) * 0.02, 0.25)
            ctx.setFillColor(gray: brightness, alpha: 1)
            ctx.fill(cgRect)

            // Header label at top levels
            if frame.depth <= 1 && frame.width > 70 && frame.height > 20 {
                let headerH = min(12.0, frame.height * 0.1)
                let headerRect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: headerH)
                ctx.setFillColor(gray: 0.22, alpha: 1)
                ctx.fill(headerRect)

                // Draw header text
                let fontSize = max(7.0, min(9.0, headerH * 0.75))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: NSColor(white: 0.65, alpha: 1)
                ]
                let str = NSAttributedString(string: frame.node.name, attributes: attrs)
                let textRect = CGRect(x: frame.x + 3, y: frame.y + 1, width: frame.width - 6, height: headerH - 2)
                str.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }
        }

        // Draw leaf cells with cushion shading
        for rect in coordinator.leafRects {
            let cgRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            let baseNSColor = resolveNSColor(for: rect.node)

            // Cushion intensity
            let cx = rect.x + rect.width / 2
            let cy = rect.y + rect.height / 2
            let iTL = cushionIntensity(rect: rect, px: rect.x + 0.5, py: rect.y + 0.5,
                                        lightX: lightX, lightY: lightY, ambient: ambientLight)
            let iC = cushionIntensity(rect: rect, px: cx, py: cy,
                                       lightX: lightX, lightY: lightY, ambient: ambientLight)
            let iBR = cushionIntensity(rect: rect, px: rect.x + rect.width - 0.5, py: rect.y + rect.height - 0.5,
                                        lightX: lightX, lightY: lightY, ambient: ambientLight)
            let avgI = (iTL + iC + iBR) / 3.0

            // Base fill — convert to sRGB to avoid crash on catalog colors
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            let rgbColor = baseNSColor.usingColorSpace(.sRGB) ?? baseNSColor
            rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            ctx.setFillColor(red: r * CGFloat(avgI), green: g * CGFloat(avgI), blue: b * CGFloat(avgI), alpha: a)
            ctx.fill(cgRect)

            // Cushion gradient overlay (highlight top-left, shadow bottom-right)
            if rect.width > 3 && rect.height > 3 {
                let hlStr = CGFloat(max(0, iTL - iBR) * 0.5)
                let shStr = CGFloat(iBR < 0.5 ? (0.5 - iBR) * 0.35 : 0)

                if hlStr > 0.01 {
                    // Simple top-left highlight
                    let hlRect = CGRect(x: rect.x, y: rect.y,
                                        width: rect.width * 0.5, height: rect.height * 0.5)
                    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: hlStr)
                    ctx.fill(hlRect)
                }
                if shStr > 0.01 {
                    // Bottom-right shadow
                    let shRect = CGRect(x: rect.x + rect.width * 0.5, y: rect.y + rect.height * 0.5,
                                        width: rect.width * 0.5, height: rect.height * 0.5)
                    ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: shStr)
                    ctx.fill(shRect)
                }
            }

            // Text label (only for larger cells)
            if rect.width > 48 && rect.height > 15 {
                let fontSize = max(8.0, min(11.0, rect.height * 0.28))
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: NSColor.white
                ]
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
                shadow.shadowOffset = NSSize(width: 0.5, height: -0.5)
                shadow.shadowBlurRadius = 1
                let attrsWithShadow: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                    .foregroundColor: NSColor.white,
                    .shadow: shadow
                ]
                let str = NSAttributedString(string: rect.node.name, attributes: attrsWithShadow)
                let textRect = CGRect(x: rect.x + 3, y: rect.y + (rect.height - fontSize - 4) / 2,
                                      width: rect.width - 6, height: fontSize + 4)
                str.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            }
        }

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    private func cushionIntensity(rect: TreemapRect, px: Double, py: Double,
                                   lightX: Double, lightY: Double, ambient: Double) -> Double {
        let dfx = -2.0 * rect.cushionX.a * px + rect.cushionX.b
        let dfy = -2.0 * rect.cushionY.a * py + rect.cushionY.b
        let nx = -dfx, ny = -dfy, nz = 1.0
        let len = sqrt(nx * nx + ny * ny + nz * nz)
        guard len > 0 else { return ambient }
        return max(ambient, (lightX * nx + lightY * ny + nz) / len)
    }

    private func resolveNSColor(for node: FileNode) -> NSColor {
        if node.isDirectory { return NSColor.gray.withAlphaComponent(0.4) }

        guard let coord = coordinator else { return .gray }
        switch coord.colorMode {
        case .fileType:
            let ext = node.fileExtension.isEmpty ? "(no extension)" : node.fileExtension
            return NSColor(FileTypeColorMap.color(for: ext))
        case .age:
            return ageNSColor(for: node)
        case .size:
            return sizeNSColor(for: node)
        }
    }

    private func ageNSColor(for node: FileNode) -> NSColor {
        guard let date = node.modificationDate, let coord = coordinator else { return .gray }
        let totalRange = coord.globalNewestDate.timeIntervalSince(coord.globalOldestDate)
        guard totalRange > 0 else { return NSColor(calibratedHue: 0.33, saturation: 0.7, brightness: 0.85, alpha: 1) }
        let f = date.timeIntervalSince(coord.globalOldestDate) / totalRange
        if f < 0.25 {
            let t = CGFloat(f / 0.25)
            return NSColor(calibratedHue: lerp(0.65, 0.33, t), saturation: 0.7, brightness: lerp(0.6, 0.75, t), alpha: 1)
        } else if f < 0.5 {
            let t = CGFloat((f - 0.25) / 0.25)
            return NSColor(calibratedHue: lerp(0.33, 0.16, t), saturation: 0.7, brightness: lerp(0.75, 0.85, t), alpha: 1)
        } else if f < 0.75 {
            let t = CGFloat((f - 0.5) / 0.25)
            return NSColor(calibratedHue: lerp(0.16, 0.08, t), saturation: lerp(0.7, 0.8, t), brightness: lerp(0.85, 0.9, t), alpha: 1)
        } else {
            let t = CGFloat((f - 0.75) / 0.25)
            return NSColor(calibratedHue: lerp(0.08, 0.0, t), saturation: lerp(0.8, 0.9, t), brightness: lerp(0.9, 0.85, t), alpha: 1)
        }
    }

    private func sizeNSColor(for node: FileNode) -> NSColor {
        guard let coord = coordinator, coord.maxFileSize > 0 else { return .gray }
        let logSize = log10(Double(max(node.size, 1)))
        let logMax = log10(Double(max(coord.maxFileSize, 1)))
        let f = min(logSize / logMax, 1.0)
        if f < 0.5 {
            let t = CGFloat(f / 0.5)
            return NSColor(calibratedHue: lerp(0.33, 0.16, t), saturation: lerp(0.5, 0.7, t), brightness: lerp(0.7, 0.85, t), alpha: 1)
        } else {
            let t = CGFloat((f - 0.5) / 0.5)
            return NSColor(calibratedHue: lerp(0.16, 0.0, t), saturation: lerp(0.7, 0.9, t), brightness: lerp(0.85, 0.8, t), alpha: 1)
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    // MARK: - Mouse events

    func invalidateCache() {
        cachedImage = nil
        cachedSize = .zero
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let hit = coordinator.hitTest(pt)
        if hit !== coordinator.hoveredNode {
            coordinator.hoveredNode = hit
            updateHoverOverlay()
            Task { @MainActor in
                self.coordinator.hoverState.hoveredNode = hit
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        if coordinator.hoveredNode != nil {
            coordinator.hoveredNode = nil
            updateHoverOverlay()
            Task { @MainActor in
                self.coordinator.hoverState.hoveredNode = nil
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2 {
            if let hit = coordinator.hitTest(pt), let parent = hit.parent, parent.isDirectory {
                coordinator.onNavigate(parent)
            } else if let dir = coordinator.hitTestDirectory(pt) {
                coordinator.onNavigate(dir)
            }
        } else {
            if let hit = coordinator.hitTest(pt) {
                coordinator.onSelect(hit)
            }
        }
    }
}
