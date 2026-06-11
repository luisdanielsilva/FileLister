import Foundation
import Combine

struct CloudFolder: Identifiable, Hashable {
    let id: String       // "root" or a drive item id
    let name: String
    let path: String     // display path
}

struct CloudFileInfo: Identifiable, Hashable {
    let id: String        // drive item id
    let name: String
    let size: Int64
    let path: String      // display path within the drive
    let hash: String      // quickXorHash
    let webURL: String?

    var fullPath: String { path.isEmpty ? name : path + "/" + name }
}

struct CloudDupGroup: Identifiable {
    let id = UUID()
    let hash: String
    var files: [CloudFileInfo]
    var name: String { files.first?.name ?? "" }
    var sizeBytes: Int64 { files.first?.size ?? 0 }
    func reclaimable(excluding deleted: Set<String>) -> Int64 {
        let live = files.filter { !deleted.contains($0.id) }
        return Int64(max(0, live.count - 1)) * sizeBytes
    }
}

// A cluster of OneDrive folders that share most of their content.
struct CloudFolderDupGroup: Identifiable {
    let id = UUID()
    let folders: [String]              // cluster of duplicate folder paths; folders[0] = keep (most files)
    let matchedGroups: [CloudDupGroup] // content shared across the cluster's folders (2+ copies = removable)
    let filesToMove: [CloudFileInfo]   // one representative per distinct content the keep folder lacks
    let keepFileNames: Set<String>     // names already in the keep folder (for collision handling on merge)
    let keptBytes: Int64               // total size of the kept folder's existing files (retained on merge)
    let keptCount: Int                 // number of files already in the kept folder (retained on merge)
    let matchRatio: Double             // 0.75–1.0 (strongest pairwise similarity in the cluster)

    var keepFolder: String { folders.first ?? "" }
    var keepName: String { (keepFolder as NSString).lastPathComponent }
    var otherFolders: [String] { Array(folders.dropFirst()) }
    var otherName: String { (otherFolders.first.map { ($0 as NSString).lastPathComponent }) ?? keepName }

    func reclaimable(excluding deleted: Set<String>) -> Int64 {
        matchedGroups.reduce(0) { $0 + $1.reclaimable(excluding: deleted) }
    }
}

@MainActor
final class RemoteEngine: ObservableObject {
    @Published var isScanning = false
    @Published var progress = 0.0
    @Published var status = "Connect and search to find duplicates in OneDrive."
    @Published var groups: [CloudDupGroup] = []
    @Published var folderGroups: [CloudFolderDupGroup] = []
    @Published var deletedIDs: Set<String> = []
    @Published var hitLimit = false
    @Published var lastLogURL: URL? = nil

    private var shouldStop = false
    private let folderMatchThreshold = 0.75
    private var folderPathToID: [String: String] = [:]   // display path → drive item id (for folder merge)

    // The active remote backend (OneDrive in Phase 1). Used for auth tokens; listing,
    // crawl, and mutations still build Graph requests directly until issue #8.
    let provider: any RemoteProvider

    init(provider: any RemoteProvider) {
        self.provider = provider
    }

    // Merge controls (mirror local Folders mode).
    @Published var renameKeptFolder = false
    @Published var safeMergeToNewFolder = false   // copy the merged result into a new OneDrive folder, keep originals

    func stop() { shouldStop = true; status = "Stopping…" }

    // All content groups currently displayed, regardless of mode (for nav/preview).
    var displayGroups: [CloudDupGroup] {
        folderGroups.isEmpty ? groups : folderGroups.flatMap { $0.matchedGroups }
    }

    // MARK: Scan

    func scan(folders: [CloudFolder], folderMode: Bool = false) {
        shouldStop = false
        isScanning = true
        progress = 0
        groups = []
        folderGroups = []
        deletedIDs = []
        hitLimit = false
        status = "Connecting…"
        folderPathToID = [:]
        for f in folders { folderPathToID[f.path] = f.id }   // seed with the selected roots

        Task {
            guard let token = await provider.validAccessToken() else {
                self.isScanning = false; self.status = "Not connected. Please reconnect OneDrive."
                return
            }
            do {
                let roots = folders.map { $0.id }
                let files = try await crawl(token: token, roots: roots)
                let limitNote = self.hitLimit ? " (reached the scan limit — raise it in Settings)" : ""
                if folderMode {
                    let fgroups = self.clusterFolders(files)
                    self.folderGroups = fgroups
                    let dupes = fgroups.reduce(0) { $0 + $1.matchedGroups.reduce(0) { $0 + $1.files.count - 1 } }
                    self.status = "Found \(fgroups.count) duplicate folder cluster(s) · \(dupes) removable\(limitNote)."
                } else {
                    let grouped = self.group(files)
                    self.groups = grouped
                    let dupes = grouped.reduce(0) { $0 + $1.files.count - 1 }
                    self.status = "Found \(grouped.count) duplicate group(s) · \(dupes) removable\(limitNote)."
                }
                self.isScanning = false
                self.progress = 1
            } catch {
                self.isScanning = false
                self.status = "OneDrive scan failed: \(error.localizedDescription)"
            }
        }
    }

    private func childrenURL(_ folderID: String) -> String {
        let sel = "?$select=id,name,size,file,folder,parentReference,webUrl&$top=200"
        return folderID == "root"
            ? OneDriveConfig.graphBase + "/me/drive/root/children" + sel
            : OneDriveConfig.graphBase + "/me/drive/items/\(folderID)/children" + sel
    }

    // Recursively enumerate the selected folders' subtrees, capped by count / bytes.
    private func crawl(token: String, roots: [String]) async throws -> [CloudFileInfo] {
        let fileLimit = OneDrivePreferences.shared.fileLimit
        let byteLimit = OneDrivePreferences.shared.byteLimit
        var files: [CloudFileInfo] = []
        var totalBytes: Int64 = 0
        var queue: [String] = roots.isEmpty ? ["root"] : roots
        var qi = 0

        while qi < queue.count, !shouldStop {
            let folderID = queue[qi]; qi += 1
            var next: String? = childrenURL(folderID)
            while let urlStr = next, !shouldStop {
                self.status = "Scanning OneDrive… \(files.count) file(s)"
                guard let url = URL(string: urlStr) else { break }
                var req = URLRequest(url: url)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                    throw OneDriveError.network("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)")
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }

                for item in json["value"] as? [[String: Any]] ?? [] {
                    if item["folder"] != nil {
                        if let fid = item["id"] as? String {
                            queue.append(fid)   // recurse into subfolders
                            // Record this folder's display path → id for folder merge.
                            let name = item["name"] as? String ?? ""
                            let parent = item["parentReference"] as? [String: Any]
                            let rawPath = (parent?["path"] as? String) ?? ""
                            let parentPath = rawPath.replacingOccurrences(of: "/drive/root:", with: "")
                                .removingPercentEncoding ?? rawPath
                            self.folderPathToID[parentPath.isEmpty ? "/" + name : parentPath + "/" + name] = fid
                        }
                        continue
                    }
                    guard let file = item["file"] as? [String: Any] else { continue }
                    let hashes = file["hashes"] as? [String: Any]
                    let quickXor = (hashes?["quickXorHash"] as? String) ?? ""
                    let id = item["id"] as? String ?? ""
                    let name = item["name"] as? String ?? "?"
                    let size = (item["size"] as? Int64) ?? Int64(item["size"] as? Int ?? 0)
                    let parent = item["parentReference"] as? [String: Any]
                    let rawPath = (parent?["path"] as? String) ?? ""
                    let path = rawPath.replacingOccurrences(of: "/drive/root:", with: "")
                        .removingPercentEncoding ?? rawPath
                    let web = item["webUrl"] as? String

                    files.append(CloudFileInfo(id: id, name: name, size: size, path: path, hash: quickXor, webURL: web))
                    totalBytes += size
                    if files.count >= fileLimit || totalBytes >= byteLimit {
                        hitLimit = true
                        return files
                    }
                }
                next = json["@odata.nextLink"] as? String
            }
        }
        return files
    }

    // Lists child folders of a folder (nil/"root" = drive root) for the folder picker.
    func listFolders(parentID: String?) async -> [CloudFolder] {
        guard let token = await provider.validAccessToken() else { return [] }
        var urlStr: String? = {
            let base = (parentID == nil || parentID == "root")
                ? OneDriveConfig.graphBase + "/me/drive/root/children"
                : OneDriveConfig.graphBase + "/me/drive/items/\(parentID!)/children"
            return base + "?$select=id,name,folder,parentReference&$top=200"
        }()
        var out: [CloudFolder] = []
        while let s = urlStr {
            guard let url = URL(string: s) else { break }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }
            for item in json["value"] as? [[String: Any]] ?? [] {
                guard item["folder"] != nil else { continue }
                let id = item["id"] as? String ?? ""
                let name = item["name"] as? String ?? "?"
                let raw = ((item["parentReference"] as? [String: Any])?["path"] as? String) ?? ""
                let parentPath = raw.replacingOccurrences(of: "/drive/root:", with: "").removingPercentEncoding ?? raw
                out.append(CloudFolder(id: id, name: name, path: (parentPath + "/" + name)))
            }
            urlStr = json["@odata.nextLink"] as? String
        }
        return out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // Create a new subfolder under `parentID` and return it (display path mirrors listFolders).
    func createFolder(named name: String, in parentID: String?) async -> CloudFolder? {
        guard let token = await provider.validAccessToken() else { return nil }
        let base = (parentID == nil || parentID == "root")
            ? OneDriveConfig.graphBase + "/me/drive/root/children"
            : OneDriveConfig.graphBase + "/me/drive/items/\(parentID!)/children"
        guard let url = URL(string: base) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name, "folder": [:] as [String: Any],
                                   "@microsoft.graph.conflictBehavior": "rename"]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...201).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String, let nm = json["name"] as? String else { return nil }
        let raw = ((json["parentReference"] as? [String: Any])?["path"] as? String) ?? ""
        let parentPath = raw.replacingOccurrences(of: "/drive/root:", with: "").removingPercentEncoding ?? raw
        return CloudFolder(id: id, name: nm, path: parentPath + "/" + nm)
    }

    private func group(_ files: [CloudFileInfo]) -> [CloudDupGroup] {
        var byHash: [String: [CloudFileInfo]] = [:]
        for f in files where !f.hash.isEmpty { byHash[f.hash, default: []].append(f) }
        return byHash.compactMap { (hash, fs) in
            fs.count > 1 ? CloudDupGroup(hash: hash, files: fs.sorted { $0.fullPath < $1.fullPath }) : nil
        }
        .sorted { $0.reclaimable(excluding: []) > $1.reclaimable(excluding: []) }
    }

    // Cluster folders that share most of their content, via union-find over
    // pairs of folders whose match ratio (shared hashes / smaller file count)
    // meets the threshold. Mirrors the local Folders detection (quickXorHash here).
    private func clusterFolders(_ files: [CloudFileInfo]) -> [CloudFolderDupGroup] {
        var hashGroups: [String: [CloudFileInfo]] = [:]
        for f in files where !f.hash.isEmpty { hashGroups[f.hash, default: []].append(f) }

        var folderFileCounts: [String: Int] = [:]
        var folderSizes: [String: Int64] = [:]
        for f in files {
            folderFileCounts[f.path, default: 0] += 1
            folderSizes[f.path, default: 0] += f.size
        }

        // Pairwise shared-hash sets to decide which folders are connected.
        var folderPairHashes: [String: Set<String>] = [:]
        var folderPairFolders: [String: (String, String)] = [:]
        for (hash, fs) in hashGroups {
            guard fs.count > 1 else { continue }
            let folderSet = Set(fs.map { $0.path })
            guard folderSet.count > 1 else { continue }
            let arr = folderSet.sorted()
            for i in 0..<arr.count {
                for j in (i+1)..<arr.count {
                    let a = arr[i], b = arr[j]
                    let key = "\(a)|\(b)"
                    folderPairHashes[key, default: []].insert(hash)
                    folderPairFolders[key] = (a, b)
                }
            }
        }

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
            let ra = find(a), rb = find(b); if ra != rb { parent[ra] = rb }
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

        var clusters: [String: [String]] = [:]
        for folder in folderFileCounts.keys { clusters[find(folder), default: []].append(folder) }

        var out: [CloudFolderDupGroup] = []
        for (_, clusterFolders) in clusters {
            guard clusterFolders.count >= 2 else { continue }
            let clusterSet = Set(clusterFolders)

            // keep = most files (tie: larger total size)
            let keep = clusterFolders.max(by: { lhs, rhs in
                let lc = folderFileCounts[lhs] ?? 0, rc = folderFileCounts[rhs] ?? 0
                if lc != rc { return lc < rc }
                return (folderSizes[lhs] ?? 0) < (folderSizes[rhs] ?? 0)
            })!
            let ordered = [keep] + clusterFolders.filter { $0 != keep }.sorted()

            var matchedGroups: [CloudDupGroup] = []
            for (hash, fs) in hashGroups {
                let inCluster = fs.filter { clusterSet.contains($0.path) }
                if inCluster.count >= 2 {
                    matchedGroups.append(CloudDupGroup(hash: hash, files: inCluster.sorted { $0.fullPath < $1.fullPath }))
                }
            }
            guard !matchedGroups.isEmpty else { continue }

            // Files the keep folder lacks: one representative per distinct content
            // (unhashed files are always treated as unique). Dup copies of content
            // already in keep are left to be trashed with their folders.
            let keepHashes = Set(files.filter { $0.path == keep && !$0.hash.isEmpty }.map { $0.hash })
            let keepFileNames = Set(files.filter { $0.path == keep }.map { $0.name })
            var movedHashes = Set<String>()
            var filesToMove: [CloudFileInfo] = []
            for f in files where clusterSet.contains(f.path) && f.path != keep {
                if !f.hash.isEmpty {
                    if keepHashes.contains(f.hash) || movedHashes.contains(f.hash) { continue }
                    movedHashes.insert(f.hash)
                }
                filesToMove.append(f)
            }

            var ratio = folderMatchThreshold
            for (key, r) in pairRatio {
                if let (a, b) = folderPairFolders[key], clusterSet.contains(a), clusterSet.contains(b) {
                    ratio = max(ratio, r)
                }
            }

            let keepFiles = files.filter { $0.path == keep }
            let keptBytes = keepFiles.reduce(Int64(0)) { $0 + $1.size }
            out.append(CloudFolderDupGroup(
                folders: ordered,
                matchedGroups: matchedGroups.sorted { $0.reclaimable(excluding: []) > $1.reclaimable(excluding: []) },
                filesToMove: filesToMove,
                keepFileNames: keepFileNames,
                keptBytes: keptBytes,
                keptCount: keepFiles.count,
                matchRatio: min(1.0, ratio)
            ))
        }
        return out.sorted { $0.matchRatio > $1.matchRatio }
    }

    // MARK: Preview (download with progress to a temp file, then Quick Look)

    @Published var previewingID: String? = nil
    @Published var previewProgress: Double = 0   // 0…1
    private var downloader: CloudDownloader?

    func preview(_ file: CloudFileInfo) {
        previewingID = file.id
        previewProgress = 0
        status = "Downloading \(file.name)…"
        Task {
            guard let token = await provider.validAccessToken(),
                  let url = URL(string: OneDriveConfig.graphBase + "/me/drive/items/\(file.id)/content") else {
                self.previewingID = nil
                self.status = "Couldn't preview \(file.name)."
                return
            }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("FileLister-cloud-preview", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let dest = tmp.appendingPathComponent(file.name)

            let dl = CloudDownloader(destination: dest)
            dl.onProgress = { [weak self] p in self?.previewProgress = p }
            dl.onFinish = { [weak self] success in
                guard let self else { return }
                self.previewingID = nil
                if success {
                    QuickLookManager.shared.showPreview(url: dest)
                    self.status = ""
                } else {
                    self.status = "Couldn't download \(file.name) for preview."
                }
            }
            self.downloader = dl
            dl.start(request: req)
        }
    }

    // MARK: Delete

    func deleteDuplicates(in group: CloudDupGroup) {
        let live = group.files.filter { !deletedIDs.contains($0.id) }
        guard live.count > 1 else { return }
        let keep = live[0]
        let targets = Array(live.dropFirst())
        delete(targets, keep: keep)
    }

    // Delete a single cloud file (keeps at least one copy in the group).
    func deleteFile(_ file: CloudFileInfo, in group: CloudDupGroup) {
        let live = group.files.filter { !deletedIDs.contains($0.id) }
        guard live.count > 1, live.contains(where: { $0.id == file.id }) else { return }
        let keep = live.first { $0.id != file.id }
        delete([file], keep: keep)
    }

    func deleteAll() {
        var keepBy: [String: CloudFileInfo] = [:]
        var targets: [CloudFileInfo] = []
        for g in groups {
            let live = g.files.filter { !deletedIDs.contains($0.id) }
            guard live.count > 1 else { continue }
            keepBy[g.hash] = live[0]
            targets.append(contentsOf: live.dropFirst())
        }
        guard !targets.isEmpty else { return }
        delete(targets, keep: nil, keepByHash: keepBy)
    }

    // Delete every removable duplicate across all detected folder clusters.
    func deleteAllFolders() {
        var keepBy: [String: CloudFileInfo] = [:]
        var targets: [CloudFileInfo] = []
        for fg in folderGroups {
            for g in fg.matchedGroups {
                let live = g.files.filter { !deletedIDs.contains($0.id) }
                guard live.count > 1 else { continue }
                keepBy[g.hash] = live[0]
                targets.append(contentsOf: live.dropFirst())
            }
        }
        guard !targets.isEmpty else { return }
        delete(targets, keep: nil, keepByHash: keepBy)
    }

    // MARK: Folder merge (in-place: move uniques into keep, recycle the other folders)

    func mergeFolders(_ groups: [CloudFolderDupGroup],
                      mergedName: @escaping (String, String) -> String,
                      logDir: URL?) {
        guard !groups.isEmpty else { return }
        let rename = renameKeptFolder
        shouldStop = false
        isScanning = true
        status = "Merging \(groups.count) folder cluster(s) in OneDrive…"
        Task {
            guard let token = await provider.validAccessToken() else {
                self.isScanning = false; self.status = "Not connected."; return
            }
            var clusters: [MergeLogCluster] = []
            var totalErrors = 0, merged = 0
            for g in groups {
                if shouldStop { break }
                let (cluster, errors) = await self.mergeOne(g, rename: rename, mergedName: mergedName, token: token)
                clusters.append(cluster); totalErrors += errors; merged += 1
            }
            self.writeMergeLog(clusters, to: logDir)
            let mergedIDs = Set(groups.map { $0.id })
            self.folderGroups.removeAll { mergedIDs.contains($0.id) }
            self.isScanning = false
            let errMsg = totalErrors > 0 ? " (\(totalErrors) error(s))" : ""
            self.status = "Merged \(merged) folder cluster(s) in OneDrive\(errMsg)."
        }
    }

    private func mergeOne(_ g: CloudFolderDupGroup, rename: Bool,
                          mergedName: (String, String) -> String, token: String) async -> (MergeLogCluster, Int) {
        let keep = g.keepFolder
        var errors = 0
        var entries: [MergeLogEntry] = []
        guard let keepID = folderPathToID[keep] else {
            entries.append(MergeLogEntry(action: "ERROR", fileName: g.keepName,
                sourcePath: "OneDrive:" + keep, sourceFolder: "OneDrive:" + keep,
                destinationPath: "", destinationFolder: "", sizeBytes: 0, sha256: "",
                note: "could not resolve keep folder id — cluster skipped"))
            return (MergeLogCluster(keepFolder: "OneDrive:" + keep, otherFolders: g.otherFolders.map { "OneDrive:" + $0 },
                resultName: g.keepName, resultPath: "OneDrive:" + keep, entries: entries), 1)
        }

        // 1. Move unique files into keep (rename on name collision).
        var usedNames = g.keepFileNames
        for f in g.filesToMove {
            if shouldStop { break }
            var destName = f.name
            var renamed = false
            if usedNames.contains(destName) {
                renamed = true
                let srcFolderName = (f.path as NSString).lastPathComponent
                destName = FileScanner.resolveCollisionName(for: f.name, sourceFolderName: srcFolderName)
                var suffix = 2
                while usedNames.contains(destName) {
                    let ext = (destName as NSString).pathExtension
                    let base = ext.isEmpty ? destName : String(destName.dropLast(ext.count + 1))
                    destName = ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
                    suffix += 1
                }
            }
            let ok = await moveItem(id: f.id, toParent: keepID, newName: renamed ? destName : nil, token: token)
            if ok { usedNames.insert(destName) } else { errors += 1 }
            entries.append(MergeLogEntry(
                action: ok ? (renamed ? "MOVED+RENAMED" : "MOVED") : "ERROR",
                fileName: f.name, sourcePath: "OneDrive:" + f.fullPath, sourceFolder: "OneDrive:" + f.path,
                destinationPath: ok ? "OneDrive:" + keep + "/" + destName : "", destinationFolder: ok ? "OneDrive:" + keep : "",
                sizeBytes: Int(f.size), sha256: "quickXor:" + f.hash,
                note: ok ? (renamed ? "renamed to \(destName) (name collision)" : "") : "move failed"))
        }

        // 2. Record removable duplicate copies (trashed along with their folders).
        let moveIDs = Set(g.filesToMove.map { $0.id })
        for mg in g.matchedGroups {
            for f in mg.files where f.path != keep && !moveIDs.contains(f.id) {
                entries.append(MergeLogEntry(action: "TRASHED", fileName: f.name,
                    sourcePath: "OneDrive:" + f.fullPath, sourceFolder: "OneDrive:" + f.path,
                    destinationPath: "OneDrive recycle bin", destinationFolder: "OneDrive recycle bin",
                    sizeBytes: Int(f.size), sha256: "quickXor:" + f.hash, note: "duplicate of kept copy"))
                self.deletedIDs.insert(f.id)
            }
        }

        // 3. Recycle every other folder in the cluster.
        for other in g.otherFolders {
            if shouldStop { break }
            // Safety: never recycle a folder that contains the keep folder — doing
            // so would take the keep (and its merged files) with it.
            if keep == other || keep.hasPrefix(other + "/") {
                entries.append(MergeLogEntry(action: "SKIPPED", fileName: (other as NSString).lastPathComponent,
                    sourcePath: "OneDrive:" + other, sourceFolder: "OneDrive:" + other,
                    destinationPath: "", destinationFolder: "", sizeBytes: 0, sha256: "",
                    note: "kept — this folder contains the keep folder"))
                continue
            }
            guard let oid = folderPathToID[other] else {
                errors += 1
                entries.append(MergeLogEntry(action: "ERROR", fileName: (other as NSString).lastPathComponent,
                    sourcePath: "OneDrive:" + other, sourceFolder: "OneDrive:" + other,
                    destinationPath: "", destinationFolder: "", sizeBytes: 0, sha256: "",
                    note: "could not resolve folder id"))
                continue
            }
            let ok = await deleteItem(id: oid, token: token)
            if !ok { errors += 1 }
            entries.append(MergeLogEntry(
                action: ok ? "FOLDER_TRASHED" : "ERROR",
                fileName: (other as NSString).lastPathComponent,
                sourcePath: "OneDrive:" + other, sourceFolder: "OneDrive:" + (other as NSString).deletingLastPathComponent,
                destinationPath: ok ? "OneDrive recycle bin" : "", destinationFolder: ok ? "OneDrive recycle bin" : "",
                sizeBytes: 0, sha256: "", note: ok ? "folder removed after its unique files were moved into keep" : "folder delete failed"))
        }

        // 4. Optionally rename keep.
        var resultPath = keep
        if rename {
            let newName = mergedName(g.keepFolder, g.otherFolders.first ?? g.keepFolder)
            if !newName.isEmpty, newName != g.keepName, await renameItem(id: keepID, newName: newName, token: token) {
                resultPath = (keep as NSString).deletingLastPathComponent + "/" + newName
            }
        }

        return (MergeLogCluster(keepFolder: "OneDrive:" + keep, otherFolders: g.otherFolders.map { "OneDrive:" + $0 },
            resultName: (resultPath as NSString).lastPathComponent, resultPath: "OneDrive:" + resultPath, entries: entries), errors)
    }

    private func moveItem(id: String, toParent parentID: String, newName: String?, token: String) async -> Bool {
        guard let url = URL(string: OneDriveConfig.graphBase + "/me/drive/items/\(id)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["parentReference": ["id": parentID]]
        if let n = newName { body["name"] = n }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) { return true }
        return false
    }

    private func renameItem(id: String, newName: String, token: String) async -> Bool {
        guard let url = URL(string: OneDriveConfig.graphBase + "/me/drive/items/\(id)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": newName])
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) { return true }
        return false
    }

    private func writeMergeLog(_ clusters: [MergeLogCluster], to dir: URL?, mode: String = "OneDrive folder merge") {
        guard !clusters.isEmpty, let target = dir ?? MergeLogWriter.defaultAppLogDirectory() else { return }
        let report = MergeLogReport(timestamp: Date(), appVersion: MergeLogWriter.appVersion,
                                    mode: mode, renameKeptFolder: renameKeptFolder, clusters: clusters)
        lastLogURL = MergeLogWriter.write(report, to: target)
    }

    // MARK: Folder safe merge (copy to a new OneDrive folder; originals untouched)

    // For each cluster, copy the keep folder's subtree into `parentID` under the merged
    // name, then copy the cluster's unique files in (renaming on collision). Nothing is
    // moved or recycled — the originals (and their duplicates) are left in place.
    func safeMergeFolders(_ groups: [CloudFolderDupGroup],
                          intoParent parentID: String,
                          mergedName: @escaping (String, String) -> String,
                          logDir: URL?) {
        guard !groups.isEmpty else { return }
        shouldStop = false
        isScanning = true
        status = "Creating \(groups.count) merged copy(ies) in OneDrive…"
        Task {
            guard let token = await provider.validAccessToken() else {
                self.isScanning = false; self.status = "Not connected."; return
            }
            var clusters: [MergeLogCluster] = []
            var totalErrors = 0, made = 0
            for g in groups {
                if shouldStop { break }
                let (cluster, errors) = await self.safeMergeOne(g, intoParent: parentID, mergedName: mergedName, token: token)
                clusters.append(cluster); totalErrors += errors
                if errors == 0 { made += 1 }
            }
            self.writeMergeLog(clusters, to: logDir, mode: "OneDrive copy to new folder (originals kept)")
            self.isScanning = false
            let errMsg = totalErrors > 0 ? " (\(totalErrors) error(s))" : ""
            self.status = "Created \(made) merged copy(ies) in OneDrive\(errMsg). Originals untouched."
        }
    }

    private func safeMergeOne(_ g: CloudFolderDupGroup, intoParent parentID: String,
                              mergedName: (String, String) -> String, token: String) async -> (MergeLogCluster, Int) {
        let keep = g.keepFolder
        var errors = 0
        var entries: [MergeLogEntry] = []
        guard let keepID = folderPathToID[keep] else {
            entries.append(MergeLogEntry(action: "ERROR", fileName: g.keepName,
                sourcePath: "OneDrive:" + keep, sourceFolder: "OneDrive:" + keep,
                destinationPath: "", destinationFolder: "", sizeBytes: 0, sha256: "",
                note: "could not resolve keep folder id — cluster skipped"))
            return (MergeLogCluster(keepFolder: "OneDrive:" + keep, otherFolders: g.otherFolders.map { "OneDrive:" + $0 },
                resultName: g.keepName, resultPath: "OneDrive:" + keep, entries: entries), 1)
        }

        // 1. Copy the keep folder's whole subtree into the destination as the merge base.
        let base = mergedName(g.keepFolder, g.otherFolders.first ?? g.keepFolder)
        let resultName = base.isEmpty ? g.keepName : base
        guard let newFolderID = await copyItem(id: keepID, toParent: parentID, name: resultName, token: token) else {
            entries.append(MergeLogEntry(action: "ERROR", fileName: resultName,
                sourcePath: "OneDrive:" + keep, sourceFolder: "OneDrive:" + keep,
                destinationPath: "", destinationFolder: "", sizeBytes: 0, sha256: "",
                note: "failed to copy keep folder as the merge base"))
            return (MergeLogCluster(keepFolder: "OneDrive:" + keep, otherFolders: g.otherFolders.map { "OneDrive:" + $0 },
                resultName: resultName, resultPath: "OneDrive:" + resultName, entries: entries), 1)
        }
        entries.append(MergeLogEntry(action: "FOLDER_COPIED", fileName: resultName,
            sourcePath: "OneDrive:" + keep, sourceFolder: "OneDrive:" + (keep as NSString).deletingLastPathComponent,
            destinationPath: "OneDrive:" + resultName, destinationFolder: "OneDrive", sizeBytes: 0, sha256: "",
            note: "keep folder copied as the merge base"))

        // 2. Copy each unique file into the new folder (rename on collision with keep's names).
        var usedNames = g.keepFileNames
        for f in g.filesToMove {
            if shouldStop { break }
            var destName = f.name
            var renamed = false
            if usedNames.contains(destName) {
                renamed = true
                let srcFolderName = (f.path as NSString).lastPathComponent
                destName = FileScanner.resolveCollisionName(for: f.name, sourceFolderName: srcFolderName)
                var suffix = 2
                while usedNames.contains(destName) {
                    let ext = (destName as NSString).pathExtension
                    let baseName = ext.isEmpty ? destName : String(destName.dropLast(ext.count + 1))
                    destName = ext.isEmpty ? "\(baseName)_\(suffix)" : "\(baseName)_\(suffix).\(ext)"
                    suffix += 1
                }
            }
            let ok = await copyItem(id: f.id, toParent: newFolderID, name: destName, token: token) != nil
            if ok { usedNames.insert(destName) } else { errors += 1 }
            entries.append(MergeLogEntry(
                action: ok ? (renamed ? "COPIED+RENAMED" : "COPIED") : "ERROR",
                fileName: f.name, sourcePath: "OneDrive:" + f.fullPath, sourceFolder: "OneDrive:" + f.path,
                destinationPath: ok ? "OneDrive:" + resultName + "/" + destName : "", destinationFolder: ok ? "OneDrive:" + resultName : "",
                sizeBytes: Int(f.size), sha256: "quickXor:" + f.hash,
                note: ok ? (renamed ? "renamed to \(destName) (name collision)" : "") : "copy failed"))
        }

        // 3. Record duplicate copies intentionally not copied (left untouched in the originals).
        let moveIDs = Set(g.filesToMove.map { $0.id })
        for mg in g.matchedGroups {
            for f in mg.files where f.path != keep && !moveIDs.contains(f.id) {
                entries.append(MergeLogEntry(action: "SKIPPED", fileName: f.name,
                    sourcePath: "OneDrive:" + f.fullPath, sourceFolder: "OneDrive:" + f.path,
                    destinationPath: "", destinationFolder: "", sizeBytes: Int(f.size),
                    sha256: "quickXor:" + f.hash, note: "duplicate — not copied"))
            }
        }

        return (MergeLogCluster(keepFolder: "OneDrive:" + keep, otherFolders: g.otherFolders.map { "OneDrive:" + $0 },
            resultName: resultName, resultPath: "OneDrive:" + resultName, entries: entries), errors)
    }

    // Graph copy is asynchronous: POST returns 202 + a monitor URL we poll until the
    // copy completes. Returns the new item's id, or nil on failure.
    private func copyItem(id: String, toParent parentID: String, name: String?, token: String) async -> String? {
        guard let url = URL(string: OneDriveConfig.graphBase + "/me/drive/items/\(id)/copy") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["parentReference": ["id": parentID]]
        if let n = name { body["name"] = n }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return nil }
        if http.statusCode == 202, let monitor = http.value(forHTTPHeaderField: "Location") {
            return await pollCopyMonitor(monitor)
        }
        // Fallback: a tenant may return the created item inline.
        if (200...201).contains(http.statusCode),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json["id"] as? String
        }
        return nil
    }

    // Poll the async-copy monitor URL until the operation completes; return the new id.
    private func pollCopyMonitor(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        for _ in 0..<180 {   // ~2 min at 700 ms intervals
            if shouldStop { return nil }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let st = json["status"] as? String
            if st == "completed" { return (json["resourceId"] as? String) ?? (json["id"] as? String) }
            if st == "failed" { return nil }
            if st == nil, let iid = json["id"] as? String { return iid }   // redirected to the finished item
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        return nil
    }

    private func delete(_ targets: [CloudFileInfo], keep: CloudFileInfo?, keepByHash: [String: CloudFileInfo] = [:]) {
        guard !targets.isEmpty else { return }
        isScanning = true
        status = "Deleting \(targets.count) file(s) from OneDrive…"
        Task {
            guard let token = await provider.validAccessToken() else {
                self.isScanning = false; self.status = "Not connected."; return
            }
            var ok = 0, errors = 0
            var logEntries: [MergeLogEntry] = []
            if let k = keep {
                logEntries.append(keptEntry(k))
            }
            for t in targets {
                if shouldStop { break }
                let success = await deleteItem(id: t.id, token: token)
                if success {
                    ok += 1
                    self.deletedIDs.insert(t.id)
                    let kept = keep ?? keepByHash[t.hash]
                    if keep == nil, let kk = kept { logEntries.append(keptEntry(kk)) }
                    logEntries.append(trashedEntry(t, keptName: kept?.name))
                } else { errors += 1 }
            }
            self.writeCloudLog(logEntries)
            self.isScanning = false
            let errMsg = errors > 0 ? " (\(errors) failed)" : ""
            self.status = "Moved \(ok) OneDrive file(s) to the recycle bin\(errMsg)."
        }
    }

    private func deleteItem(id: String, token: String) async -> Bool {
        guard let url = URL(string: OneDriveConfig.graphBase + "/me/drive/items/\(id)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let http = resp as? HTTPURLResponse, http.statusCode == 204 {
            return true
        }
        return false
    }

    // MARK: Logging

    private func keptEntry(_ f: CloudFileInfo) -> MergeLogEntry {
        MergeLogEntry(action: "KEPT", fileName: f.name, sourcePath: "OneDrive:" + f.fullPath, sourceFolder: "OneDrive:" + f.path,
                      destinationPath: "OneDrive:" + f.fullPath, destinationFolder: "OneDrive:" + f.path,
                      sizeBytes: Int(f.size), sha256: "quickXor:" + f.hash, note: "kept original")
    }
    private func trashedEntry(_ f: CloudFileInfo, keptName: String?) -> MergeLogEntry {
        MergeLogEntry(action: "TRASHED", fileName: f.name, sourcePath: "OneDrive:" + f.fullPath, sourceFolder: "OneDrive:" + f.path,
                      destinationPath: "OneDrive recycle bin", destinationFolder: "OneDrive recycle bin",
                      sizeBytes: Int(f.size), sha256: "quickXor:" + f.hash,
                      note: "duplicate of \(keptName ?? "kept copy") · OneDrive recycle bin")
    }
    private func writeCloudLog(_ entries: [MergeLogEntry]) {
        guard !entries.isEmpty, let dir = MergeLogWriter.defaultAppLogDirectory() else { return }
        let cluster = MergeLogCluster(keepFolder: "OneDrive", otherFolders: [], resultName: "OneDrive cleanup", resultPath: "OneDrive", entries: entries)
        let report = MergeLogReport(timestamp: Date(), appVersion: MergeLogWriter.appVersion,
                                    mode: "OneDrive cleanup", renameKeptFolder: false, clusters: [cluster])
        lastLogURL = MergeLogWriter.write(report, to: dir)
    }
}

// Delegate-based downloader that reports byte progress and saves to a fixed destination.
final class CloudDownloader: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    var onProgress: ((Double) -> Void)?
    var onFinish: ((Bool) -> Void)?
    private var session: URLSession?

    init(destination: URL) { self.destination = destination }

    func start(request: URLRequest) {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: request).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.onProgress?(p) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Must move the temp file synchronously here — `location` is gone after this returns.
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        let ok = (try? fm.moveItem(at: location, to: destination)) != nil
        DispatchQueue.main.async { self.onProgress?(1); self.onFinish?(ok) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil { DispatchQueue.main.async { self.onFinish?(false) } }
    }
}
