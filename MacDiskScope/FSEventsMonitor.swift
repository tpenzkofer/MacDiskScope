import Foundation
import CoreServices

final class FSEventsMonitor {
    typealias ChangeHandler = (_ changedPaths: [String]) -> Void

    private var stream: FSEventStreamRef?
    private let path: String
    private let handler: ChangeHandler
    private let debounceInterval: TimeInterval

    private var pendingPaths: Set<String> = []
    private var debounceTimer: Timer?
    private let lock = NSLock()

    init(path: String, debounceInterval: TimeInterval = 1.0, handler: @escaping ChangeHandler) {
        self.path = path
        self.handler = handler
        self.debounceInterval = debounceInterval
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil else { return }

        let pathsToWatch = [path] as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagNoDefer)

        guard let eventStream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // latency
            flags
        ) else { return }

        stream = eventStream
        FSEventStreamSetDispatchQueue(eventStream, DispatchQueue.main)
        FSEventStreamStart(eventStream)
    }

    func stop() {
        debounceTimer?.invalidate()
        debounceTimer = nil

        guard let eventStream = stream else { return }
        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        stream = nil
    }

    fileprivate func handleEvents(_ paths: [String]) {
        lock.lock()
        // Collect parent directories of changed paths (we rescan at directory level)
        for p in paths {
            let parentDir = (p as NSString).deletingLastPathComponent
            pendingPaths.insert(parentDir)
        }
        lock.unlock()

        // Debounce: reset timer on each event burst
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.debounceTimer?.invalidate()
            self.debounceTimer = Timer.scheduledTimer(withTimeInterval: self.debounceInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock()
                let paths = Array(self.pendingPaths)
                self.pendingPaths.removeAll()
                self.lock.unlock()

                if !paths.isEmpty {
                    self.handler(paths)
                }
            }
        }
    }
}

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(info).takeUnretainedValue()

    guard let cfPaths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

    monitor.handleEvents(cfPaths)
}
