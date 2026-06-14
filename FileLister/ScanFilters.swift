import Foundation
import Combine

// Global include/exclude rules applied to every search (local Files/Folders/Photos
// and remote). #18. Session-only — reset on each launch, edited from the toolbar
// Filters button.
//
// Precedence: an excluded folder removes matching files; an excluded extension always
// wins, and if an include list is set only those extensions pass.
final class ScanFilters: ObservableObject {
    static let shared = ScanFilters()

    // Raw, comma-separated text (what the Filters popover fields bind to).
    @Published var excludeFolders: String = "" { didSet { rebuild() } }
    @Published var includeExtensions: String = "" { didSet { rebuild() } }
    @Published var excludeExtensions: String = "" { didSet { rebuild() } }

    // Cached normalized lookup sets (rebuilt on edit).
    private var excludedFolderSet: Set<String> = []
    private var includedExtSet: Set<String> = []
    private var excludedExtSet: Set<String> = []

    private init() {}

    var isActive: Bool {
        !excludedFolderSet.isEmpty || !includedExtSet.isEmpty || !excludedExtSet.isEmpty
    }

    // A folder (by name, matched anywhere in the tree) whose entire subtree is skipped.
    func shouldSkipFolder(named name: String) -> Bool {
        excludedFolderSet.contains(name.lowercased())
    }

    // Whether a file passes the extension rules.
    func allowsFile(named name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        if excludedExtSet.contains(ext) { return false }
        if !includedExtSet.isEmpty && !includedExtSet.contains(ext) { return false }
        return true
    }

    // Post-search test for one file by its full path: extension rules + no excluded
    // folder anywhere in its parent path. Used to filter already-scanned results.
    func allows(fullPath: String) -> Bool {
        if !isActive { return true }
        let url = URL(fileURLWithPath: fullPath)
        if !allowsFile(named: url.lastPathComponent) { return false }
        if !excludedFolderSet.isEmpty {
            for comp in url.deletingLastPathComponent().pathComponents
            where excludedFolderSet.contains(comp.lowercased()) { return false }
        }
        return true
    }

    private func rebuild() {
        excludedFolderSet = Self.parseNames(excludeFolders)
        includedExtSet = Self.parseExtensions(includeExtensions)
        excludedExtSet = Self.parseExtensions(excludeExtensions)
    }

    // Folder names: split on commas only (names may contain spaces).
    private static func parseNames(_ s: String) -> Set<String> {
        Set(s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty })
    }

    // Extensions: split on commas/space/semicolon; tolerate a leading dot.
    private static func parseExtensions(_ s: String) -> Set<String> {
        Set(s.split(whereSeparator: { ",; \n\t".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty })
    }
}
