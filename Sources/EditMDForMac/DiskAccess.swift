import Foundation

struct DiskVersion: Equatable {
    let data: Data
    let text: String
    init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        self.data = data
        self.text = text
    }
    init(text: String) { self.data = Data(text.utf8); self.text = text }
}

enum DiskWriteResult {
    case written(DiskVersion)
    case changed(DiskVersion?)
}

/// Content is checked inside the coordinated write, not just when the watcher
/// fires. Atomic replacement is safe for readers; unrelated writers must also
/// cooperate with NSFileCoordinator to close the final concurrent-write race.
enum DiskAccess {
    static func read(_ url: URL) throws -> DiskVersion {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<DiskVersion, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinated in
            result = Result { try DiskVersion(data: Data(contentsOf: coordinated)) }
        }
        if let coordinationError { throw coordinationError }
        return try (result ?? .failure(CocoaError(.fileReadUnknown))).get()
    }

    static func write(_ text: String, to url: URL, expecting expected: DiskVersion?) throws -> DiskWriteResult {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<DiskWriteResult, Error>?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
            result = Result {
                let exists = FileManager.default.fileExists(atPath: coordinated.path)
                let current = exists ? try DiskVersion(data: Data(contentsOf: coordinated)) : nil
                guard current == expected else { return .changed(current) }
                try text.write(to: coordinated, atomically: true, encoding: .utf8)
                return .written(DiskVersion(text: text))
            }
        }
        if let coordinationError { throw coordinationError }
        return try (result ?? .failure(CocoaError(.fileWriteUnknown))).get()
    }
}
