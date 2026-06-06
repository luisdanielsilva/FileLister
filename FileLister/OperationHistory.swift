import Foundation
import Combine

// One reversible operation. `trashed` = files sent to Trash (restore by moving the
// Trash URL back to the original). `created` = files/folders we wrote (undo by deleting).
struct UndoableOp {
    let title: String
    var trashed: [(trashURL: URL, original: URL)] = []
    var created: [URL] = []
    var isEmpty: Bool { trashed.isEmpty && created.isEmpty }
}

final class OperationHistory: ObservableObject {
    static let shared = OperationHistory()

    @Published private(set) var canUndo = false
    @Published private(set) var lastTitle = ""
    private var stack: [UndoableOp] = []

    func push(_ op: UndoableOp) {
        guard !op.isEmpty else { return }
        stack.append(op)
        refresh()
    }

    private func refresh() {
        canUndo = !stack.isEmpty
        lastTitle = stack.last?.title ?? ""
    }

    struct UndoResult {
        let status: String
        let restoredOriginals: [String]   // original paths that came back from Trash
        let removedCreated: [String]      // copy paths that were removed
    }

    @discardableResult
    func undoLast() -> UndoResult? {
        guard let op = stack.popLast() else { return nil }
        refresh()
        let fm = FileManager.default
        var restored = 0, removed = 0, errors = 0
        var restoredOriginals: [String] = []
        var removedCreated: [String] = []

        // 1. restore trashed files to their original locations
        for item in op.trashed {
            var dest = item.original
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { dest = Self.uniqueURL(dest) }
            do {
                try fm.moveItem(at: item.trashURL, to: dest)
                restored += 1
                restoredOriginals.append(item.original.path)
            } catch {
                errors += 1
            }
        }

        // 2. remove files/folders we had created
        for url in op.created {
            do { try fm.removeItem(at: url); removed += 1; removedCreated.append(url.path) }
            catch { errors += 1 }
        }

        var parts: [String] = []
        if restored > 0 { parts.append("restored \(restored) file(s)") }
        if removed > 0 { parts.append("removed \(removed) copy(ies)") }
        if errors > 0 { parts.append("\(errors) error(s)") }
        let status = "Undo \"\(op.title)\": " + (parts.isEmpty ? "nothing to do" : parts.joined(separator: " · "))
        return UndoResult(status: status, restoredOriginals: restoredOriginals, removedCreated: removedCreated)
    }

    private static func uniqueURL(_ url: URL) -> URL {
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : String(url.lastPathComponent.dropLast(ext.count + 1))
        let dir = url.deletingLastPathComponent()
        var n = 1
        var candidate = url
        let fm = FileManager.default
        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (restored \(n))" : "\(base) (restored \(n)).\(ext)"
            candidate = dir.appendingPathComponent(name)
            n += 1
        }
        return candidate
    }
}
