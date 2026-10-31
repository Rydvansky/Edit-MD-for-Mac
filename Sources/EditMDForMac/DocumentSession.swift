import Foundation

struct EditorSnapshot: Equatable {
    let documentID: UUID
    let revision: Int
    let markdown: String
}

/// The native host owns document identity and the saved baseline. The editor
/// assigns increasing revisions to its transactions, including debounced edits.
struct DocumentSession {
    let id: UUID
    private(set) var revision = 0
    private(set) var text: String
    private(set) var savedText: String
    private(set) var hasPendingEdits = false

    init(text: String = "", id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.savedText = text
    }

    var isDirty: Bool { hasPendingEdits || text != savedText }
    var snapshot: EditorSnapshot { EditorSnapshot(documentID: id, revision: revision, markdown: text) }

    @discardableResult
    mutating func markEdited(documentID: UUID, revision: Int) -> Bool {
        guard documentID == id, revision > self.revision else { return false }
        self.revision = revision
        hasPendingEdits = true
        return true
    }

    @discardableResult
    mutating func accept(_ snapshot: EditorSnapshot) -> Bool {
        guard snapshot.documentID == id, snapshot.revision >= revision else { return false }
        revision = snapshot.revision
        text = snapshot.markdown
        hasPendingEdits = false
        return true
    }

    mutating func didSave(_ snapshot: EditorSnapshot) {
        guard snapshot.documentID == id else { return }
        savedText = snapshot.markdown
        // Never clear a newer pending edit when an older write finishes.
    }
}

@MainActor
protocol DocumentEditor: AnyObject {
    func loadDocument()
    func snapshot(lock: Bool) async throws -> EditorSnapshot?
    func replaceContent(_ markdown: String, expectedRevision: Int?) async throws -> EditorSnapshot
    func showComparison(base: String, disk: String?, token: String, issue: String?)
    func clearComparison()
    func setBaseline(_ markdown: String, revision: Int)
    func resumeEditing()
    func updateContext()
    func setSaveState(_ state: String, revision: Int)
    func adjustTextSize(by delta: Int)
}
