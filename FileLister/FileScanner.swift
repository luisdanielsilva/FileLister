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

struct DuplicateFileInfo: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let name: String
    let size: String
    let sizeBytes: Int
    var isSymlink: Bool = false
    var modificationDate: Date? = nil

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
}

struct FolderDuplicateGroup: Identifiable {
    let id = UUID()
    let folderA: String                     // folder to keep
    let folderB: String                     // folder to merge into A then trash
    let matchedGroups: [DuplicateGroup]     // file groups shared between A and B
    let uniqueToA: [DuplicateFileInfo]      // files only in A
    let uniqueToB: [DuplicateFileInfo]      // files only in B — moved to A on merge
    let matchRatio: Double                  // 0.5–1.0
    var totalSizeBytes: Int {
        matchedGroups.reduce(0) { $0 + $1.sizeBytes } + uniqueToB.reduce(0) { $0 + $1.sizeBytes }
    }

    // Files deleted from B — the actual disk space recovered
    var potentialSavings: Int {
        matchedGroups.reduce(0) { $0 + $1.sizeBytes }
    }

    var tooltipText: String {
        let filesInA = matchedGroups.count + uniqueToA.count
        let filesInB = matchedGroups.count + uniqueToB.count
        let minCount = min(filesInA, filesInB)
        let nameA = URL(fileURLWithPath: folderA).lastPathComponent
        let nameB = URL(fileURLWithPath: folderB).lastPathComponent
        return """
        Folder Match Ratio: \(Int(matchRatio * 100))%

        Formula: SHA-256 verified matches ÷ files in smaller folder
          \(matchedGroups.count) matching files ÷ \(minCount) = \(Int(matchRatio * 100))%

        • \(nameA): \(filesInA) file(s) total
          — \(matchedGroups.count) shared, \(uniqueToA.count) unique
        • \(nameB): \(filesInB) file(s) total
          — \(matchedGroups.count) shared, \(uniqueToB.count) unique

        Matching verified by SHA-256 hash comparison (byte-identical).
        Unique files will be moved to \(nameA) on merge.
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

    func startScan(sourceURL: URL) {
        shouldStop = false
        isScanning = true
        progress = 0
        scanPhaseIndex = 0
        totalScanPhases = 1 + (useDeepAnalysis ? 1 : 0) + (detectFolderDuplicates ? 1 : 0)
        status = "Counting files..."
        duplicateGroups = []
        folderDuplicateGroups = []
        deletedPaths = []
        totalPotentialSavings = 0
        totalRecovered = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.totalItems = self.countItems(at: sourceURL)
            if self.totalItems == 0 {
                DispatchQueue.main.async { self.status = "No files found."; self.isScanning = false }
                return
            }
            self.performScan(sourceURL: sourceURL)
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
    
    private func performScan(sourceURL: URL) {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .typeIdentifierKey, .isDirectoryKey, .contentModificationDateKey]

        guard let enumerator = fileManager.enumerator(at: sourceURL, includingPropertiesForKeys: keys,
              options: [], errorHandler: { _, _ in return true }) else {
            DispatchQueue.main.async { self.isScanning = false }
            return
        }

        self.processedItems = 0
        var tracker: [String: [DuplicateFileInfo]] = [:]
        var symlinkTracker: [String: [DuplicateFileInfo]] = [:]  // keyed by target device:inode
        var allFilesPerFolder: [String: [DuplicateFileInfo]] = [:]  // folder path → all files

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
        
        if !shouldStop {
            self.detectFolderDuplicatesIfNeeded(allFiles: allFilesPerFolder, groups: &groups)
            self.computeConfidence(for: &groups, folderGroups: self.folderDuplicateGroups)
            DispatchQueue.main.async {
                self.duplicateGroups = groups
                self.totalPotentialSavings = groups.reduce(0) { $0 + Int64($1.sizeBytes) * Int64($1.files.count - 1) }
                self.applySort()
                let total = groups.count + self.folderDuplicateGroups.count
                self.status = "Completed! \(total) groups found."
                self.isScanning = false
                self.progress = 1.0
            }
        }
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
            var folderMatchDetail = "No related folder pair detected"
            for fg in folderGroups {
                if folders.contains(fg.folderA) && folders.contains(fg.folderB) {
                    if fg.matchRatio > folderMatchScore {
                        folderMatchScore = fg.matchRatio
                        let nA = URL(fileURLWithPath: fg.folderA).lastPathComponent
                        let nB = URL(fileURLWithPath: fg.folderB).lastPathComponent
                        folderMatchDetail = "\"\(nA)\" and \"\(nB)\" share \(Int(fg.matchRatio * 100))% of files"
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

    private func detectFolderDuplicatesIfNeeded(allFiles: [String: [DuplicateFileInfo]], groups: inout [DuplicateGroup]) {
        guard detectFolderDuplicates else { return }

        // Collect every scanned file and hash them all — no name+size pre-filter
        let allFilesList = allFiles.values.flatMap { $0 }
        let totalToHash = allFilesList.count
        guard totalToHash > 0 else { return }

        DispatchQueue.main.async {
            self.scanPhaseIndex += 1
            self.progress = 0
            self.status = "Folder analysis: hashing files..."
        }

        // Build hash → [DuplicateFileInfo] map by SHA-256 hashing every file
        var hashGroups: [String: [DuplicateFileInfo]] = [:]
        for (index, file) in allFilesList.enumerated() {
            if shouldStop { return }
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

        // Build folder pair → shared hash set from hash groups with 2+ files across different folders
        var folderPairHashes: [String: Set<String>] = [:]
        var folderPairFolders: [String: (String, String)] = [:]
        var hashToFiles: [String: [DuplicateFileInfo]] = [:]

        for (hash, files) in hashGroups {
            guard files.count > 1 else { continue }
            let folders = Set(files.map { $0.path })
            guard folders.count > 1 else { continue }
            hashToFiles[hash] = files
            let folderArray = Array(folders).sorted()
            for i in 0..<folderArray.count {
                for j in (i+1)..<folderArray.count {
                    let a = folderArray[i], b = folderArray[j]
                    let key = "\(a)|\(b)"
                    folderPairHashes[key, default: []].insert(hash)
                    folderPairFolders[key] = (a, b)
                }
            }
        }

        var detectedFolderGroups: [FolderDuplicateGroup] = []

        for (key, hashes) in folderPairHashes {
            guard let (rawA, rawB) = folderPairFolders[key] else { continue }
            let countA = folderFileCounts[rawA] ?? 0
            let countB = folderFileCounts[rawB] ?? 0
            let minCount = min(countA, countB)
            guard minCount > 0 else { continue }

            let ratio = Double(hashes.count) / Double(minCount)
            guard ratio >= folderMatchThreshold else { continue }

            let (folderA, folderB) = countA >= countB ? (rawA, rawB) : (rawB, rawA)

            let verifiedGroups: [DuplicateGroup] = hashes.compactMap { hash in
                guard let files = hashToFiles[hash] else { return nil }
                let f = files[0]
                return DuplicateGroup(name: f.name, size: f.size, sizeBytes: f.sizeBytes, files: files)
            }

            let sharedKeys = Set(verifiedGroups.map { "\($0.name)_\($0.sizeBytes)" })
            let uniqueToA = (allFiles[folderA] ?? []).filter { !sharedKeys.contains("\($0.name)_\($0.sizeBytes)") }
            let uniqueToB = (allFiles[folderB] ?? []).filter { !sharedKeys.contains("\($0.name)_\($0.sizeBytes)") }

            detectedFolderGroups.append(FolderDuplicateGroup(
                folderA: folderA, folderB: folderB,
                matchedGroups: verifiedGroups,
                uniqueToA: uniqueToA, uniqueToB: uniqueToB,
                matchRatio: ratio
            ))
        }

        // Remove name+size duplicate groups whose files are covered by a detected folder pair
        groups = groups.filter { group in
            let fileFolders = Set(group.files.map { $0.path })
            return !detectedFolderGroups.contains { fg in
                fileFolders.contains(fg.folderA) && fileFolders.contains(fg.folderB)
            }
        }
        folderDuplicateGroups = detectedFolderGroups.sorted { $0.matchRatio > $1.matchRatio }
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

    func recycleFile(atPath fullPath: String) {
        let fileURL = URL(fileURLWithPath: fullPath)

        guard let group = self.duplicateGroups.first(where: { g in g.files.contains(where: { $0.fullPath == fullPath }) }) else { return }
        guard let fileInfo = group.files.first(where: { $0.fullPath == fullPath }) else { return }
        guard group.files.filter({ !deletedPaths.contains($0.fullPath) }).count > 1 else {
            self.status = "Security Error: No active original file found!"
            return
        }

        // Symlinks: identical by definition (same target) — skip binary check
        if fileInfo.isSymlink || group.isSymlinkGroup {
            NSWorkspace.shared.recycle([fileURL]) { (_, error) in
                DispatchQueue.main.async {
                    if let error = error { self.status = "Error: \(error.localizedDescription)" }
                    else {
                        self.deletedPaths.insert(fullPath)
                        self.totalRecovered += Int64(group.sizeBytes)
                        self.status = "Symlink moved to Trash."
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

                NSWorkspace.shared.recycle([fileURL]) { (_, error) in
                    DispatchQueue.main.async {
                        if let error = error { self.status = "Error: \(error.localizedDescription)" }
                        else {
                            self.deletedPaths.insert(fullPath)
                            self.totalRecovered += Int64(group.sizeBytes)
                            self.status = "Security Verified! Moved to Trash."
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
            
            for group in self.duplicateGroups {
                let activeFiles = group.files.filter { !self.deletedPaths.contains($0.fullPath) }

                if activeFiles.count > 1 {
                    if group.isSymlinkGroup {
                        // Symlinks: identical by target — skip binary check, keep the first
                        for i in 1..<activeFiles.count {
                            toRecycle.append(URL(fileURLWithPath: activeFiles[i].fullPath))
                            totalSavingsInSession += Int64(group.sizeBytes)
                        }
                    } else {
                        let referenceURL = URL(fileURLWithPath: activeFiles[0].fullPath)
                        for i in 1..<activeFiles.count {
                            let fileURL = URL(fileURLWithPath: activeFiles[i].fullPath)
                            if self.isContentIdentical(url1: fileURL, url2: referenceURL) {
                                toRecycle.append(fileURL)
                                totalSavingsInSession += Int64(group.sizeBytes)
                            } else {
                                skippedCount += 1
                            }
                        }
                    }
                }
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
                    }
                }
            }
        }
    }
    
    func computeMergedFolderName(folderA: String, folderB: String) -> String {
        let nameA = URL(fileURLWithPath: folderA).lastPathComponent
        let nameB = URL(fileURLWithPath: folderB).lastPathComponent

        // Longest common prefix (case-insensitive comparison, preserve original casing from nameA)
        var commonLength = 0
        for (a, b) in zip(nameA.lowercased(), nameB.lowercased()) {
            if a == b { commonLength += 1 } else { break }
        }
        let common = String(nameA.prefix(commonLength))
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "-_()[]")))

        let base = common.count >= 3 ? common : nameA

        guard !mergeNameContent.isEmpty else { return base }
        return mergeNamePosition == .suffix
            ? "\(base)\(mergeNameSeparator)\(mergeNameContent)"
            : "\(mergeNameContent)\(mergeNameSeparator)\(base)"
    }

    func mergeFolder(_ folderGroup: FolderDuplicateGroup) {
        self.isScanning = true
        self.status = "Merging folders..."

        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            var errors: [String] = []

            // Step 1: move unique files from B → A
            for file in folderGroup.uniqueToB {
                let srcURL = URL(fileURLWithPath: file.fullPath)
                var destName = file.name
                var destURL = URL(fileURLWithPath: folderGroup.folderA).appendingPathComponent(destName)

                // Rename on collision
                if fileManager.fileExists(atPath: destURL.path) {
                    let ext = srcURL.pathExtension
                    let base = ext.isEmpty ? destName : String(destName.dropLast(ext.count + 1))
                    destName = ext.isEmpty ? "\(base)_merged" : "\(base)_merged.\(ext)"
                    destURL = URL(fileURLWithPath: folderGroup.folderA).appendingPathComponent(destName)
                }

                do {
                    try fileManager.moveItem(at: srcURL, to: destURL)
                } catch {
                    errors.append(file.name)
                }
            }

            // Step 2: trash matched duplicate files in B
            let filesToTrash = folderGroup.matchedGroups
                .flatMap { $0.files }
                .filter { $0.path == folderGroup.folderB }
                .map { URL(fileURLWithPath: $0.fullPath) }

            if !filesToTrash.isEmpty {
                NSWorkspace.shared.recycle(filesToTrash, completionHandler: nil)
            }

            // Step 3: trash folder B itself
            let folderBURL = URL(fileURLWithPath: folderGroup.folderB)
            NSWorkspace.shared.recycle([folderBURL]) { _, _ in }

            // Step 4: rename folderA to the computed merged name
            let parentDir = URL(fileURLWithPath: folderGroup.folderA).deletingLastPathComponent()
            let computedName = self.computeMergedFolderName(folderA: folderGroup.folderA, folderB: folderGroup.folderB)
            var destURL = parentDir.appendingPathComponent(computedName)
            var suffix = 2
            while fileManager.fileExists(atPath: destURL.path) {
                destURL = parentDir.appendingPathComponent("\(computedName)_\(suffix)")
                suffix += 1
            }
            try? fileManager.moveItem(at: URL(fileURLWithPath: folderGroup.folderA), to: destURL)

            DispatchQueue.main.async {
                self.folderDuplicateGroups.removeAll { $0.id == folderGroup.id }
                for file in folderGroup.matchedGroups.flatMap({ $0.files }) where file.path == folderGroup.folderB {
                    self.deletedPaths.insert(file.fullPath)
                }
                self.totalRecovered += Int64(folderGroup.totalSizeBytes)
                self.isScanning = false
                if errors.isEmpty {
                    self.status = "Merge complete → \"\(destURL.lastPathComponent)\""
                } else {
                    self.status = "Merge done with \(errors.count) error(s): \(errors.prefix(2).joined(separator: ", "))"
                }
            }
        }
    }

    func mergeAllFolders() {
        let groups = folderDuplicateGroups
        guard !groups.isEmpty else { return }
        self.isScanning = true
        self.status = "Merging all folder pairs..."

        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            var mergedCount = 0
            var errorCount = 0

            for (index, folderGroup) in groups.enumerated() {
                DispatchQueue.main.async {
                    self.status = "Merging pair \(index + 1)/\(groups.count)..."
                    self.progress = Double(index) / Double(groups.count)
                }

                // Step 1: move unique files from B → A
                for file in folderGroup.uniqueToB {
                    let srcURL = URL(fileURLWithPath: file.fullPath)
                    var destName = file.name
                    var destURL = URL(fileURLWithPath: folderGroup.folderA).appendingPathComponent(destName)
                    if fileManager.fileExists(atPath: destURL.path) {
                        let ext = srcURL.pathExtension
                        let base = ext.isEmpty ? destName : String(destName.dropLast(ext.count + 1))
                        destName = ext.isEmpty ? "\(base)_merged" : "\(base)_merged.\(ext)"
                        destURL = URL(fileURLWithPath: folderGroup.folderA).appendingPathComponent(destName)
                    }
                    if (try? fileManager.moveItem(at: srcURL, to: destURL)) == nil { errorCount += 1 }
                }

                // Step 2: trash matched files in B
                let filesToTrash = folderGroup.matchedGroups
                    .flatMap { $0.files }
                    .filter { $0.path == folderGroup.folderB }
                    .map { URL(fileURLWithPath: $0.fullPath) }
                if !filesToTrash.isEmpty { NSWorkspace.shared.recycle(filesToTrash, completionHandler: nil) }

                // Step 3: trash folder B
                NSWorkspace.shared.recycle([URL(fileURLWithPath: folderGroup.folderB)], completionHandler: nil)

                // Step 4: rename folder A
                let parentDir = URL(fileURLWithPath: folderGroup.folderA).deletingLastPathComponent()
                let computedName = self.computeMergedFolderName(folderA: folderGroup.folderA, folderB: folderGroup.folderB)
                var destURL = parentDir.appendingPathComponent(computedName)
                var suffix = 2
                while fileManager.fileExists(atPath: destURL.path) {
                    destURL = parentDir.appendingPathComponent("\(computedName)_\(suffix)")
                    suffix += 1
                }
                try? fileManager.moveItem(at: URL(fileURLWithPath: folderGroup.folderA), to: destURL)

                DispatchQueue.main.async {
                    self.folderDuplicateGroups.removeAll { $0.id == folderGroup.id }
                    for file in folderGroup.matchedGroups.flatMap({ $0.files }) where file.path == folderGroup.folderB {
                        self.deletedPaths.insert(file.fullPath)
                    }
                    self.totalRecovered += Int64(folderGroup.totalSizeBytes)
                }
                mergedCount += 1
            }

            DispatchQueue.main.async {
                self.isScanning = false
                self.progress = 1.0
                let errMsg = errorCount > 0 ? " (\(errorCount) errors)" : ""
                self.status = "Merged \(mergedCount) folder pair(s)\(errMsg)."
            }
        }
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
