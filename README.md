# MacDiskScope

A fast, native macOS disk space analyzer with hierarchical cushion treemap visualization — like WinDirStat/WizTree for Mac.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### Visualize Your Storage
- **Cushion treemap** — files shown as colored rectangles sized by disk usage, with hierarchical nesting that reveals the directory structure
- **Three color modes** — color by file type, file age, or file size
- **Drill down** — double-click any folder to zoom in, breadcrumb navigation to go back

### Fast & Lightweight  
- Scans hundreds of thousands of files in seconds
- Cached bitmap rendering (Core Graphics) for smooth interaction
- Native SwiftUI + AppKit — no Electron, no web views

### Understand Your Files
- **Inspector panel** with file counts, folder depth, average sizes, top extensions
- **File type breakdown** with percentages and color-coded bars
- **Quick Look** — press Space to preview any file, arrow keys to browse (just like Finder)

### Take Action
- Move to Trash or relocate files directly
- Reveal in Finder, open with default app, copy path
- Optional real-time FSEvents monitoring for live updates

## Screenshots

*Scan a folder, then explore the treemap and tree view.*

## Building

### Requirements
- macOS 14.0+
- Xcode 15.0+

### Build & Run
```bash
# Clone
git clone https://github.com/YOUR_USERNAME/MacDiskScope.git
cd MacDiskScope

# Build
xcodebuild -project MacDirStat.xcodeproj -scheme MacDiskScope -configuration Release build

# Or open in Xcode
open MacDirStat.xcodeproj
```

### Create DMG
```bash
./build_dmg.sh
```

## Architecture

| File | Purpose |
|---|---|
| `DirectoryScanner.swift` | Fast async directory traversal with progress callbacks |
| `FSEventsMonitor.swift` | Real-time file system change monitoring |
| `FileNode.swift` | Tree data model with cached sorting and statistics |
| `TreemapLayout.swift` | Squarified treemap algorithm with cushion surface math |
| `TreemapView.swift` | NSView-based bitmap-cached treemap renderer |
| `DirectoryTreeView.swift` | NSOutlineView-backed tree with Quick Look and context menus |
| `InfoPanelView.swift` | Detailed statistics inspector panel |
| `FileTypeColorMap.swift` | File extension to color mapping |
| `ScanState.swift` | Main app state with sandbox/bookmark support |

## License

MIT License — see [LICENSE](LICENSE) for details.
