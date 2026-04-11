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
}

class FileScanner: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var status: String = "Ready to start"
    @Published var isScanning: Bool = false
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var deletedPaths: Set<String> = []
    
    @Published var totalPotentialSavings: Int64 = 0
    @Published var totalRecovered: Int64 = 0
    
    @Published var useDeepAnalysis: Bool = false
    @Published var filterMediaOnly: Bool = false
    @Published var skipHiddenFiles: Bool = false
    
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
        
        guard let enumerator = fileManager.enumerator(at: sourceURL, includingPropertiesForKeys: keys, options: [], errorHandler: { url, error in return true }) else {
            DispatchQueue.main.async { self.isScanning = false }
            return
        }
        
        self.processedItems = 0
        var tracker: [String: [DuplicateFileInfo]] = [:]
        
        while let fileURL = enumerator.nextObject() as? URL {
            if shouldStop { break }
            do {
                let name = fileURL.lastPathComponent
                if skipHiddenFiles && name.hasPrefix(".") { continue }
                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                let isDir = resourceValues.isDirectory ?? false
                let ext = fileURL.pathExtension.lowercased()
                if filterMediaOnly && !isDir && !mediaExtensions.contains(ext) { continue }
                
                let path = fileURL.deletingLastPathComponent().path
                let sizeInBytes = resourceValues.fileSize ?? 0
                let sizeStr = formatSize(sizeInBytes)
                
                if !isDir {
                    let key = "\(name)_\(sizeInBytes)"
                    let info = DuplicateFileInfo(path: path, name: name, size: sizeStr, sizeBytes: sizeInBytes)
                    if tracker[key] != nil { tracker[key]?.append(info) } else { tracker[key] = [info] }
                }
                
                processedItems += 1
                let currentProgress = Double(processedItems) / Double(max(1, totalItems))
                DispatchQueue.main.async { self.progress = currentProgress; self.status = "Scanning: \(name)" }
            } catch { continue }
        }
        
        var groups = tracker.values
            .filter { $0.count > 1 }
            .map { DuplicateGroup(name: $0[0].name, size: $0[0].size, sizeBytes: $0[0].sizeBytes, files: $0) }
        
        if useDeepAnalysis && !shouldStop && !groups.isEmpty {
            DispatchQueue.main.async { self.status = "Deep Analysis (SHA-256)..." }
            groups = performDeepAnalysis(on: groups)
        }
        
        if !shouldStop {
            DispatchQueue.main.async {
                self.duplicateGroups = groups
                self.totalPotentialSavings = groups.reduce(0) { $0 + Int64($1.sizeBytes) * Int64($1.files.count - 1) }
                self.applySort()
                self.status = "Completed! \(groups.count) groups found."
                self.isScanning = false
                self.progress = 1.0
            }
        }
    }
    
    func toggleSort(criteria: SortCriteria) {
        if sortCriteria == criteria { sortOrder = (sortOrder == .ascending) ? .descending : .ascending }
        else { sortCriteria = criteria; sortOrder = .descending }
        applySort()
    }
    
    func applySort() {
        duplicateGroups.sort { (a, b) -> Bool in
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
            
            var hasher = SHA256()
            // USE MODERN Swift API (throws proper errors instead of NSException crash)
            while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
                hasher.update(data: data)
            }
            
            return hasher.finalize().map { String(format: "%02hhx", $0) }.joined()
        } catch {
            print("Warning: Could not hash cloud/locked file at \(path): \(error)")
            return nil // Gracefully skip instead of crashing
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
            guard let size1 = attr1[.size] as? Int, let size2 = attr2[.size] as? Int, size1 == size2 else { 
                print("Size mismatch: \(size1) vs \(size2)")
                return false 
            }
            
            while true {
                let data1 = try handle1.read(upToCount: 64 * 1024)
                let data2 = try handle2.read(upToCount: 64 * 1024)
                
                if data1 != data2 { return false }
                if data1 == nil || data1!.isEmpty { break }
            }
            return true
        } catch {
            print("Comparison error: \(error.localizedDescription)")
            return false
        }
    }

    func recycleFile(atPath fullPath: String) {
        let fileURL = URL(fileURLWithPath: fullPath)
        
        // SECURITY: Identify the original/reference file
        guard let group = self.duplicateGroups.first(where: { g in g.files.contains(where: { $0.fullPath == fullPath }) }) else { return }
        
        // Find the first active file that is NOT the one being deleted
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
                    let referenceFile = activeFiles[0] // First file is the Original
                    let referenceURL = URL(fileURLWithPath: referenceFile.fullPath)
                    
                    for i in 1..<activeFiles.count {
                        let file = activeFiles[i]
                        let fileURL = URL(fileURLWithPath: file.fullPath)
                        
                        if self.isContentIdentical(url1: fileURL, url2: referenceURL) {
                            toRecycle.append(fileURL)
                            totalSavingsInSession += Int64(group.sizeBytes)
                        } else {
                            skippedCount += 1
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
