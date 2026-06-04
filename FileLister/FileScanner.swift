import Foundation
import SwiftUI
import Combine
import AppKit
import CryptoKit

enum SortCriteria {
    case name, size, count
}

enum SortOrderEnum {
    case ascending, descending
}

struct DuplicateFileInfo: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let name: String
    let size: String
    let sizeBytes: Int
    var isSymlink: Bool = false

    var fullPath: String {
        return (path as NSString).appendingPathComponent(name)
    }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let name: String
    let size: String
    let sizeBytes: Int
    let files: [DuplicateFileInfo]
    var isSymlinkGroup: Bool = false
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
        let keys: [URLResourceKey] = [.fileSizeKey, .typeIdentifierKey, .isDirectoryKey]

        guard let enumerator = fileManager.enumerator(at: sourceURL, includingPropertiesForKeys: keys,
              options: [], errorHandler: { _, _ in return true }) else {
            DispatchQueue.main.async { self.isScanning = false }
            return
        }

        self.processedItems = 0
        var tracker: [String: [DuplicateFileInfo]] = [:]
        var symlinkTracker: [String: [DuplicateFileInfo]] = [:]  // keyed by target device:inode
        var allFilesPerFolder: [String: [DuplicateFileInfo]] = []  // folder path → all files

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
                    let key = "\(name)_\(sizeInBytes)"
                    let info = DuplicateFileInfo(path: path, name: name, size: sizeStr, sizeBytes: sizeInBytes)
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
            DispatchQueue.main.async { self.status = "Deep Analysis (SHA-256)..." }
            groups = performDeepAnalysis(on: groups)
        }
        
        if !shouldStop {
            self.detectFolderDuplicatesIfNeeded(allFiles: allFilesPerFolder, groups: &groups)
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
    
    private func detectFolderDuplicatesIfNeeded(allFiles: [String: [DuplicateFileInfo]], groups: inout [DuplicateGroup]) {
        guard detectFolderDuplicates else { return }

        // Count total files per folder
        var folderFileCounts: [String: Int] = [:]
        for (_, files) in allFiles {
            for file in files {
                folderFileCounts[file.path, default: 0] += 1
            }
        }

        // For each duplicate group, record which folder pairs share it
        // folderPairGroups: key = "folderA|folderB" (sorted), value = [DuplicateGroup]
        var folderPairGroups: [String: [DuplicateGroup]] = [:]
        var folderPairFolders: [String: (String, String)] = [:]

        for group in groups {
            let folders = Set(group.files.map { $0.path })
            let folderArray = Array(folders).sorted()
            for i in 0..<folderArray.count {
                for j in (i+1)..<folderArray.count {
                    let a = folderArray[i], b = folderArray[j]
                    let key = "\(a)|\(b)"
                    folderPairGroups[key, default: []].append(group)
                    folderPairFolders[key] = (a, b)
                }
            }
        }

        var detectedFolderGroups: [FolderDuplicateGroup] = []
        var consumedGroupIDs: Set<UUID> = []

        for (key, sharedGroups) in folderPairGroups {
            guard let (rawA, rawB) = folderPairFolders[key] else { continue }
            let countA = folderFileCounts[rawA] ?? 0
            let countB = folderFileCounts[rawB] ?? 0
            let minCount = min(countA, countB)
            guard minCount > 0 else { continue }

            let ratio = Double(sharedGroups.count) / Double(minCount)
            guard ratio >= folderMatchThreshold else { continue }

            // folderA = the one with more files (the "keep" side)
            let (folderA, folderB) = countA >= countB ? (rawA, rawB) : (rawB, rawA)

            let sharedFileNamesAndSizes = Set(sharedGroups.map { "\($0.name)_\($0.sizeBytes)" })

            let uniqueToA = (allFiles[folderA] ?? []).filter {
                !sharedFileNamesAndSizes.contains("\($0.name)_\($0.sizeBytes)")
            }
            let uniqueToB = (allFiles[folderB] ?? []).filter {
                !sharedFileNamesAndSizes.contains("\($0.name)_\($0.sizeBytes)")
            }

            detectedFolderGroups.append(FolderDuplicateGroup(
                folderA: folderA, folderB: folderB,
                matchedGroups: sharedGroups,
                uniqueToA: uniqueToA, uniqueToB: uniqueToB,
                matchRatio: ratio
            ))
            sharedGroups.forEach { consumedGroupIDs.insert($0.id) }
        }

        // Remove individual file groups that were fully consumed by a folder group
        groups = groups.filter { !consumedGroupIDs.contains($0.id) }
        folderDuplicateGroups = detectedFolderGroups
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

            DispatchQueue.main.async {
                self.folderDuplicateGroups.removeAll { $0.id == folderGroup.id }
                // Mark all matched files in B as deleted in the deletedPaths set
                for file in folderGroup.matchedGroups.flatMap({ $0.files }) where file.path == folderGroup.folderB {
                    self.deletedPaths.insert(file.fullPath)
                }
                self.totalRecovered += Int64(folderGroup.totalSizeBytes)
                self.isScanning = false
                if errors.isEmpty {
                    self.status = "Merge complete. \(folderGroup.folderB) moved to Trash."
                } else {
                    self.status = "Merge done with \(errors.count) error(s): \(errors.prefix(2).joined(separator: ", "))"
                }
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
