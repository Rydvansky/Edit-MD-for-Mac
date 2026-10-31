import Foundation

@main
struct DocumentSessionChecks {
    static func main() {
        var session = DocumentSession(text: "disk")
        let id = session.id
        precondition(!session.isDirty)
        precondition(!session.accept(EditorSnapshot(documentID: UUID(), revision: 20, markdown: "wrong file")))
        precondition(session.markEdited(documentID: id, revision: 1))
        precondition(session.isDirty && session.hasPendingEdits)
        precondition(!session.accept(EditorSnapshot(documentID: id, revision: 0, markdown: "late payload")))
        precondition(session.accept(EditorSnapshot(documentID: id, revision: 1, markdown: "first edit")))
        let writing = session.snapshot
        precondition(session.markEdited(documentID: id, revision: 2))
        session.didSave(writing)
        precondition(session.isDirty && session.hasPendingEdits, "An old save must not clear a newer pending edit")
        precondition(session.accept(EditorSnapshot(documentID: id, revision: 2, markdown: "second edit")))
        session.didSave(writing)
        precondition(session.isDirty && session.savedText == "first edit")
        session.didSave(session.snapshot)
        precondition(!session.isDirty)
        precondition(session.markEdited(documentID: id, revision: 3))
        precondition(session.accept(EditorSnapshot(documentID: id, revision: 3, markdown: session.savedText)))
        precondition(!session.isDirty, "Undo to saved content should be clean")
        var reopened = DocumentSession(text: "other document")
        reopened.didSave(writing)
        precondition(reopened.savedText == "other document")
        precondition(!reopened.markEdited(documentID: id, revision: 50))
        print("PASS: document identity, stale revisions, pending edits, save race, saved baseline, undo")
    }
}
