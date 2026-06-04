import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import Quartz
import QuickLookUI

// Auxiliary class to handle the macOS System Quick Look Panel
class QuickLookManager: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookManager()
    var currentURL: URL?
    
    func showPreview(url: URL) {
        self.currentURL = url
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.reloadData()
        } else {
            panel.updateController()
            panel.delegate = self
            panel.dataSource = self
            panel.makeKeyAndOrderFront(nil)
        }
    }
    
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return currentURL != nil ? 1 : 0
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return currentURL as QLPreviewItem?
    }
}

struct FileIconView: View {
    let path: String
    let size: CGFloat
    
    var body: some View {
        // NSWorkspace icon(forFile:) is very efficient as it uses internal caching
        let nsImage = NSWorkspace.shared.icon(forFile: path)
        Image(nsImage: nsImage)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}


struct SelectionButton: View {
    let file: DuplicateFileInfo
    @Binding var selectedFile: DuplicateFileInfo?
    let isDeleted: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Text(file.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isDeleted ? .red : (selectedFile?.id == file.id ? .white : .secondary))
                .strikethrough(isDeleted)
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(selectedFile?.id == file.id ? Color.blue : Color.clear)
        .cornerRadius(3)
        .contentShape(Rectangle()) // Clickable area expansion
        .onTapGesture {
            if !isDeleted {
                selectedFile = file
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var scanner = FileScanner()
    @EnvironmentObject var licenseManager: LicenseManager
    @State private var sourceURL: URL?
    
    // Selection state for Quick Look
    @State private var selectedFile: DuplicateFileInfo? = nil
    @State private var showingBatchDeleteConfirm = false
    @State private var showingRegisterAlert = false
    @State private var folderGroupToMerge: FolderDuplicateGroup? = nil
    @State private var showingMergeAllSheet = false
    @State private var selectedFolderGroupID: UUID? = nil
    @State private var previewFolderGroup: FolderDuplicateGroup? = nil
    
    var hasRemovableDuplicates: Bool {
        for group in scanner.duplicateGroups {
            let activeCount = group.files.filter { !scanner.deletedPaths.contains($0.fullPath) }.count
            if activeCount > 1 { return true }
        }
        return false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack(spacing: 12) {
                Button(action: { startScanning() }) {
                    HStack {
                        Image(systemName: scanner.isScanning ? "stop.circle.fill" : "magnifyingglass.circle.fill")
                        Text(scanner.isScanning ? "Stop" : "Search for Duplicates")
                    }
                    .fontWeight(.semibold)
                    .frame(width: 180, height: 32)
                    .background(sourceURL == nil || scanner.isScanning ? Color.gray.opacity(0.3) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .disabled(sourceURL == nil || scanner.isScanning)
                .buttonStyle(.plain)

                HStack {
                    Text(sourceURL?.path ?? "No Folder Selected")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Select...") { selectSource() }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.horizontal, 10).frame(height: 32)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
            }
            .padding().background(Color(NSColor.windowBackgroundColor))
            
            // Analysis Options + Sorting
            HStack(spacing: 20) {
                HStack(spacing: 15) {
                    Toggle(isOn: $scanner.useDeepAnalysis) {
                        Label("Deep Scan", systemImage: "checkmark.shield").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox).disabled(scanner.isScanning)
                    Toggle(isOn: $scanner.filterMediaOnly) {
                        Label("Media", systemImage: "photo.on.rectangle").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox).disabled(scanner.isScanning)
                    Toggle(isOn: $scanner.skipHiddenFiles) {
                        Label("No Hidden", systemImage: "eye.slash").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox).disabled(scanner.isScanning)
                    Toggle(isOn: $scanner.detectSymlinks) {
                        Label("Symlinks", systemImage: "link").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox).disabled(scanner.isScanning)
                    Toggle(isOn: $scanner.detectFolderDuplicates) {
                        Label("Folders", systemImage: "folder.badge.questionmark").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox).disabled(scanner.isScanning)
                    if scanner.detectFolderDuplicates {
                        HStack(spacing: 4) {
                            Text("Match:").font(.system(size: 10)).foregroundColor(.secondary)
                            Slider(value: $scanner.folderMatchThreshold, in: 0.5...1.0, step: 0.05)
                                .frame(width: 80)
                                .disabled(scanner.isScanning)
                            Text("\(Int(scanner.folderMatchThreshold * 100))%").font(.system(size: 10, weight: .medium)).frame(width: 28)
                        }
                    }
                }
                Divider().frame(height: 20)
                HStack(spacing: 8) {
                    sortButton(label: "Copies", criteria: .count)
                    sortButton(label: "Size", criteria: .size)
                    sortButton(label: "Match Ratio", criteria: .matchRatio)
                }
                
                Spacer()
                
                if !scanner.folderDuplicateGroups.isEmpty && !scanner.isScanning {
                    Button(action: { showingMergeAllSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.merge")
                            Text("Merge All Folders")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.indigo)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.indigo.opacity(0.1)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                if hasRemovableDuplicates && !scanner.isScanning {
                    Button(action: {
                        if licenseManager.isRegistered {
                            showingBatchDeleteConfirm = true
                        } else {
                            showingRegisterAlert = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                            Text("Clean All Duplicates")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.red.opacity(0.1)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 10).padding(.horizontal).frame(maxWidth: .infinity, alignment: .leading)


            if scanner.isScanning {
                let overallProgress = (Double(scanner.scanPhaseIndex) + scanner.progress) / Double(max(1, scanner.totalScanPhases))
                VStack(spacing: 6) {
                    ProgressView(value: scanner.progress, total: 1.0)
                        .accentColor(.green).progressViewStyle(.linear).padding(.horizontal)

                    Text("\(Int(overallProgress * 100))%")
                        .font(.system(size: 120, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .animation(.none, value: overallProgress)

                }
                .padding(.bottom, 10)
            }

            // Duplicates List
            if !scanner.duplicateGroups.isEmpty || !scanner.folderDuplicateGroups.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Duplicate Groups found (\(scanner.duplicateGroups.count + scanner.folderDuplicateGroups.count)):").font(.caption).fontWeight(.bold)
                        Spacer()
                        Text("Space to Preview").font(.system(size: 8, weight: .bold)).foregroundColor(.blue)
                        Text("Safety Lock Active").font(.system(size: 9, weight: .bold)).foregroundColor(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1)).cornerRadius(4)
                    }
                    .padding(.horizontal).padding(.vertical, 8).foregroundColor(.secondary)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(scanner.detectFolderDuplicates ? scanner.folderDuplicateGroups : []) { folderGroup in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder.badge.questionmark")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.indigo)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(URL(fileURLWithPath: folderGroup.folderA).lastPathComponent)
                                                .fontWeight(.bold).font(.system(size: 12))
                                            Text(folderGroup.folderA)
                                                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Image(systemName: "arrow.left.arrow.right")
                                            .font(.system(size: 9)).foregroundColor(.secondary)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(URL(fileURLWithPath: folderGroup.folderB).lastPathComponent)
                                                .fontWeight(.bold).font(.system(size: 12))
                                            Text(folderGroup.folderB)
                                                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer()
                                        Text("\(Int(folderGroup.matchRatio * 100))% match")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.indigo)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Color.indigo.opacity(0.1)).cornerRadius(3)
                                            .help(folderGroup.tooltipText)
                                    }
                                    HStack(spacing: 12) {
                                        Text("\(folderGroup.matchedGroups.count) shared files")
                                            .font(.system(size: 9)).foregroundColor(.secondary)
                                        if !folderGroup.uniqueToB.isEmpty {
                                            Text("\(folderGroup.uniqueToB.count) unique to merge")
                                                .font(.system(size: 9)).foregroundColor(.secondary)
                                        }
                                        Text(scanner.formatBytes(Int64(folderGroup.totalSizeBytes)))
                                            .font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                                        Spacer()
                                        Button(action: { folderGroupToMerge = folderGroup }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.triangle.merge")
                                                Text("Merge & Clean")
                                            }
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.indigo)
                                            .padding(.horizontal, 10).padding(.vertical, 4)
                                            .background(Color.indigo.opacity(0.1)).cornerRadius(5)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(scanner.isScanning)
                                    }
                                    .padding(.leading, 4)
                                }
                                .padding(6)
                                .background(selectedFolderGroupID == folderGroup.id ? Color.indigo.opacity(0.18) : Color.indigo.opacity(0.06))
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(selectedFolderGroupID == folderGroup.id ? Color.indigo.opacity(0.6) : Color.clear, lineWidth: 1.5)
                                )
                                .onTapGesture { selectedFolderGroupID = folderGroup.id; selectedFile = nil }
                            }

                            ForEach(scanner.detectFolderDuplicates ? [] : scanner.duplicateGroups) { group in
                                let remainingCount = group.files.filter { !scanner.deletedPaths.contains($0.fullPath) }.count
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        if group.isSymlinkGroup {
                                            Image(systemName: "link")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.purple)
                                                .frame(width: 14, height: 14)
                                        } else {
                                            FileIconView(path: group.files.first?.fullPath ?? "", size: 14)
                                        }
                                        Text(group.name).fontWeight(.bold).font(.system(size: 12))
                                        if group.isSymlinkGroup {
                                            Text("symlink").font(.system(size: 8, weight: .medium))
                                                .foregroundColor(.purple)
                                                .padding(.horizontal, 4).padding(.vertical, 1)
                                                .background(Color.purple.opacity(0.1)).cornerRadius(3)
                                        }
                                        Text("(\(group.size))").font(.caption2).foregroundColor(.secondary)
                                        Spacer()
                                        if let c = group.confidence {
                                            let pct = Int(c.overall * 100)
                                            let color: Color = c.overall >= 0.75 ? .orange : (c.overall >= 0.5 ? .yellow : .gray)
                                            Text("\(pct)% match")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(color)
                                                .padding(.horizontal, 4).padding(.vertical, 1)
                                                .background(color.opacity(0.12)).cornerRadius(3)
                                                .help(c.tooltipText)
                                        }
                                        Text("\(remainingCount) copies").font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(remainingCount > 1 ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                                            .foregroundColor(remainingCount > 1 ? .blue : .green).cornerRadius(3)
                                    }
                                    ForEach(group.files) { file in
                                        let fullPath = file.fullPath
                                        let isDeleted = scanner.deletedPaths.contains(fullPath)
                                        HStack(spacing: 8) {
                                            SelectionButton(file: file, selectedFile: $selectedFile, isDeleted: isDeleted)
                                            
                                            if !isDeleted {
                                                Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: file.path)) }) {
                                                    Image(systemName: "folder")
                                                        .font(.system(size: 9)).foregroundColor(.gray)
                                                }
                                                .buttonStyle(.plain).help("Open folder in Finder")

                                                Button(action: { 
                                                    if remainingCount > 1 { 
                                                        if licenseManager.canPerformFreeDeletion() {
                                                            scanner.recycleFile(atPath: fullPath)
                                                            // Note: In a real app, we'd only count successful deletions. 
                                                            // For simplicity here, we record the attempt.
                                                            licenseManager.recordDeletion()
                                                        } else {
                                                            showingRegisterAlert = true
                                                        }
                                                    } 
                                                }) {
                                                    Image(systemName: remainingCount > 1 ? "trash" : "lock.fill")
                                                        .font(.system(size: 9)).foregroundColor(remainingCount > 1 ? .gray : .green.opacity(0.5))
                                                }
                                                .buttonStyle(.plain).disabled(remainingCount <= 1)
                                            } else {
                                                Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundColor(.red)
                                            }
                                        }
                                        .padding(.leading, 12)
                                    }
                                }
                                .padding(6).background(remainingCount > 1 ? Color.orange.opacity(0.08) : Color.green.opacity(0.05)).cornerRadius(4)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            } else {
                Spacer()
                if !scanner.isScanning && (scanner.status == "Ready to start" || scanner.duplicateGroups.isEmpty) {
                    Button(action: { selectSource() }) {
                        VStack {
                            Image(systemName: scanner.duplicateGroups.isEmpty && !scanner.status.contains("Ready") ? "checkmark.circle" : "folder.badge.plus")
                                .font(.system(size: 40)).foregroundColor(.gray.opacity(0.2))
                            Text(scanner.duplicateGroups.isEmpty && !scanner.status.contains("Ready") ? "No duplicates found" : "Select a folder to begin")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            
            // Hidden Button for Keyboard Shortcut (Space)
            Button("") {
                if let file = selectedFile {
                    QuickLookManager.shared.showPreview(url: URL(fileURLWithPath: file.fullPath))
                } else if let id = selectedFolderGroupID,
                          let fg = scanner.folderDuplicateGroups.first(where: { $0.id == id }) {
                    previewFolderGroup = fg
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)

            // Status Bar
            HStack {
                Circle().fill(
                    scanner.status.contains("Error") ? Color.red :
                    (scanner.isScanning ? Color.green : (scanner.status.contains("Completed") || scanner.status.contains("Trash") ? Color.blue : Color.gray))
                )
                    .frame(width: 7, height: 7)
                Text(scanner.status)
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                
                if scanner.totalPotentialSavings > 0 || scanner.totalRecovered > 0 {
                    HStack(spacing: 12) {
                        HStack(spacing: 3) {
                            Image(systemName: "externaldrive.fill").font(.system(size: 8))
                            Text("Potential Savings:").fontWeight(.bold)
                            Text(scanner.formatBytes(scanner.totalPotentialSavings))
                        }
                        
                        Divider().frame(height: 10).padding(.horizontal, 4)
                        
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles").font(.system(size: 8))
                            Text("Recoveries:").fontWeight(.bold)
                            Text(scanner.formatBytes(scanner.totalRecovered))
                                .foregroundColor(.green)
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.trailing, 10)
                }

                if scanner.progress > 0 && scanner.progress < 1 {
                    Text("\(Int(scanner.progress * 100))%").font(.system(size: 9, weight: .bold)).foregroundColor(.green)
                }

                if !licenseManager.isRegistered {
                    Divider().frame(height: 10).padding(.horizontal, 4)
                    HStack(spacing: 3) {
                        Image(systemName: "timer").font(.system(size: 8))
                        Text("Trial Mode:").fontWeight(.bold)
                        Text("\(licenseManager.trialDeletions)/15 used")
                        
                        Button("(Register App)") {
                            NotificationCenter.default.post(name: NSNotification.Name("toggleLicenseSheet"), object: nil)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                        .padding(.leading, 5)
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .padding(.trailing, 5)
                }
            }
            .padding(.horizontal, 10).frame(height: 24).background(Color.gray.opacity(0.05)).overlay(Divider(), alignment: .top)
        }
        .frame(minWidth: 700, minHeight: 520)
        .alert("Confirm Batch Deletion?", isPresented: $showingBatchDeleteConfirm) {
            Button("Clean All", role: .destructive) {
                scanner.recycleAllDuplicates()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("⚠️ This action moves ALL detected duplicates to the Trash. This change is irreversible.\n\nNote: Original files (one per group) will be kept safe.")
        }
        .sheet(item: $previewFolderGroup) { fg in
            FolderDiffPreviewSheet(
                folderGroup: fg,
                scanner: scanner,
                onMerge: {
                    folderGroupToMerge = fg
                    previewFolderGroup = nil
                },
                onClose: { previewFolderGroup = nil }
            )
        }
        .sheet(isPresented: $showingMergeAllSheet) {
            MergeAllConfirmationSheet(
                scanner: scanner,
                onMergeAll: {
                    scanner.mergeAllFolders()
                    showingMergeAllSheet = false
                },
                onCancel: { showingMergeAllSheet = false }
            )
        }
        .sheet(item: $folderGroupToMerge) { fg in
            MergeConfirmationSheet(
                folderGroup: fg,
                scanner: scanner,
                onMerge: {
                    scanner.mergeFolder(fg)
                    folderGroupToMerge = nil
                },
                onCancel: { folderGroupToMerge = nil }
            )
        }
        .alert("Register the application to use this feature", isPresented: $showingRegisterAlert) {
            Button("Register here") {
                if let url = URL(string: "https://www.luisdanielsilva.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("You have reached the trial limit or are attempting a premium action. Please register to unlock unlimited access.")
        }
    }
    
    private func sortButton(label: String, criteria: SortCriteria) -> some View {
        Button(action: { scanner.toggleSort(criteria: criteria) }) {
            HStack(spacing: 4) {
                Text(label)
                if scanner.sortCriteria == criteria {
                    Image(systemName: scanner.sortOrder == .ascending ? "chevron.up" : "chevron.down").font(.system(size: 8))
                }
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(scanner.sortCriteria == criteria ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
            .foregroundColor(scanner.sortCriteria == criteria ? .blue : .primary).cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private func selectSource() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK {
            self.sourceURL = panel.url
            startScanning()
        }
    }
    
    private func startScanning() {
        guard let source = sourceURL else { return }
        scanner.startScan(sourceURL: source)
    }
}

// MARK: - Folder Diff Preview

struct DiffRow: Identifiable {
    enum Kind {
        case matched(fileA: DuplicateFileInfo, fileB: DuplicateFileInfo)
        case uniqueToA(DuplicateFileInfo)
        case uniqueToB(DuplicateFileInfo, wouldDuplicate: Bool)
    }
    let id = UUID()
    let kind: Kind
}

struct FolderDiffPreviewSheet: View {
    let folderGroup: FolderDuplicateGroup
    @ObservedObject var scanner: FileScanner
    let onMerge: () -> Void
    let onClose: () -> Void

    private var nameA: String { URL(fileURLWithPath: folderGroup.folderA).lastPathComponent }
    private var nameB: String { URL(fileURLWithPath: folderGroup.folderB).lastPathComponent }

    // name+size keys of all files already in folderA (matched + uniqueToA)
    private var filesInAKeys: Set<String> {
        var keys = Set<String>()
        for group in folderGroup.matchedGroups {
            if let fA = group.files.first(where: { $0.path == folderGroup.folderA }) {
                keys.insert("\(fA.name)_\(fA.sizeBytes)")
            }
        }
        for f in folderGroup.uniqueToA { keys.insert("\(f.name)_\(f.sizeBytes)") }
        return keys
    }

    private var diffRows: [DiffRow] {
        let aKeys = filesInAKeys
        var rows: [DiffRow] = []
        for group in folderGroup.matchedGroups.sorted(by: { $0.name < $1.name }) {
            if let fA = group.files.first(where: { $0.path == folderGroup.folderA }),
               let fB = group.files.first(where: { $0.path == folderGroup.folderB }) {
                rows.append(DiffRow(kind: .matched(fileA: fA, fileB: fB)))
            }
        }
        for file in folderGroup.uniqueToA.sorted(by: { $0.name < $1.name }) {
            rows.append(DiffRow(kind: .uniqueToA(file)))
        }
        for file in folderGroup.uniqueToB.sorted(by: { $0.name < $1.name }) {
            let wouldDuplicate = aKeys.contains("\(file.name)_\(file.sizeBytes)")
            rows.append(DiffRow(kind: .uniqueToB(file, wouldDuplicate: wouldDuplicate)))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {

            // Header
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(nameA).fontWeight(.bold).font(.system(size: 13))
                        Text("KEEP").font(.system(size: 9, weight: .bold)).foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.green.opacity(0.08))

                Text("Operations")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 110)
                    .padding(12)
                    .background(Color.gray.opacity(0.06))

                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(nameB).fontWeight(.bold).font(.system(size: 13))
                        Text("MERGE & CLEAN").font(.system(size: 9, weight: .bold)).foregroundColor(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.red.opacity(0.06))
            }

            Divider()

            // Legend
            HStack(spacing: 16) {
                legendItem(color: .orange, label: "Duplicate (kept in A)")
                legendItem(color: .red, label: "Duplicate (deleted from B)")
                legendItem(color: .blue, label: "Unique (moved to A)")
                legendItem(color: .secondary, label: "Unique (no change)")
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.gray.opacity(0.04))

            Divider()

            // Diff rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(diffRows) { row in
                        diffRowView(row)
                        Divider().opacity(0.4)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(folderGroup.matchedGroups.count) duplicate · \(folderGroup.uniqueToB.count) to move · \(folderGroup.uniqueToA.count) unchanged")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                Button("Close", action: onClose).buttonStyle(.bordered)
                Button(action: onMerge) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge & Clean")
                    }
                    .fontWeight(.semibold).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.indigo).cornerRadius(7)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
        .frame(width: 820, height: 560)
    }

    @ViewBuilder
    private func diffRowView(_ row: DiffRow) -> some View {
        HStack(spacing: 0) {
            switch row.kind {
            case .matched(let fA, let fB):
                fileCell(name: fA.name, size: fA.size, color: .orange, icon: "doc.fill", side: .leading)
                operationCell(icon: "xmark.circle.fill", label: "DELETE", color: .red)
                fileCell(name: fB.name, size: fB.size, color: .red, icon: "doc.fill", side: .leading, strikethrough: true)

            case .uniqueToA(let f):
                fileCell(name: f.name, size: f.size, color: .secondary, icon: "doc.fill", side: .leading)
                operationCell(icon: "minus", label: "NO CHANGE", color: .secondary)
                emptyCell()

            case .uniqueToB(let f, let wouldDuplicate):
                if wouldDuplicate {
                    emptyCell()
                    operationCell(icon: "xmark.circle.fill", label: "DELETE", color: .red)
                    fileCell(name: f.name, size: f.size, color: .red, icon: "doc.fill", side: .leading, strikethrough: true)
                } else {
                    emptyCell()
                    operationCell(icon: "arrow.left.circle.fill", label: "MOVE", color: .blue)
                    fileCell(name: f.name, size: f.size, color: .blue, icon: "doc.fill", side: .leading)
                }
            }
        }
        .frame(height: 48)
    }

    private func fileCell(name: String, size: String, color: Color, icon: String, side: Alignment, strikethrough: Bool = false) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10)).foregroundColor(color)
                Text(name)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                    .strikethrough(strikethrough, color: color)
                    .lineLimit(1).truncationMode(.middle)
            }
            Text(size).font(.system(size: 9)).foregroundColor(color.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func operationCell(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
            Text(label).font(.system(size: 7, weight: .bold)).foregroundColor(color)
        }
        .frame(minWidth: 110, maxWidth: 110, minHeight: 0, maxHeight: .infinity)
        .background(Color.gray.opacity(0.08))
    }

    private func emptyCell() -> some View {
        Rectangle().fill(Color.clear).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
        }
    }
}

struct MergeAllConfirmationSheet: View {
    @ObservedObject var scanner: FileScanner
    let onMergeAll: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.merge").font(.title2).foregroundColor(.indigo)
                Text("Merge All Folder Pairs").font(.title2).fontWeight(.bold)
                Spacer()
                Text("\(scanner.folderDuplicateGroups.count) pairs")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.1)).cornerRadius(4)
            }

            Divider()

            // Naming controls (shared across all pairs)
            VStack(alignment: .leading, spacing: 10) {
                Text("Naming rule (applied to all pairs)").font(.system(size: 12, weight: .semibold))

                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(
                            get: { scanner.mergeNamePosition == .prefix },
                            set: { scanner.mergeNamePosition = $0 ? .prefix : .suffix }
                        ))
                        .toggleStyle(.checkbox).labelsHidden()
                        Text("Prefix").font(.system(size: 12))
                    }
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(
                            get: { scanner.mergeNamePosition == .suffix },
                            set: { scanner.mergeNamePosition = $0 ? .suffix : .prefix }
                        ))
                        .toggleStyle(.checkbox).labelsHidden()
                        Text("Suffix").font(.system(size: 12))
                    }
                    HStack(spacing: 6) {
                        Text("Content:").font(.system(size: 12)).foregroundColor(.secondary)
                        TextField("e.g. merged", text: $scanner.mergeNameContent)
                            .textFieldStyle(.roundedBorder).frame(width: 100).font(.system(size: 12))
                    }
                    HStack(spacing: 6) {
                        Text("Separator:").font(.system(size: 12)).foregroundColor(.secondary)
                        TextField("", text: $scanner.mergeNameSeparator)
                            .textFieldStyle(.roundedBorder).frame(width: 50).font(.system(size: 12))
                    }
                }
            }

            Divider()

            // Folder pairs list with preview names
            Text("Pairs to merge").font(.system(size: 12, weight: .semibold))

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(scanner.folderDuplicateGroups) { fg in
                        let preview = scanner.computeMergedFolderName(folderA: fg.folderA, folderB: fg.folderB)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.fill").foregroundColor(.secondary).font(.system(size: 10))
                                    Text(URL(fileURLWithPath: fg.folderB).lastPathComponent)
                                        .font(.system(size: 11))
                                    Text("→").foregroundColor(.secondary).font(.system(size: 10))
                                    Image(systemName: "folder.fill").foregroundColor(.secondary).font(.system(size: 10))
                                    Text(URL(fileURLWithPath: fg.folderA).lastPathComponent)
                                        .font(.system(size: 11))
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.fill").foregroundColor(.green).font(.system(size: 10))
                                    Text(preview)
                                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
                                }
                            }
                            Spacer()
                            Text("\(Int(fg.matchRatio * 100))%")
                                .font(.system(size: 9, weight: .bold)).foregroundColor(.indigo)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.1)).cornerRadius(3)
                        }
                        .padding(8)
                        .background(Color.indigo.opacity(0.04))
                        .cornerRadius(6)
                    }
                }
            }
            .frame(maxHeight: 220)

            Divider()

            // Action buttons
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button(action: onMergeAll) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge All & Clean")
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.indigo)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}

struct MergeConfirmationSheet: View {
    let folderGroup: FolderDuplicateGroup
    @ObservedObject var scanner: FileScanner
    let onMerge: () -> Void
    let onCancel: () -> Void

    private var nameA: String { URL(fileURLWithPath: folderGroup.folderA).lastPathComponent }
    private var nameB: String { URL(fileURLWithPath: folderGroup.folderB).lastPathComponent }
    private var previewName: String { scanner.computeMergedFolderName(folderA: folderGroup.folderA, folderB: folderGroup.folderB) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.merge").font(.title2).foregroundColor(.indigo)
                Text("Merge & Clean Folders").font(.title2).fontWeight(.bold)
            }

            Divider()

            // Folder summary
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundColor(.indigo)
                    Text(nameB).fontWeight(.semibold)
                    Text("→").foregroundColor(.secondary)
                    Image(systemName: "folder.fill").foregroundColor(.green)
                    Text(nameA).fontWeight(.semibold)
                }
                .font(.system(size: 13))

                VStack(alignment: .leading, spacing: 3) {
                    Label("\(folderGroup.matchedGroups.count) duplicate files moved to Trash", systemImage: "trash")
                    Label("\(folderGroup.uniqueToB.count) unique files moved into \(nameA)", systemImage: "arrow.right.doc.on.clipboard")
                    Label("\"\(nameB)\" deleted after merge", systemImage: "folder.badge.minus")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }

            Divider()

            // Naming controls
            VStack(alignment: .leading, spacing: 10) {
                Text("Merged folder name").font(.system(size: 12, weight: .semibold))

                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(
                            get: { scanner.mergeNamePosition == .prefix },
                            set: { scanner.mergeNamePosition = $0 ? .prefix : .suffix }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        Text("Prefix").font(.system(size: 12))
                    }
                    HStack(spacing: 6) {
                        Toggle("", isOn: Binding(
                            get: { scanner.mergeNamePosition == .suffix },
                            set: { scanner.mergeNamePosition = $0 ? .suffix : .prefix }
                        ))
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        Text("Suffix").font(.system(size: 12))
                    }
                }

                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Content:").font(.system(size: 12)).foregroundColor(.secondary)
                        TextField("e.g. merged", text: $scanner.mergeNameContent)
                            .textFieldStyle(.roundedBorder).frame(width: 120).font(.system(size: 12))
                    }
                    HStack(spacing: 6) {
                        Text("Separator:").font(.system(size: 12)).foregroundColor(.secondary)
                        TextField("e.g. space or _", text: $scanner.mergeNameSeparator)
                            .textFieldStyle(.roundedBorder).frame(width: 60).font(.system(size: 12))
                    }
                }

                // Live preview
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundColor(.green)
                    Text(previewName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(8)
                .background(Color.green.opacity(0.08))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.2), lineWidth: 1))
            }

            Divider()

            // Action buttons
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Spacer()
                Button(action: onMerge) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.merge")
                        Text("Merge & Clean")
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.indigo)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
