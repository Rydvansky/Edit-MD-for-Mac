import AppKit

/// Watch the parent, because atomic saves replace the file's inode. Polling
/// metadata and focus/wake checks cover dropped events and recreated folders.
final class FileObservation {
    private let queue = DispatchQueue(label: "EditMD.file-observation", qos: .utility)
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var pending: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    private let url: URL
    private let changed: @Sendable () -> Void
    private var stamp: String = ""

    init(url: URL, changed: @escaping @Sendable () -> Void) {
        self.url = url
        self.changed = changed
        armDirectory()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let next = [FileAttributeKey.modificationDate, .size, .systemFileNumber].map { String(describing: attributes?[$0]) }.joined(separator: ":")
            if next != stamp { stamp = next; changed() }
            if source == nil { armDirectory() }
        }
        self.timer = timer
        timer.resume()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in changed() })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil) { _ in changed() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in changed() })
    }

    private func armDirectory() {
        let descriptor = open(url.deletingLastPathComponent().path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .attrib, .revoke], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.changed() }
            pending = work
            queue.asyncAfter(deadline: .now() + 0.25, execute: work)
            if !(self.source?.data ?? []).intersection([.delete, .rename, .revoke]).isEmpty {
                self.source?.cancel()
                self.source = nil
            }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    deinit {
        pending?.cancel()
        source?.cancel()
        timer?.cancel()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
