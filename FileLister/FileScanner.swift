import Foundation
import SwiftUI
import Combine
import AppKit
import CryptoKit

enum SortCriteria {
    case name, size, count, matchRatio
}

enum SortOrderEnum {
    case ascending, descending
}

enum MergeNamePosition {
    case prefix, suffix
}

enum ScanScope {
    case combined   // pool all selected folders — duplicates found across them
    case perFolder  // scan each selected folder independently
}

struct DuplicateFileInfo: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let name: String
    let size: String
    let sizeBytes: Int
    var isSymlink: Bool = false
    var modificationDate: Date? = nil
    var sha256: String? = nil

    var fullPath: String {
        return (path as NSString).appendingPathComponent(name)
    }
}

struct ConfidenceSignal {
    let name: String
    let score: Double    // 0.0–1.0
    let weight: Double
    let detail: String
}

struct DuplicateConfidence {
    let overall: Double  // weighted sum, 0.0–1.0
    let signals: [ConfidenceSignal]

    var label: String {
        switch overall {
        case 0.75...: return "Very likely accidental"
        case 0.5..<0.75: return "Probably accidental"
        case 0.3..<0.5: return "Uncertain"
        default: return "Possibly intentional"
        }
    }

    var tooltipText: String {
        var lines: [String] = [
            "Confidence: \(Int(overall * 100))% — \(label)",
            ""
        ]
        for s in signals {
            lines.append("• \(s.name): \(Int(s.score * 100))%  (weight \(Int(s.weight * 100))%)")
            lines.append("  \(s.detail)")
        }
        return lines.joined(separator: "\n")
    }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let sizeBytes: Int
    let files: [DuplicateFileInfo]
    var isSymlinkGroup: Bool = false
    var confidence: DuplicateConfidence? = nil
    var rootFolder: String? = nil   // set in per-folder scope so results can be sectioned
}

struct FolderDuplicateGroup: Identifiable {
    let id = UUID()
    let folders: [String]                   // cluster of duplicate folders; folders[0] = keep
    let matchedGroups: [DuplicateGroup]     // content groups with 2+ copies in the cluster (removable dups)
    let uniqueToKeep: [DuplicateFileInfo]   // contents present only in the keep folder (unchanged on merge)
    let filesToMove: [DuplicateFileInfo]    // one representative per distinct content the keep folder lacks
    let matchRatio: Double                  // 0.5–1.0 (max pairwise similarity in the cluster)
    var rootFolder: String? = nil           // set in per-folder scope so results can be sectioned

    // Keep is the first (largest) folder; the rest are merged into it then removed.
    var keepFolder: String { folders.first ?? "" }
    var otherFolders: [String] { Array(folders.dropFirst()) }

    // Back-compat shims for the (pair-oriented) UI. folderB is a representative
    // of the "other" side; for 3+ folder clusters the UI also shows the count.
    var folderA: String { keepFolder }
    var folderB: String { otherFolders.first ?? keepFolder }
    var uniqueToA: [DuplicateFileInfo] { uniqueToKeep }
    var uniqueToB: [DuplicateFileInfo] { filesToMove }

    var totalSizeBytes: Int {
        matchedGroups.reduce(0) { $0 + $1.sizeBytes } + filesToMove.reduce(0) { $0 + $1.sizeBytes }
    }

    // Disk space recovered: every removable duplicate copy (all copies but one per content).
    var potentialSavings: Int {
        matchedGroups.reduce(0) { $0 + $1.sizeBytes * max(0, $1.files.count - 1) }
    }

    var tooltipText: String {
        let keepName = URL(fileURLWithPath: keepFolder).lastPathComponent
        let otherNames = otherFolders.map { URL(fileURLWithPath: $0).lastPathComponent }
        let removableCopies = matchedGroups.reduce(0) { $0 + max(0, $1.files.count - 1) }
        return """
        Folder cluster — \(folders.count) folders, \(Int(matchRatio * 100))% match

        Keep:  \(keepName)
        Merge & clean: \(otherNames.joined(separator: ", "))

        • \(matchedGroups.count) shared content group(s) → \(removableCopies) duplicate copy(ies) removed
        • \(filesToMove.count) unique file(s) moved into \(keepName)

        Matching verified by SHA-256 hash comparison (byte-identical).
        """
    }
}

class FileScanner: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var status: String = "Ready to start"
    @Published var isScanning: Bool = false
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var deletedPaths: Set<String> = []
    
    @Published var totalPotentialSavings: Int64 = 0
    @Published var totalRecovered: Int64 = 0
    @Published var fileProgress: Double = 0.0
    
    @Published var useDeepAnalysis: Bool = false
    @Published var filterMediaOnly: Bool = false
    @Published var skipHiddenFiles: Bool = false
    @Published var detectSymlinks: Bool = false
    @Published var detectFolderDuplicates: Bool = false
    @Published var folderMatchThreshold: Double = 0.75
    @Published var folderDuplicateGroups: [FolderDuplicateGroup] = []
    @Published var scanScope: ScanScope = .combined
    @Published var safeMergeToNewFolder: Bool = false   // copy result to a new folder, keep originals
    @Published var renameKeptFolder: Bool = false       // append the merged tag to the kept folder (destructive merge)
    @Published var lastLogURL: URL? = nil               // most recent merge log (for "Reveal log")
    @Published var logLocationMode: LogLocationMode = (UserDefaults.standard.string(forKey: "mergeLogLocation").flatMap(LogLocationMode.init) ?? .appFolder) {
        didSet { UserDefaults.standard.set(logLocationMode.rawValue, forKey: "mergeLogLocation") }
    }

    @Published var scanPhaseIndex: Int = 0
    @Published var totalScanPhases: Int = 1

    @Published var mergeNamePosition: MergeNamePosition = .suffix
    @Published var mergeNameSeparator: String = " "
    @Published var mergeNameContent: String = "merged"

    @Published var sortCriteria: SortCriteria = .name
    @Published var sortOrder: SortOrderEnum = .ascending
    
    private var totalItems: Int = 0
    private var processedItems: Int = 0
    private var shouldStop: Bool = false
    
    private let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp",
        "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm"
    ]

    init(detectFolderDuplicates: Bool = false) {
        self.detectFolderDuplicates = detectFolderDuplicates
    }

    func startScan(sourceURL: URL) {
        startScan(sourceURLs: [sourceURL])
    }

    func stopScan() {
        shouldStop = true
        status = "Stopping…"
    }

    func startScan(sourceURLs: [URL]) {
        guard !sourceURLs.isEmpty else { return }
        shouldStop = false
        isScanning = true
        progress = 0
        scanPhaseIndex = 0
        let base = 1 + (useDeepAnalysis ? 1 : 0) + (detectFolderDuplicates ? 1 : 0)
        totalScanPhases = scanScope == .perFolder ? base * sourceURLs.count : base
        status = "Counting files..."
        duplicateGroups = []
        folderDuplicateGroups = []
        deletedPaths = []
        totalPotentialSavings = 0
        totalRecovered = 0

        DispatchQueue.global(qos: .userInitiated).async {
            self.totalItems = sourceURLs.reduce(0) { $0 + self.countItems(at: $1) }
            if self.totalItems == 0 {
                DispatchQueue.main.async { self.status = "No files found."; self.isScanning = false }
                return
            }
            self.performScan(roots: sourceURLs)
        }
    }
    
    private func countItems(at url: URL) -> Int {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: nil)
        var count = 0
        while enumerator?.nextObject() != nil {
            if shouldStop { return 0 }
            count += 1
        }
        return count
    }
    
    private func performScan(roots: [URL]) {
        self.processedItems = 0
        var allGroups: [DuplicateGroup] = []
        var allFolderGroups: [FolderDuplicateGroup] = []

        if scanScope == .combined {
            let result = scanRoots(roots)
            allGroups = result.groups
            allFolderGroups = result.folderGroups
        } else {
            // Per-folder: scan each root independently and tag results with their origin
            for root in roots {
                if shouldStop { break }
                let result = scanRoots([root])
                let rootPath = root.path
                allGroups.append(contentsOf: result.groups.map { g in
                    var copy = g; copy.rootFolder = rootPath; return copy
                })
                allFolderGroups.append(contentsOf: result.folderGroups.map { fg in
                    var copy = fg; copy.rootFolder = rootPath; return copy
                })
            }
        }

        guard !shouldStop else {
            DispatchQueue.main.async {
                self.isScanning = false
                self.progress = 0
                self.status = "Scan stopped."
            }
            return
        }

        DispatchQueue.main.async {
            self.duplicateGroups = allGroups
            self.folderDuplicateGroups = allFolderGroups
            self.totalPotentialSavings = allGroups.reduce(0) { $0 + Int64($1.sizeBytes) * Int64($1.files.count - 1) }
            self.applySort()
            let total = allGroups.count + allFolderGroups.count
            self.status = "Completed! \(total) groups found."
            self.isScanning = false
            self.progress = 1.0
        }
    }

    // Enumerates the given roots into a shared tracker and runs the full pipeline
    // (grouping → deep analysis → folder detection → confidence). Returns results
    // without publishing final state, so callers can combine across roots.
    private func scanRoots(_ roots: [URL]) -> (groups: [DuplicateGroup], folderGroups: [FolderDuplicateGroup]) {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .typeIdentifierKey, .isDirectoryKey, .contentModificationDateKey]

        var tracker: [String: [DuplicateFileInfo]] = [:]
        var symlinkTracker: [String: [DuplicateFileInfo]] = [:]  // keyed by target device:inode
        var allFilesPerFolder: [String: [DuplicateFileInfo]] = [:]  // folder path → all files

        for root in roots {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys,
                  options: [], errorHandler: { _, _ in return true }) else { continue }

            while let fileURL = enumerator.nextObject() as? URL {
                if shouldStop { break }
                do {
                    let name = fileURL.lastPathComponent
                    if skipHiddenFiles && name.hasPrefix(".") { continue }

                    // Detect symlinks via destinationOfSymbolicLink — reliable, never follows the link
                    let symlinkDest = try? fileManager.destinationOfSymbolicLink(atPath: fileURL.path)
                    let isSymlink = symlinkDest != nil

                    let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                    let isDir = resourceValues.isDirectory ?? false
                    let ext = fileURL.pathExtension.lowercased()
                    let path = fileURL.deletingLastPathComponent().path

                    if isSymlink && detectSymlinks {
                        // Resolve to the canonical target path — handles relative symlinks and /tmp→/private/tmp
                        let targetURL = fileURL.resolvingSymlinksInPath()
                        let symlinkKey = targetURL.path
                        let targetAttrs = try? fileManager.attributesOfItem(atPath: targetURL.path)
                        let targetSize = targetAttrs?[.size] as? Int ?? 0
                        let info = DuplicateFileInfo(path: path, name: name,
                                                     size: formatSize(targetSize), sizeBytes: targetSize,
                                                     isSymlink: true)
                        if symlinkTracker[symlinkKey] != nil { symlinkTracker[symlinkKey]?.append(info) }
                        else { symlinkTracker[symlinkKey] = [info] }
                    } else if !isDir && !isSymlink {
                        if filterMediaOnly && !mediaExtensions.contains(ext) { continue }
                        let sizeInBytes = resourceValues.fileSize ?? 0
                        let sizeStr = formatSize(sizeInBytes)
                        let modDate = resourceValues.contentModificationDate
                        let key = "\(name)_\(sizeInBytes)"
                        let info = DuplicateFileInfo(path: path, name: name, size: sizeStr, sizeBytes: sizeInBytes, modificationDate: modDate)
                        if tracker[key] != nil { tracker[key]?.append(info) } else { tracker[key] = [info] }
                        allFilesPerFolder[path, default: []].append(info)
                    }

                    processedItems += 1
                    let currentProgress = Double(processedItems) / Double(max(1, totalItems))
                    DispatchQueue.main.async { self.progress = currentProgress; self.status = "Scanning: \(name)" }
                } catch { continue }
            }
            if shouldStop { break }
        }

        var groups = tracker.values
            .filter { $0.count > 1 }
            .map { DuplicateGroup(name: $0[0].name, size: $0[0].size, sizeBytes: $0[0].sizeBytes, files: $0) }

        // Append symlink duplicate groups
        let symlinkGroups = symlinkTracker.filter { $0.value.count > 1 }.map { (targetPath, files) -> DuplicateGroup in
            let targetName = URL(fileURLWithPath: targetPath).lastPathComponent
            return DuplicateGroup(name: targetName, size: files[0].size, sizeBytes: files[0].sizeBytes,
                                  files: files, isSymlinkGroup: true)
        }
        groups.append(contentsOf: symlinkGroups)

        if useDeepAnalysis && !shouldStop && !groups.isEmpty {
            DispatchQueue.main.async {
                self.scanPhaseIndex += 1
                self.progress = 0
                self.status = "Deep Analysis (SHA-256)..."
            }
            groups = performDeepAnalysis(on: groups)
        }

        var folderGroups: [FolderDuplicateGroup] = []
        if !shouldStop {
            folderGroups = detectFolderDuplicatesIfNeeded(allFiles: allFilesPerFolder, groups: &groups)
            computeConfidence(for: &groups, folderGroups: folderGroups)
        }
        return (groups, folderGroups)
    }
    
    private func computeConfidence(for groups: inout [DuplicateGroup], folderGroups: [FolderDuplicateGroup]) {
        let copyPatterns = ["copy", "backup", "bak", " old", "_old", "archive", "temp", "(1)", "(2)", "(3)", "- copy", "_copy"]

        for i in 0..<groups.count {
            let files = groups[i].files
            guard files.count > 1 else { continue }
            let folders = files.map { $0.path }
            var signals: [ConfidenceSignal] = []

            // Signal 1 — Folder match ratio (weight 40%)
            var folderMatchScore = 0.0
            var folderMatchDetail = "No related folder cluster detected"
            for fg in folderGroups {
                let cf = Set(fg.folders)
                if folders.filter({ cf.contains($0) }).count >= 2 {
                    if fg.matchRatio > folderMatchScore {
                        folderMatchScore = fg.matchRatio
                        let keepName = URL(fileURLWithPath: fg.keepFolder).lastPathComponent
                        folderMatchDetail = "Part of a \(fg.folders.count)-folder cluster around \"\(keepName)\" (\(Int(fg.matchRatio * 100))% match)"
                    }
                }
            }
            signals.append(ConfidenceSignal(name: "Folder similarity", score: folderMatchScore, weight: 0.35, detail: folderMatchDetail))

            // Signal 2 — Folder name patterns (weight 25%)
            var namePatternScore = 0.0
            var namePatternDetail = "No copy/backup naming detected in parent folders"
            for folder in folders {
                let lower = URL(fileURLWithPath: folder).lastPathComponent.lowercased()
                if copyPatterns.contains(where: { lower.contains($0) }) {
                    namePatternScore = 1.0
                    namePatternDetail = "Folder \"\(URL(fileURLWithPath: folder).lastPathComponent)\" suggests a copy or backup"
                    break
                }
            }
            signals.append(ConfidenceSignal(name: "Folder name pattern", score: namePatternScore, weight: 0.25, detail: namePatternDetail))

            // Signal 3 — Timestamp match (weight 20%)
            let dates = files.compactMap { $0.modificationDate }
            var timestampScore = 0.0
            var timestampDetail = "Modification dates unavailable"
            if dates.count == files.count {
                let diff = dates.max()!.timeIntervalSince(dates.min()!)
                switch diff {
                case ..<1:
                    timestampScore = 1.0; timestampDetail = "All copies modified within 1 second (exact copy)"
                case 1..<60:
                    timestampScore = 0.8; timestampDetail = "All copies modified within 1 minute of each other"
                case 60..<3600:
                    timestampScore = 0.5; timestampDetail = "Copies modified within \(Int(diff/60)) minute(s) of each other"
                case 3600..<86400:
                    timestampScore = 0.3; timestampDetail = "Copies modified within \(Int(diff/3600)) hour(s) of each other"
                default:
                    timestampScore = 0.1; timestampDetail = "Copies modified \(Int(diff/86400)) day(s) apart — may be independently maintained"
                }
            }
            signals.append(ConfidenceSignal(name: "Timestamp match", score: timestampScore, weight: 0.20, detail: timestampDetail))

            // Signal 4 — Path proximity (weight 15%)
            let pathComponents = folders.map { URL(fileURLWithPath: $0).pathComponents }
            let minDepth = pathComponents.map { $0.count }.min() ?? 0
            var commonDepth = 0
            for d in 0..<minDepth {
                if pathComponents.allSatisfy({ $0[d] == pathComponents[0][d] }) { commonDepth = d + 1 } else { break }
            }
            let maxDepth = pathComponents.map { $0.count }.max() ?? 1
            let divergence = Double(maxDepth - commonDepth) / Double(max(1, maxDepth))
            let pathScore = max(0.0, 1.0 - divergence)
            let pathDetail: String
            switch divergence {
            case ..<0.2: pathDetail = "Files differ only at the last path segment — very close"
            case 0.2..<0.5: pathDetail = "Files share most of their path (moderate divergence)"
            default: pathDetail = "Files are in very different filesystem locations"
            }
            signals.append(ConfidenceSignal(name: "Path proximity", score: pathScore, weight: 0.10, detail: pathDetail))

            // Signal 5 — Copy count (weight 10%)
            let copyCount = files.count
            let copyScore: Double
            let copyDetail: String
            switch copyCount {
            case 2:
                copyScore = 0.4; copyDetail = "2 copies — inconclusive on its own"
            case 3...5:
                copyScore = 0.65; copyDetail = "\(copyCount) copies — moderately suggests accidental duplication"
            default:
                copyScore = 0.85; copyDetail = "\(copyCount) copies — strongly suggests mass duplication"
            }
            signals.append(ConfidenceSignal(name: "Copy count", score: copyScore, weight: 0.10, detail: copyDetail))

            let overall = signals.reduce(0.0) { $0 + $1.score * $1.weight }
            groups[i].confidence = DuplicateConfidence(overall: overall, signals: signals)
        }
    }

    private func detectFolderDuplicatesIfNeeded(allFiles: [String: [DuplicateFileInfo]], groups: inout [DuplicateGroup]) -> [FolderDuplicateGroup] {
        guard detectFolderDuplicates else { return [] }

        // Collect every scanned file and hash them all — no name+size pre-filter
        let allFilesList = allFiles.values.flatMap { $0 }
        let totalToHash = allFilesList.count
        guard totalToHash > 0 else { return [] }

        DispatchQueue.main.async {
            self.scanPhaseIndex += 1
            self.progress = 0
            self.status = "Folder analysis: hashing files..."
        }

        // Build hash → [DuplicateFileInfo] map by SHA-256 hashing every file
        var hashGroups: [String: [DuplicateFileInfo]] = [:]
        for (index, file) in allFilesList.enumerated() {
            if shouldStop { return [] }
            DispatchQueue.main.async {
                self.progress = Double(index) / Double(totalToHash)
                self.status = "Folder SHA-256: \(file.name)"
            }
            guard let hash = calculateSHA256(for: file.fullPath) else { continue }
            hashGroups[hash, default: []].append(file)
        }

        DispatchQueue.main.async { self.progress = 1.0 }

        // Count total files per folder
        var folderFileCounts: [String: Int] = [:]
        for (folder, files) in allFiles { folderFileCounts[folder] = files.count }

        // Build pairwise shared-hash sets to decide which folders are connected
        var folderPairHashes: [String: Set<String>] = [:]
        var folderPairFolders: [String: (String, String)] = [:]
        var hashToFiles: [String: [DuplicateFileInfo]] = [:]

        for (hash, files) in hashGroups {
            guard files.count > 1 else { continue }
            hashToFiles[hash] = files
            let folderSet = Set(files.map { $0.path })
            guard folderSet.count > 1 else { continue }
            let folderArray = Array(folderSet).sorted()
            for i in 0..<folderArray.count {
                for j in (i+1)..<folderArray.count {
                    let a = folderArray[i], b = folderArray[j]
                    let key = "\(a)|\(b)"
                    folderPairHashes[key, default: []].insert(hash)
                    folderPairFolders[key] = (a, b)
                }
            }
        }

        // Union-find over folders connected by a pair whose match ratio >= threshold.
        // This collapses clusters of 3+ duplicate folders into a single group.
        var parent: [String: String] = [:]
        for folder in folderFileCounts.keys { parent[folder] = folder }
        func find(_ x: String) -> String {
            var root = x
            while let p = parent[root], p != root { root = p }
            var cur = x
            while let p = parent[cur], p != root { parent[cur] = root; cur = p }
            return root
        }
        func union(_ a: String, _ b: String) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        var pairRatio: [String: Double] = [:]
        for (key, hashes) in folderPairHashes {
            guard let (a, b) = folderPairFolders[key] else { continue }
            let minCount = min(folderFileCounts[a] ?? 0, folderFileCounts[b] ?? 0)
            guard minCount > 0 else { continue }
            let ratio = Double(hashes.count) / Double(minCount)
            pairRatio[key] = ratio
            if ratio >= folderMatchThreshold { union(a, b) }
        }

        // Collect folders by cluster root
        var clusters: [String: [String]] = [:]
        for folder in folderFileCounts.keys {
            clusters[find(folder), default: []].append(folder)
        }

        var detectedFolderGroups: [FolderDuplicateGroup] = []

        for (_, clusterFolders) in clusters {
            guard clusterFolders.count >= 2 else { continue }
            let clusterSet = Set(clusterFolders)

            // keep = most files (tie: larger total size)
            let keep = clusterFolders.max(by: { lhs, rhs in
                let lc = folderFileCounts[lhs] ?? 0, rc = folderFileCounts[rhs] ?? 0
                if lc != rc { return lc < rc }
                let ls = (allFiles[lhs] ?? []).reduce(0) { $0 + $1.sizeBytes }
                let rs = (allFiles[rhs] ?? []).reduce(0) { $0 + $1.sizeBytes }
                return ls < rs
            })!
            let ordered = [keep] + clusterFolders.filter { $0 != keep }.sorted()

            // Group every file in the cluster by content hash
            var contentToFiles: [String: [DuplicateFileInfo]] = [:]
            for (hash, files) in hashGroups {
                let inCluster = files.filter { clusterSet.contains($0.path) }
                if !inCluster.isEmpty { contentToFiles[hash] = inCluster }
            }

            var matchedGroups: [DuplicateGroup] = []
            var uniqueToKeep: [DuplicateFileInfo] = []
            var filesToMove: [DuplicateFileInfo] = []

            for (hash, rawFiles) in contentToFiles {
                // annotate each file with its content hash for logging
                let files = rawFiles.map { f -> DuplicateFileInfo in var c = f; c.sha256 = hash; return c }
                let f0 = files[0]
                if files.count >= 2 {
                    matchedGroups.append(DuplicateGroup(name: f0.name, size: f0.size, sizeBytes: f0.sizeBytes, files: files))
                }
                let inKeep = files.contains { $0.path == keep }
                if inKeep {
                    if files.count == 1 { uniqueToKeep.append(f0) }
                } else {
                    // keep lacks this content → move one representative in
                    filesToMove.append(files.first { $0.path != keep } ?? f0)
                }
            }

            // cluster match ratio = strongest pairwise similarity within the cluster
            var ratio = folderMatchThreshold
            for (key, r) in pairRatio {
                if let (a, b) = folderPairFolders[key], clusterSet.contains(a), clusterSet.contains(b) {
                    ratio = max(ratio, r)
                }
            }

            detectedFolderGroups.append(FolderDuplicateGroup(
                folders: ordered,
                matchedGroups: matchedGroups,
                uniqueToKeep: uniqueToKeep,
                filesToMove: filesToMove,
                matchRatio: min(1.0, ratio)
            ))
        }

        // Remove name+size duplicate groups whose files are covered by a detected cluster
        groups = groups.filter { group in
            let fileFolders = Set(group.files.map { $0.path })
            return !detectedFolderGroups.contains { fg in
                let cf = Set(fg.folders)
                return fileFolders.filter { cf.contains($0) }.count >= 2
            }
        }
        return detectedFolderGroups.sorted { $0.matchRatio > $1.matchRatio }
    }

    func toggleSort(criteria: SortCriteria) {
        if sortCriteria == criteria { sortOrder = (sortOrder == .ascending) ? .descending : .ascending }
        else { sortCriteria = criteria; sortOrder = .descending }
        applySort()
    }
    
    func applySort() {
        duplicateGroups.sort { (a, b) -> Bool in
            if detectSymlinks {
                if a.isSymlinkGroup != b.isSymlinkGroup { return a.isSymlinkGroup }
            }
            let result: Bool
            switch sortCriteria {
            case .name: result = a.name < b.name
            case .size: result = a.sizeBytes < b.sizeBytes
            case .count:
                let countA = a.files.filter { !deletedPaths.contains($0.fullPath) }.count
                let countB = b.files.filter { !deletedPaths.contains($0.fullPath) }.count
                result = countA < countB
            case .matchRatio:
                result = (a.confidence?.overall ?? 0) < (b.confidence?.overall ?? 0)
            }
            return (sortOrder == .ascending) ? result : !result
        }

        folderDuplicateGroups.sort { (a, b) -> Bool in
            let result: Bool
            switch sortCriteria {
            case .name: result = URL(fileURLWithPath: a.folderA).lastPathComponent < URL(fileURLWithPath: b.folderA).lastPathComponent
            case .size: result = a.totalSizeBytes < b.totalSizeBytes
            case .count: result = a.matchedGroups.count < b.matchedGroups.count
            case .matchRatio: result = a.matchRatio < b.matchRatio
            }
            return (sortOrder == .ascending) ? result : !result
        }
    }

    private func performDeepAnalysis(on candidateGroups: [DuplicateGroup]) -> [DuplicateGroup] {
        var finalGroups: [DuplicateGroup] = []
        for (index, group) in candidateGroups.enumerated() {
            if shouldStop { break }
            DispatchQueue.main.async {
                self.status = "Hashing group \(index + 1) of \(candidateGroups.count)..."
                self.progress = Double(index) / Double(candidateGroups.count)
            }
            var hashTracker: [String: [DuplicateFileInfo]] = [:]
            for file in group.files {
                if let hash = calculateSHA256(for: file.fullPath) {
                    if hashTracker[hash] != nil { hashTracker[hash]?.append(file) } else { hashTracker[hash] = [file] }
                } else {
                    // Fallback: If hashing fails (e.g. cloud file offline), 
                    // we treat it as its own unique entry for safety
                    hashTracker["failed_\(file.id.uuidString)"] = [file]
                }
            }
            let confirmedGroups = hashTracker.values
                .filter { $0.count > 1 }
                .map { DuplicateGroup(name: $0[0].name, size: $0[0].size, sizeBytes: $0[0].sizeBytes, files: $0) }
            finalGroups.append(contentsOf: confirmedGroups)
        }
        return finalGroups
    }
    
    private func calculateSHA256(for path: String) -> String? {
        let fileURL = URL(fileURLWithPath: path)
        do {
            // Check if file is reachable
            guard (try? fileURL.checkResourceIsReachable()) == true else { return nil }
            
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            
            let totalSize = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            var bytesRead: Int64 = 0
            
            var hasher = SHA256()
            // USE MODERN Swift API (throws proper errors instead of NSException crash)
            while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
                hasher.update(data: data)
                bytesRead += Int64(data.count)
                if totalSize > 0 {
                    let p = Double(bytesRead) / Double(totalSize)
                    DispatchQueue.main.async { self.fileProgress = p }
                }
            }
            
            DispatchQueue.main.async { self.fileProgress = 0 }
            return hasher.finalize().map { String(format: "%02hhx", $0) }.joined()
        } catch {
            return nil
        }
    }
    
    private func isContentIdentical(url1: URL, url2: URL) -> Bool {
        do {
            let handle1 = try FileHandle(forReadingFrom: url1)
            let handle2 = try FileHandle(forReadingFrom: url2)
            defer { try? handle1.close(); try? handle2.close() }
            
            // Final size sanity check
            let attr1 = try FileManager.default.attributesOfItem(atPath: url1.path)
            let attr2 = try FileManager.default.attributesOfItem(atPath: url2.path)
            let s1 = attr1[.size] as? Int
            let s2 = attr2[.size] as? Int
            
            guard let size1 = s1, let size2 = s2, size1 == size2 else { 
                return false 
            }
            
            var bytesRead: Int64 = 0
            let totalSize = Int64(size1)
            
            while true {
                let data1 = try handle1.read(upToCount: 64 * 1024)
                let data2 = try handle2.read(upToCount: 64 * 1024)
                
                if data1 != data2 { 
                    DispatchQueue.main.async { self.fileProgress = 0 }
                    return false 
                }
                
                if data1 == nil || data1!.isEmpty { break }
                
                bytesRead += Int64(data1!.count)
                if totalSize > 0 {
                    let p = Double(bytesRead) / Double(totalSize)
                    DispatchQueue.main.async { self.fileProgress = p }
                }
            }
            DispatchQueue.main.async { self.fileProgress = 0 }
            return true
        } catch {
            return false
        }
    }

    private func pushTrashUndo(title: String, originals: [URL], newURLs: [URL: URL]?) {
        let pairs: [(trashURL: URL, original: URL)] = originals.compactMap { o in
            guard let t = newURLs?[o] else { return nil }
            return (trashURL: t, original: o)
        }
        OperationHistory.shared.push(UndoableOp(title: title, trashed: pairs))
    }

    // Logs duplicate-file deletions (Files mode) for recovery, reusing the merge log format.
    private func writeFileCleanupLog(_ batch: [(kept: DuplicateFileInfo?, removed: [DuplicateFileInfo])]) {
        let clusters: [MergeLogCluster] = batch.compactMap { item in
            guard !item.removed.isEmpty else { return nil }
            var entries: [MergeLogEntry] = []
            if let k = item.kept {
                entries.append(MergeLogEntry(
                    action: "KEPT", fileName: k.name, sourcePath: k.fullPath, sourceFolder: k.path,
                    destinationPath: k.fullPath, destinationFolder: k.path, sizeBytes: k.sizeBytes,
                    sha256: "", note: "kept original"))
            }
            for r in item.removed {
                entries.append(MergeLogEntry(
                    action: "TRASHED", fileName: r.name, sourcePath: r.fullPath, sourceFolder: r.path,
                    destinationPath: "Trash", destinationFolder: "Trash", sizeBytes: r.sizeBytes,
                    sha256: "", note: "duplicate of kept · recoverable from Trash"))
            }
            let keepPath = item.kept?.fullPath ?? ""
            return MergeLogCluster(keepFolder: keepPath, otherFolders: [],
                                   resultName: item.kept?.name ?? "—", resultPath: keepPath, entries: entries)
        }
        guard !clusters.isEmpty, let dir = defaultLogDirectory() else { return }
        let report = MergeLogReport(timestamp: Date(), appVersion: MergeLogWriter.appVersion,
                                    mode: "Duplicate file cleanup", renameKeptFolder: false, clusters: clusters)
        let url = MergeLogWriter.write(report, to: dir)
        DispatchQueue.main.async { self.lastLogURL = url }
    }

    func recycleFile(atPath fullPath: String) {
        let fileURL = URL(fileURLWithPath: fullPath)

        guard let group = self.duplicateGroups.first(where: { g in g.files.contains(where: { $0.fullPath == fullPath }) }) else { return }
        guard let fileInfo = group.files.first(where: { $0.fullPath == fullPath }) else { return }
        guard group.files.filter({ !deletedPaths.contains($0.fullPath) }).count > 1 else {
            self.status = "Security Error: No active original file found!"
            return
        }

        let keptRef = group.files.first { $0.fullPath != fullPath && !deletedPaths.contains($0.fullPath) }

        // Symlinks: identical by definition (same target) — skip binary check
        if fileInfo.isSymlink || group.isSymlinkGroup {
            NSWorkspace.shared.recycle([fileURL]) { (newURLs, error) in
                DispatchQueue.main.async {
                    if let error = error { self.status = "Error: \(error.localizedDescription)" }
                    else {
                        self.deletedPaths.insert(fullPath)
                        self.totalRecovered += Int64(group.sizeBytes)
                        self.status = "Symlink moved to Trash."
                        self.writeFileCleanupLog([(keptRef, [fileInfo])])
                        self.pushTrashUndo(title: "Delete \(fileInfo.name)", originals: [fileURL], newURLs: newURLs)
                    }
                }
            }
            return
        }

        // Regular files: verify binary identity before recycling
        guard let referenceFile = group.files.first(where: { $0.fullPath != fullPath && !deletedPaths.contains($0.fullPath) }) else {
            self.status = "Security Error: No active original file found!"
            return
        }

        let referenceURL = URL(fileURLWithPath: referenceFile.fullPath)
        self.status = "Verifying binary identity..."

        DispatchQueue.global(qos: .userInitiated).async {
            let identical = self.isContentIdentical(url1: fileURL, url2: referenceURL)

            DispatchQueue.main.async {
                if !identical {
                    self.status = "Security Alert: Files differ! Deletion aborted."
                    return
                }

                NSWorkspace.shared.recycle([fileURL]) { (newURLs, error) in
                    DispatchQueue.main.async {
                        if let error = error { self.status = "Error: \(error.localizedDescription)" }
                        else {
                            self.deletedPaths.insert(fullPath)
                            self.totalRecovered += Int64(group.sizeBytes)
                            self.status = "Security Verified! Moved to Trash."
                            self.writeFileCleanupLog([(referenceFile, [fileInfo])])
                            self.pushTrashUndo(title: "Delete \(fileInfo.name)", originals: [fileURL], newURLs: newURLs)
                        }
                    }
                }
            }
        }
    }

    func recycleAllDuplicates() {
        self.status = "Verifying batch integrity..."
        self.isScanning = true // Use scan state to block UI during heavy comparison
        
        DispatchQueue.global(qos: .userInitiated).async {
            var toRecycle: [URL] = []
            var totalSavingsInSession: Int64 = 0
            var skippedCount = 0
            var logBatch: [(kept: DuplicateFileInfo?, removed: [DuplicateFileInfo])] = []

            for group in self.duplicateGroups {
                let activeFiles = group.files.filter { !self.deletedPaths.contains($0.fullPath) }
                var groupRemoved: [DuplicateFileInfo] = []

                if activeFiles.count > 1 {
                    if group.isSymlinkGroup {
                        // Symlinks: identical by target — skip binary check, keep the first
                        for i in 1..<activeFiles.count {
                            toRecycle.append(URL(fileURLWithPath: activeFiles[i].fullPath))
                            groupRemoved.append(activeFiles[i])
                            totalSavingsInSession += Int64(group.sizeBytes)
                        }
                    } else {
                        let referenceURL = URL(fileURLWithPath: activeFiles[0].fullPath)
                        for i in 1..<activeFiles.count {
                            let fileURL = URL(fileURLWithPath: activeFiles[i].fullPath)
                            if self.isContentIdentical(url1: fileURL, url2: referenceURL) {
                                toRecycle.append(fileURL)
                                groupRemoved.append(activeFiles[i])
                                totalSavingsInSession += Int64(group.sizeBytes)
                            } else {
                                skippedCount += 1
                            }
                        }
                    }
                }
                if !groupRemoved.isEmpty { logBatch.append((activeFiles.first, groupRemoved)) }
            }
            
            if toRecycle.isEmpty {
                DispatchQueue.main.async {
                    self.status = skippedCount > 0 ? "Alert: \(skippedCount) files differ and were skipped." : "No duplicates to clean."
                    self.isScanning = false
                }
                return
            }
            
            let count = toRecycle.count
            NSWorkspace.shared.recycle(toRecycle) { (newURLs, error) in
                DispatchQueue.main.async {
                    self.isScanning = false
                    if let error = error {
                        self.status = "Batch Error: \(error.localizedDescription)"
                    } else {
                        // Batch update UI
                        for url in toRecycle { self.deletedPaths.insert(url.path) }
                        self.totalRecovered += totalSavingsInSession
                        let skipMsg = skippedCount > 0 ? " (\(skippedCount) files skipped for safety)" : ""
                        self.status = "Security Verified! \(count) files moved to Trash\(skipMsg)."
                        self.writeFileCleanupLog(logBatch)
                        self.pushTrashUndo(title: "Clean \(count) duplicate file(s)", originals: toRecycle, newURLs: newURLs)
                    }
                }
            }
        }
    }
    
    static func resolveCollisionName(for fileName: String, sourceFolderName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension
        let base = ext.isEmpty ? fileName : String(fileName.dropLast(ext.count + 1))
        let safe = sourceFolderName.replacingOccurrences(of: "/", with: "_")
        return ext.isEmpty
            ? "\(base)_moved_from_\(safe)"
            : "\(base)_moved_from_\(safe).\(ext)"
    }

    func computeMergedFolderName(folderA: String, folderB: String) -> String {
        let nameA = URL(fileURLWithPath: folderA).lastPathComponent
        let nameB = URL(fileURLWithPath: folderB).lastPathComponent

        let boundaryChars = CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "-_()[].,"))
        func isBoundary(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { boundaryChars.contains($0) } }

        // Longest common prefix (case-insensitive comparison, preserve original casing from nameA)
        var commonLength = 0
        for (a, b) in zip(nameA.lowercased(), nameB.lowercased()) {
            if a == b { commonLength += 1 } else { break }
        }
        var common = String(nameA.prefix(commonLength))

        // If the prefix was cut in the middle of a word (e.g. "usbtinyisp v1.5" vs
        // "usbtinyisp vitor" → "usbtinyisp v"), trim back to the last word boundary.
        let charsA = Array(nameA), charsB = Array(nameB)
        let nextA: Character? = commonLength < charsA.count ? charsA[commonLength] : nil
        let nextB: Character? = commonLength < charsB.count ? charsB[commonLength] : nil
        let cutMidWord = (common.last.map { !isBoundary($0) } ?? false)
            && ((nextA.map { !isBoundary($0) } ?? false) || (nextB.map { !isBoundary($0) } ?? false))
        if cutMidWord {
            if let idx = common.lastIndex(where: { isBoundary($0) }) {
                common = String(common[..<idx])
            } else {
                common = ""
            }
        }
        common = common.trimmingCharacters(in: boundaryChars)

        // Fall back to the keep folder's full name when the common prefix is too short
        let base = common.count >= 3 ? common : nameA

        guard !mergeNameContent.isEmpty else { return base }
        return mergeNamePosition == .suffix
            ? "\(base)\(mergeNameSeparator)\(mergeNameContent)"
            : "\(mergeNameContent)\(mergeNameSeparator)\(base)"
    }

    // Destructive cluster merge — call OFF the main thread. Moves every unique file
    // into the keep folder, trashes the other folders (whose remaining files are all
    // duplicates of keep), then renames keep. Returns final name + move-error count.
    // Destructive cluster merge — call OFF the main thread. Returns a full log of
    // every action plus the move-error count.
    private func performClusterMerge(_ group: FolderDuplicateGroup) -> (cluster: MergeLogCluster, errors: Int) {
        let fileManager = FileManager.default
        let keep = group.keepFolder
        var errors = 0
        var entries: [MergeLogEntry] = []
        let moveIDs = Set(group.filesToMove.map { $0.id })

        // 1. move unique files from the other folders into keep (rename on collision)
        for file in group.filesToMove {
            let srcURL = URL(fileURLWithPath: file.fullPath)
            let sourceFolderName = URL(fileURLWithPath: file.path).lastPathComponent
            var destName = file.name
            var renamed = false
            var destURL = URL(fileURLWithPath: keep).appendingPathComponent(destName)
            if fileManager.fileExists(atPath: destURL.path) {
                renamed = true
                destName = FileScanner.resolveCollisionName(for: file.name, sourceFolderName: sourceFolderName)
                destURL = URL(fileURLWithPath: keep).appendingPathComponent(destName)
                var suffix = 2
                while fileManager.fileExists(atPath: destURL.path) {
                    let ext = URL(fileURLWithPath: destName).pathExtension
                    let base = ext.isEmpty ? destName : String(destName.dropLast(ext.count + 1))
                    destName = ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
                    destURL = URL(fileURLWithPath: keep).appendingPathComponent(destName)
                    suffix += 1
                }
            }
            let ok = (try? fileManager.moveItem(at: srcURL, to: destURL)) != nil
            if !ok { errors += 1 }
            entries.append(MergeLogEntry(
                action: ok ? (renamed ? "MOVED+RENAMED" : "MOVED") : "ERROR",
                fileName: file.name, sourcePath: file.fullPath, sourceFolder: file.path,
                destinationPath: ok ? destURL.path : "", destinationFolder: ok ? keep : "",
                sizeBytes: file.sizeBytes, sha256: file.sha256 ?? "",
                note: ok ? (renamed ? "renamed to \(destName) (name collision)" : "") : "move failed"))
        }

        // 2. record the removable duplicate copies (trashed along with their folders)
        for mg in group.matchedGroups {
            for f in mg.files where f.path != keep && !moveIDs.contains(f.id) {
                entries.append(MergeLogEntry(
                    action: "TRASHED", fileName: f.name, sourcePath: f.fullPath, sourceFolder: f.path,
                    destinationPath: "Trash", destinationFolder: "Trash",
                    sizeBytes: f.sizeBytes, sha256: f.sha256 ?? "", note: "duplicate of kept copy"))
            }
        }

        // 3. record keep-only files (unchanged)
        for f in group.uniqueToKeep {
            entries.append(MergeLogEntry(
                action: "UNCHANGED", fileName: f.name, sourcePath: f.fullPath, sourceFolder: f.path,
                destinationPath: f.fullPath, destinationFolder: f.path,
                sizeBytes: f.sizeBytes, sha256: f.sha256 ?? "", note: "only in keep folder"))
        }

        // 4. trash every other folder in the cluster
        let otherURLs = group.otherFolders.map { URL(fileURLWithPath: $0) }
        if !otherURLs.isEmpty { NSWorkspace.shared.recycle(otherURLs, completionHandler: nil) }
        for other in group.otherFolders {
            entries.append(MergeLogEntry(
                action: "FOLDER_TRASHED", fileName: URL(fileURLWithPath: other).lastPathComponent,
                sourcePath: other, sourceFolder: URL(fileURLWithPath: other).deletingLastPathComponent().path,
                destinationPath: "Trash", destinationFolder: "Trash", sizeBytes: 0, sha256: "",
                note: "folder removed after its unique files were moved into keep"))
        }

        // 5. optionally rename keep to the computed merged name (else leave it untouched)
        var resultPath = keep
        if renameKeptFolder {
            let parentDir = URL(fileURLWithPath: keep).deletingLastPathComponent()
            let computedName = self.computeMergedFolderName(folderA: group.folderA, folderB: group.folderB)
            var destURL = parentDir.appendingPathComponent(computedName)
            var suffix = 2
            while fileManager.fileExists(atPath: destURL.path) {
                destURL = parentDir.appendingPathComponent("\(computedName)_\(suffix)")
                suffix += 1
            }
            if (try? fileManager.moveItem(at: URL(fileURLWithPath: keep), to: destURL)) != nil {
                resultPath = destURL.path
            }
        }

        let cluster = MergeLogCluster(
            keepFolder: keep, otherFolders: group.otherFolders,
            resultName: URL(fileURLWithPath: resultPath).lastPathComponent, resultPath: resultPath,
            entries: entries)
        return (cluster, errors)
    }

    func mergeFolder(_ folderGroup: FolderDuplicateGroup, logDirectory: URL? = nil) {
        self.isScanning = true
        self.status = "Merging folder cluster…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.performClusterMerge(folderGroup)
            let report = MergeLogReport(timestamp: Date(), appVersion: MergeLogWriter.appVersion,
                                        mode: "In-place merge & clean", renameKeptFolder: self.renameKeptFolder,
                                        clusters: [result.cluster])
            let logURL = self.writeReport(report, preferred: logDirectory)
            DispatchQueue.main.async {
                self.folderDuplicateGroups.removeAll { $0.id == folderGroup.id }
                for file in folderGroup.matchedGroups.flatMap({ $0.files }) where file.path != folderGroup.keepFolder {
                    self.deletedPaths.insert(file.fullPath)
                }
                self.totalRecovered += Int64(folderGroup.totalSizeBytes)
                self.isScanning = false
                self.lastLogURL = logURL
                self.status = result.errors == 0
                    ? "Merge complete → \"\(result.cluster.resultName)\"\(logURL != nil ? " · log saved" : "")"
                    : "Merge done with \(result.errors) error(s)."
            }
        }
    }

    func mergeAllFolders() {
        mergeFolders(folderDuplicateGroups)
    }

    func mergeFolders(_ groups: [FolderDuplicateGroup], logDirectory: URL? = nil) {
        guard !groups.isEmpty else { return }
        self.isScanning = true
        self.status = "Merging \(groups.count) folder cluster(s)..."

        DispatchQueue.global(qos: .userInitiated).async {
            var clusters: [MergeLogCluster] = []
            var errorCount = 0

            for (index, folderGroup) in groups.enumerated() {
                DispatchQueue.main.async {
                    self.status = "Merging cluster \(index + 1)/\(groups.count)..."
                    self.progress = Double(index) / Double(groups.count)
                }

                let result = self.performClusterMerge(folderGroup)
                errorCount += result.errors
                clusters.append(result.cluster)

                DispatchQueue.main.async {
                    self.folderDuplicateGroups.removeAll { $0.id == folderGroup.id }
                    for file in folderGroup.matchedGroups.flatMap({ $0.files }) where file.path != folderGroup.keepFolder {
                        self.deletedPaths.insert(file.fullPath)
                    }
                    self.totalRecovered += Int64(folderGroup.totalSizeBytes)
                }
            }

            let report = MergeLogReport(timestamp: Date(), appVersion: MergeLogWriter.appVersion,
                                        mode: "In-place merge & clean", renameKeptFolder: self.renameKeptFolder,
                                        clusters: clusters)
            let logURL = self.writeReport(report, preferred: logDirectory)

            DispatchQueue.main.async {
                self.isScanning = false
                self.progress = 1.0
                self.lastLogURL = logURL
                let errMsg = errorCount > 0 ? " (\(errorCount) errors)" : ""
                self.status = "Merged \(clusters.count) folder cluster(s)\(errMsg)\(logURL != nil ? " · log saved" : "")."
            }
        }
    }

    // MARK: - Safe merge (copy to new folder, originals untouched)

    // Single cluster → copies the merged result into `dest` (a new folder).
    func safeMergeFolder(_ group: FolderDuplicateGroup, to dest: URL, logDirectory: URL? = nil) {
        self.isScanning = true
        self.status = "Creating merged copy…"
        DispatchQueue.global(qos: .userInitiated).async {
            let cluster = self.copyMergedFolder(group, to: dest)
            let report = MergeLogReport(timestamp: Date(), appVersion: MergeLogWriter.appVersion,
                                        mode: "Copy to new folder (originals kept)", renameKeptFolder: false,
                                        clusters: [cluster])
            let logURL = self.writeReport(report, preferred: logDirectory)
            let failed = cluster.entries.contains { $0.action == "ERROR" }
            DispatchQueue.main.async {
                self.isScanning = false
                self.lastLogURL = logURL
                self.status = failed
                    ? "Safe merge failed for \"\(dest.lastPathComponent)\"."
                    : "Merged copy created → \"\(dest.lastPathComponent)\". Originals untouched\(logURL != nil ? " · log saved" : "")."
                if !failed {
                    OperationHistory.shared.push(UndoableOp(title: "Copy merge → \(dest.lastPathComponent)", created: [dest]))
                }
            }
        }
    }

    // Multiple clusters → one merged subfolder per cluster inside `parent`.
    func safeMergeFolders(_ groups: [FolderDuplicateGroup], intoParent parent: URL, logDirectory: URL? = nil) {
        guard !groups.isEmpty else { return }
        self.isScanning = true
        self.status = "Creating \(groups.count) merged copies…"
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            var clusters: [MergeLogCluster] = []
            var errorCount = 0
            var createdDests: [URL] = []
            for group in groups {
                let name = self.computeMergedFolderName(folderA: group.folderA, folderB: group.folderB)
                var dest = parent.appendingPathComponent(name)
                var suffix = 2
                while fileManager.fileExists(atPath: dest.path) {
                    dest = parent.appendingPathComponent("\(name)_\(suffix)")
                    suffix += 1
                }
                let cluster = self.copyMergedFolder(group, to: dest)
                if cluster.entries.contains(where: { $0.action == "ERROR" }) { errorCount += 1 }
                else { createdDests.append(dest) }
                clusters.append(cluster)
            }
            let report = MergeLogReport(timestamp: Date(), appVersion: MergeLogWriter.appVersion,
                                        mode: "Copy to new folder (originals kept)", renameKeptFolder: false,
                                        clusters: clusters)
            let logURL = self.writeReport(report, preferred: logDirectory)
            DispatchQueue.main.async {
                self.isScanning = false
                self.lastLogURL = logURL
                let errMsg = errorCount > 0 ? " (\(errorCount) failed)" : ""
                self.status = "Created \(clusters.count - errorCount) merged copy(ies) in \"\(parent.lastPathComponent)\"\(errMsg). Originals untouched\(logURL != nil ? " · log saved" : "")."
                if !createdDests.isEmpty {
                    OperationHistory.shared.push(UndoableOp(title: "Copy \(createdDests.count) merged folder(s)", created: createdDests))
                }
            }
        }
    }

    // Copies the keep folder's full tree to `dest`, then adds the other folders'
    // unique files (renaming on collision). Never modifies the originals. Returns a log.
    private func copyMergedFolder(_ group: FolderDuplicateGroup, to dest: URL) -> MergeLogCluster {
        let fileManager = FileManager.default
        let keep = group.keepFolder
        let moveIDs = Set(group.filesToMove.map { $0.id })
        var entries: [MergeLogEntry] = []

        var copiedBase = true
        do {
            if fileManager.fileExists(atPath: dest.path) { try fileManager.removeItem(at: dest) }
            try fileManager.copyItem(at: URL(fileURLWithPath: keep), to: dest)
        } catch {
            copiedBase = false
        }
        entries.append(MergeLogEntry(
            action: copiedBase ? "FOLDER_COPIED" : "ERROR",
            fileName: URL(fileURLWithPath: keep).lastPathComponent, sourcePath: keep,
            sourceFolder: URL(fileURLWithPath: keep).deletingLastPathComponent().path,
            destinationPath: dest.path, destinationFolder: dest.deletingLastPathComponent().path,
            sizeBytes: 0, sha256: "",
            note: copiedBase ? "keep folder copied as the merge base" : "copy failed"))

        guard copiedBase else {
            return MergeLogCluster(keepFolder: keep, otherFolders: group.otherFolders,
                                   resultName: dest.lastPathComponent, resultPath: dest.path, entries: entries)
        }

        for file in group.filesToMove {
            let srcURL = URL(fileURLWithPath: file.fullPath)
            let sourceFolderName = URL(fileURLWithPath: file.path).lastPathComponent
            var destName = file.name
            var renamed = false
            var destURL = dest.appendingPathComponent(destName)
            if fileManager.fileExists(atPath: destURL.path) {
                renamed = true
                destName = FileScanner.resolveCollisionName(for: file.name, sourceFolderName: sourceFolderName)
                destURL = dest.appendingPathComponent(destName)
                var suffix = 2
                while fileManager.fileExists(atPath: destURL.path) {
                    let ext = URL(fileURLWithPath: destName).pathExtension
                    let base = ext.isEmpty ? destName : String(destName.dropLast(ext.count + 1))
                    destName = ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
                    destURL = dest.appendingPathComponent(destName)
                    suffix += 1
                }
            }
            let ok = (try? fileManager.copyItem(at: srcURL, to: destURL)) != nil
            entries.append(MergeLogEntry(
                action: ok ? (renamed ? "COPIED+RENAMED" : "COPIED") : "ERROR",
                fileName: file.name, sourcePath: file.fullPath, sourceFolder: file.path,
                destinationPath: ok ? destURL.path : "", destinationFolder: ok ? dest.path : "",
                sizeBytes: file.sizeBytes, sha256: file.sha256 ?? "",
                note: ok ? (renamed ? "renamed to \(destName) (name collision)" : "") : "copy failed"))
        }

        // record duplicates that were intentionally not copied
        for mg in group.matchedGroups {
            for f in mg.files where f.path != keep && !moveIDs.contains(f.id) {
                entries.append(MergeLogEntry(
                    action: "SKIPPED", fileName: f.name, sourcePath: f.fullPath, sourceFolder: f.path,
                    destinationPath: "", destinationFolder: "",
                    sizeBytes: f.sizeBytes, sha256: f.sha256 ?? "", note: "duplicate — not copied"))
            }
        }

        return MergeLogCluster(keepFolder: keep, otherFolders: group.otherFolders,
                               resultName: dest.lastPathComponent, resultPath: dest.path, entries: entries)
    }

    // MARK: - Log writing

    private func defaultLogDirectory() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent("FileLister Logs", isDirectory: true)
    }

    private func writeReport(_ report: MergeLogReport, preferred: URL?) -> URL? {
        guard let dir = preferred ?? defaultLogDirectory() else { return nil }
        return MergeLogWriter.write(report, to: dir)
    }

    func formatBytes(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024.0
        let mb = kb / 1024.0
        let gb = mb / 1024.0
        let tb = gb / 1024.0
        
        if tb >= 1 { return String(format: "%.2f TB", tb) }
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        if mb >= 1 { return String(format: "%.2f MB", mb) }
        return String(format: "%.2f KB", kb)
    }

    private func formatSize(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024.0
        return kb < 1024 ? String(format: "%.2f KB", kb) : String(format: "%.2f MB", kb / 1024.0)
    }
}
