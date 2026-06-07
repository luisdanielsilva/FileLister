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

@MainActor
final class OneDriveEngine: ObservableObject {
    @Published var isScanning = false
    @Published var progress = 0.0
    @Published var status = "Connect and search to find duplicates in OneDrive."
    @Published var groups: [CloudDupGroup] = []
    @Published var deletedIDs: Set<String> = []
    @Published var hitLimit = false
    @Published var lastLogURL: URL? = nil

    private var shouldStop = false

    func stop() { shouldStop = true; status = "Stopping…" }

    // MARK: Scan

    func scan(auth: OneDriveAuth, folders: [CloudFolder]) {
        shouldStop = false
        isScanning = true
        progress = 0
        groups = []
        deletedIDs = []
        hitLimit = false
        status = "Connecting…"

        Task {
            guard let token = await auth.validAccessToken() else {
                self.isScanning = false; self.status = "Not connected. Please reconnect OneDrive."
                return
            }
            do {
                let roots = folders.map { $0.id }
                let files = try await crawl(token: token, roots: roots)
                let grouped = group(files)
                self.groups = grouped
                self.isScanning = false
                self.progress = 1
                let dupes = grouped.reduce(0) { $0 + $1.files.count - 1 }
                let limitNote = self.hitLimit ? " (reached the scan limit — raise it in Settings)" : ""
                self.status = "Found \(grouped.count) duplicate group(s) · \(dupes) removable\(limitNote)."
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
                        if let fid = item["id"] as? String { queue.append(fid) }   // recurse into subfolders
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
    func listFolders(parentID: String?, auth: OneDriveAuth) async -> [CloudFolder] {
        guard let token = await auth.validAccessToken() else { return [] }
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

    private func group(_ files: [CloudFileInfo]) -> [CloudDupGroup] {
        var byHash: [String: [CloudFileInfo]] = [:]
        for f in files where !f.hash.isEmpty { byHash[f.hash, default: []].append(f) }
        return byHash.compactMap { (hash, fs) in
            fs.count > 1 ? CloudDupGroup(hash: hash, files: fs.sorted { $0.fullPath < $1.fullPath }) : nil
        }
        .sorted { $0.reclaimable(excluding: []) > $1.reclaimable(excluding: []) }
    }

    // MARK: Preview (download with progress to a temp file, then Quick Look)

    @Published var previewingID: String? = nil
    @Published var previewProgress: Double = 0   // 0…1
    private var downloader: CloudDownloader?

    func preview(_ file: CloudFileInfo, auth: OneDriveAuth) {
        previewingID = file.id
        previewProgress = 0
        status = "Downloading \(file.name)…"
        Task {
            guard let token = await auth.validAccessToken(),
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

    func deleteDuplicates(in group: CloudDupGroup, auth: OneDriveAuth) {
        let live = group.files.filter { !deletedIDs.contains($0.id) }
        guard live.count > 1 else { return }
        let keep = live[0]
        let targets = Array(live.dropFirst())
        delete(targets, keep: keep, auth: auth)
    }

    // Delete a single cloud file (keeps at least one copy in the group).
    func deleteFile(_ file: CloudFileInfo, in group: CloudDupGroup, auth: OneDriveAuth) {
        let live = group.files.filter { !deletedIDs.contains($0.id) }
        guard live.count > 1, live.contains(where: { $0.id == file.id }) else { return }
        let keep = live.first { $0.id != file.id }
        delete([file], keep: keep, auth: auth)
    }

    func deleteAll(auth: OneDriveAuth) {
        var keepBy: [String: CloudFileInfo] = [:]
        var targets: [CloudFileInfo] = []
        for g in groups {
            let live = g.files.filter { !deletedIDs.contains($0.id) }
            guard live.count > 1 else { continue }
            keepBy[g.hash] = live[0]
            targets.append(contentsOf: live.dropFirst())
        }
        guard !targets.isEmpty else { return }
        delete(targets, keep: nil, keepByHash: keepBy, auth: auth)
    }

    private func delete(_ targets: [CloudFileInfo], keep: CloudFileInfo?, keepByHash: [String: CloudFileInfo] = [:], auth: OneDriveAuth) {
        guard !targets.isEmpty else { return }
        isScanning = true
        status = "Deleting \(targets.count) file(s) from OneDrive…"
        Task {
            guard let token = await auth.validAccessToken() else {
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
