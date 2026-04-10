import Foundation

struct TreemapRect {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let node: FileNode
    let depth: Int
    let isDirectoryFrame: Bool

    /// Accumulated cushion surface coefficients per axis.
    /// Each ancestor contributes a parabola: h * 4 * (p - lo) * (hi - p) / (hi - lo)^2
    /// We track the sum of these as (a, b, c) coefficients for a*x^2 + b*x + c per axis.
    let cushionX: CushionAxis
    let cushionY: CushionAxis

    var area: Double { width * height }

    struct CushionAxis {
        var a: Double = 0
        var b: Double = 0

        static let zero = CushionAxis(a: 0, b: 0)

        /// Add a parabolic bump for the range [lo, hi] with the given height factor.
        func adding(lo: Double, hi: Double, h: Double) -> CushionAxis {
            let range = hi - lo
            guard range > 0 else { return self }
            var result = self
            result.a += h / (range * range)
            result.b += h * 2.0 * lo / (range * range)
            return result
        }

        /// Evaluate the cushion surface height at position p
        func evaluate(at p: Double) -> Double {
            // f(p) = sum of h_i * 4 * (p - lo_i)(hi_i - p) / (hi_i - lo_i)^2
            // Each addParabola contributes: a*p^2 + b*p piece
            // But we track it differently — let's use the direct parabola approach
            return -(a * p * p) + b * p
        }
    }
}

enum TreemapLayout {
    /// Squarified treemap algorithm - produces rectangles with aspect ratios close to 1
    static func layout(nodes: [FileNode], in rect: CGRect, minSize: Double = 2.0) -> [TreemapRect] {
        let totalSize = nodes.reduce(Int64(0)) { $0 + $1.size }
        guard totalSize > 0, rect.width > 0, rect.height > 0 else { return [] }

        let sorted = nodes.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        guard !sorted.isEmpty else { return [] }

        var results: [TreemapRect] = []
        squarify(
            items: sorted,
            totalSize: totalSize,
            rect: LayoutRect(x: rect.minX, y: rect.minY, w: Double(rect.width), h: Double(rect.height)),
            minSize: minSize,
            depth: 0,
            cushionX: .zero,
            cushionY: .zero,
            results: &results
        )
        return results
    }

    private struct LayoutRect {
        var x, y, w, h: Double
        var area: Double { w * h }
        var shortSide: Double { min(w, h) }
    }

    private static func squarify(
        items: [FileNode],
        totalSize: Int64,
        rect: LayoutRect,
        minSize: Double,
        depth: Int,
        cushionX: TreemapRect.CushionAxis,
        cushionY: TreemapRect.CushionAxis,
        results: inout [TreemapRect]
    ) {
        guard !items.isEmpty, rect.w >= minSize, rect.h >= minSize else { return }

        if items.count == 1 {
            results.append(TreemapRect(
                x: rect.x, y: rect.y, width: rect.w, height: rect.h,
                node: items[0], depth: depth, isDirectoryFrame: false,
                cushionX: cushionX.adding(lo: rect.x, hi: rect.x + rect.w, h: cushionHeight(for: depth)),
                cushionY: cushionY.adding(lo: rect.y, hi: rect.y + rect.h, h: cushionHeight(for: depth))
            ))
            return
        }

        let totalArea = rect.area
        let shortSide = rect.shortSide

        var row: [FileNode] = []
        var rowSize: Int64 = 0
        var bestWorst: Double = .infinity
        let remaining = items
        var bestSplit = 0

        for i in 0..<remaining.count {
            let item = remaining[i]
            row.append(item)
            rowSize += item.size

            let worst = worstAspectRatio(row: row, rowSize: rowSize, totalSize: totalSize, totalArea: totalArea, shortSide: shortSide)

            if worst <= bestWorst {
                bestWorst = worst
                bestSplit = i + 1
            } else {
                break
            }
        }

        let rowItems = Array(remaining[0..<bestSplit])
        let rest = Array(remaining[bestSplit...])
        let rowTotal: Int64 = rowItems.reduce(0) { $0 + $1.size }
        let rowFraction = Double(rowTotal) / Double(totalSize)

        let isHorizontal = rect.w >= rect.h

        if isHorizontal {
            let rowWidth = rect.w * rowFraction
            var offsetY = rect.y
            for item in rowItems {
                let itemFraction = Double(item.size) / Double(rowTotal)
                let itemHeight = rect.h * itemFraction
                if rowWidth >= minSize && itemHeight >= minSize {
                    let cx = cushionX.adding(lo: rect.x, hi: rect.x + rowWidth, h: cushionHeight(for: depth))
                    let cy = cushionY.adding(lo: offsetY, hi: offsetY + itemHeight, h: cushionHeight(for: depth))
                    results.append(TreemapRect(
                        x: rect.x, y: offsetY, width: rowWidth, height: itemHeight,
                        node: item, depth: depth, isDirectoryFrame: false,
                        cushionX: cx, cushionY: cy
                    ))
                }
                offsetY += itemHeight
            }

            if !rest.isEmpty {
                let newRect = LayoutRect(x: rect.x + rowWidth, y: rect.y, w: rect.w - rowWidth, h: rect.h)
                squarify(items: rest, totalSize: totalSize - rowTotal, rect: newRect, minSize: minSize,
                         depth: depth, cushionX: cushionX, cushionY: cushionY, results: &results)
            }
        } else {
            let rowHeight = rect.h * rowFraction
            var offsetX = rect.x
            for item in rowItems {
                let itemFraction = Double(item.size) / Double(rowTotal)
                let itemWidth = rect.w * itemFraction
                if itemWidth >= minSize && rowHeight >= minSize {
                    let cx = cushionX.adding(lo: offsetX, hi: offsetX + itemWidth, h: cushionHeight(for: depth))
                    let cy = cushionY.adding(lo: rect.y, hi: rect.y + rowHeight, h: cushionHeight(for: depth))
                    results.append(TreemapRect(
                        x: offsetX, y: rect.y, width: itemWidth, height: rowHeight,
                        node: item, depth: depth, isDirectoryFrame: false,
                        cushionX: cx, cushionY: cy
                    ))
                }
                offsetX += itemWidth
            }

            if !rest.isEmpty {
                let newRect = LayoutRect(x: rect.x, y: rect.y + rowHeight, w: rect.w, h: rect.h - rowHeight)
                squarify(items: rest, totalSize: totalSize - rowTotal, rect: newRect, minSize: minSize,
                         depth: depth, cushionX: cushionX, cushionY: cushionY, results: &results)
            }
        }
    }

    /// Cushion height decreases with depth so deeper levels add less curvature
    private static func cushionHeight(for depth: Int) -> Double {
        0.5 * pow(0.75, Double(depth))
    }

    private static func worstAspectRatio(row: [FileNode], rowSize: Int64, totalSize: Int64, totalArea: Double, shortSide: Double) -> Double {
        guard shortSide > 0, totalSize > 0 else { return .infinity }

        let rowAreaFraction = Double(rowSize) / Double(totalSize)
        let rowArea = totalArea * rowAreaFraction
        let rowLength = rowArea / shortSide

        guard rowLength > 0 else { return .infinity }

        var worst: Double = 0
        for item in row {
            let itemFraction = Double(item.size) / Double(rowSize)
            let itemSize = shortSide * itemFraction
            let aspect = max(rowLength / itemSize, itemSize / rowLength)
            worst = max(worst, aspect)
        }
        return worst
    }
}
