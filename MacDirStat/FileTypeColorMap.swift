import SwiftUI

enum FileTypeColorMap {
    // Vibrant but balanced palette — rich colors, not washed out
    private static let categoryColors: [(Set<String>, Color)] = [
        // Images — vivid blue
        (["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "svg", "ico", "heic", "heif", "raw", "cr2", "nef"],
         Color(red: 0.25, green: 0.56, blue: 0.90)),
        // Video — rich purple
        (["mp4", "avi", "mkv", "mov", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "3gp"],
         Color(red: 0.58, green: 0.34, blue: 0.80)),
        // Audio — vibrant rose
        (["mp3", "wav", "flac", "aac", "ogg", "wma", "m4a", "aiff", "alac", "opus"],
         Color(red: 0.88, green: 0.36, blue: 0.52)),
        // Documents — warm orange-gold
        (["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf", "tex", "pages", "numbers", "keynote"],
         Color(red: 0.93, green: 0.65, blue: 0.22)),
        // Archives — burnt sienna
        (["zip", "tar", "gz", "bz2", "7z", "rar", "xz", "zst", "dmg", "iso", "pkg", "deb", "rpm"],
         Color(red: 0.78, green: 0.44, blue: 0.28)),
        // Source code — emerald green
        (["swift", "m", "h", "c", "cpp", "cc", "cxx", "rs", "go", "py", "rb", "java", "kt", "scala", "cs", "fs",
          "js", "ts", "jsx", "tsx", "vue", "svelte", "html", "css", "scss", "less", "php", "pl", "r", "lua", "sh", "bash", "zsh", "fish"],
         Color(red: 0.22, green: 0.72, blue: 0.52)),
        // Config / Data — steel blue
        (["json", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf", "plist", "csv", "tsv", "sql", "graphql", "proto"],
         Color(red: 0.40, green: 0.58, blue: 0.78)),
        // Executables / Libraries — strong red
        (["exe", "dll", "so", "dylib", "a", "o", "app", "framework", "bundle", "wasm"],
         Color(red: 0.85, green: 0.30, blue: 0.30)),
        // Text / Markdown — olive green
        (["txt", "md", "markdown", "rst", "log", "readme", "license", "changelog"],
         Color(red: 0.52, green: 0.70, blue: 0.35)),
        // Fonts — plum
        (["ttf", "otf", "woff", "woff2", "eot"],
         Color(red: 0.70, green: 0.42, blue: 0.70)),
        // Database — deep teal
        (["db", "sqlite", "sqlite3", "realm", "mdb", "accdb"],
         Color(red: 0.20, green: 0.58, blue: 0.66)),
        // 3D / CAD — goldenrod
        (["obj", "fbx", "stl", "blend", "dae", "3ds", "gltf", "glb", "usdz"],
         Color(red: 0.82, green: 0.68, blue: 0.32)),
    ]

    private static var cache: [String: Color] = [:]

    static func color(for ext: String) -> Color {
        let key = ext.lowercased()
        if key == "(no extension)" {
            return Color(red: 0.50, green: 0.50, blue: 0.55)
        }
        if let cached = cache[key] { return cached }
        for (extensions, color) in categoryColors {
            if extensions.contains(key) {
                cache[key] = color
                return color
            }
        }
        let c = hashColor(for: key)
        cache[key] = c
        return c
    }

    private static func hashColor(for key: String) -> Color {
        var hasher = Hasher()
        hasher.combine(key)
        let hash = abs(hasher.finalize())
        let hue = Double(hash % 1000) / 1000.0
        let sat = 0.50 + Double(hash / 1000 % 20) / 100.0   // 0.50–0.70
        let bri = 0.60 + Double(hash / 20000 % 25) / 100.0  // 0.60–0.85
        return Color(hue: hue, saturation: sat, brightness: bri)
    }
}
