import Foundation

enum FormatUtils {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func formatBytes(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    static func formatCount(_ count: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    static func percentString(_ part: Int64, of total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let pct = Double(part) / Double(total) * 100.0
        if pct < 0.1 { return "<0.1%" }
        return String(format: "%.1f%%", pct)
    }
}
