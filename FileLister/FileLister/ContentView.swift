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
    let isIgnored: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Text(file.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isDeleted ? .red : (isIgnored ? .secondary.opacity(0.5) : (selectedFile?.id == file.id ? .white : .secondary)))
                .strikethrough(isDeleted)
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(selectedFile?.id == file.id ? Color.blue : (isIgnored ? Color.black.opacity(0.2) : Color.clear))
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
    @State private var showingSingleDeleteConfirm = false
    @State private var pendingDeletePath: String? = nil
    @State private var showingRegisterAlert = false
    
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
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Toggle(isOn: $scanner.useDeepAnalysis) {
                        Label("Deep Scan", systemImage: "cpu").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox).disabled(scanner.isScanning)
                    .help("Compares file content (byte-by-byte) instead of just name and size. Slower but 100% accurate.")
                    
                    Toggle(isOn: $scanner.filterMediaOnly) {
                        Label("Media", systemImage: "film").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox).disabled(scanner.isScanning)
                    .help("Only show images, videos, and audio files.")
                    
                    Toggle(isOn: $scanner.skipHiddenFiles) {
                        Label("No Hidden", systemImage: "eye.slash").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox).disabled(scanner.isScanning)
                    .help("Exclude hidden system files and .DS_Store from the scan.")

                    HStack(spacing: 4) {
                        Toggle("", isOn: $scanner.isLoggingEnabled)
                            .toggleStyle(.checkbox)
                            .disabled(scanner.isScanning || scanner.logFolderURL == nil)
                            .help("Enable or disable session logging.")
                        
                        Button(action: { selectLogFolder() }) {
                            Label("Log", systemImage: "doc.text").font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(scanner.logFolderURL == nil ? .secondary : .blue)
                        .help(scanner.logFolderURL == nil ? "Click to select a folder for scan logs" : "Logging to: \(scanner.logFolderURL!.path)")
                    }

                    TextField("Ext (e.g. xls)", text: $scanner.fileTypeFilter)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))
                        .frame(width: 70)
                        .help("Filter by file extension (e.g. 'jpg', 'pdf', 'xlsx'). Leave empty for all types.")
                        .disabled(scanner.isScanning)
                }
                Divider().frame(height: 20)
                HStack(spacing: 6) {
                    sortButton(label: "Copies", criteria: .count)
                        .help("Sort groups by the number of duplicates found.")
                    sortButton(label: "Size", criteria: .size)
                        .help("Sort groups by file size.")
                    
                    Divider().frame(height: 20).padding(.horizontal, 4)
                    
                    Menu {
                        ForEach(AutoSelectRule.allCases) { rule in
                            Button(rule.rawValue) {
                                scanner.autoSelectRule = rule
                                scanner.applyAutoSelection()
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(scanner.autoSelectRule.rawValue)
                                .font(.system(size: 10))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 140)
                    .help("Automatic selection rule: Decide which file to keep in each duplicate group.")
                }
                
                Spacer()
                
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
                            Text("Clean All Duplicates (\(scanner.totalDuplicatesCount))")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.red.opacity(0.1)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(scanner.duplicateGroups.isEmpty || scanner.isScanning)
                    .help("Move all marked duplicates to the Trash immediately.")
                }
            }
            .padding(.bottom, 10).padding(.horizontal).frame(maxWidth: .infinity, alignment: .leading)


            if scanner.isScanning {
                VStack(spacing: 4) {
                    ProgressView(value: scanner.progress, total: 1.0)
                        .accentColor(.green).progressViewStyle(.linear).padding(.horizontal)
                    
                    if scanner.fileProgress > 0 && scanner.fileProgress < 1 {
                        ProgressView(value: scanner.fileProgress, total: 1.0)
                            .accentColor(.blue).progressViewStyle(.linear).padding(.horizontal)
                            .scaleEffect(x: 1, y: 0.5, anchor: .center)
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, 10)
            }

            // Duplicates List
            if !scanner.duplicateGroups.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Duplicate Groups found (\(scanner.duplicateGroups.count)):").font(.caption).fontWeight(.bold)
                        Spacer()
                        Text("Space to Preview").font(.system(size: 8, weight: .bold)).foregroundColor(.blue)
                        Text("Safety Lock Active").font(.system(size: 9, weight: .bold)).foregroundColor(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1)).cornerRadius(4)
                    }
                    .padding(.horizontal).padding(.vertical, 8).foregroundColor(.secondary)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(scanner.duplicateGroups) { group in
                                let remainingCount = group.files.filter { !scanner.deletedPaths.contains($0.fullPath) && !scanner.ignoredPaths.contains($0.fullPath) }.count
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        FileIconView(path: group.files.first?.fullPath ?? "", size: 14)
                                        Text(group.name).fontWeight(.bold).font(.system(size: 12))
                                        Text("(\(group.size))").font(.caption2).foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(remainingCount) copies").font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(remainingCount > 1 ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                                            .foregroundColor(remainingCount > 1 ? .blue : .green).cornerRadius(3)
                                    }
                                    ForEach(group.files) { file in
                                        let fullPath = file.fullPath
                                        let isDeleted = scanner.deletedPaths.contains(fullPath)
                                        let isIgnored = scanner.ignoredPaths.contains(fullPath)
                                        HStack(spacing: 8) {
                                            HStack(spacing: 2) {
                                                Toggle("", isOn: Binding(
                                                    get: { isIgnored },
                                                    set: { value in
                                                        if value { scanner.ignoredPaths.insert(fullPath) }
                                                        else { scanner.ignoredPaths.remove(fullPath) }
                                                    }
                                                ))
                                                .toggleStyle(.checkbox)
                                                .labelsHidden()
                                                .disabled(isDeleted)
                                                
                                                Text("Ignore").font(.system(size: 7)).foregroundColor(.secondary)
                                            }
                                            .padding(.trailing, 2)

                                            SelectionButton(file: file, selectedFile: $selectedFile, isDeleted: isDeleted, isIgnored: isIgnored)
                                            
                                            if !isDeleted {
                                                Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: file.path)) }) {
                                                    Image(systemName: "folder")
                                                        .font(.system(size: 9)).foregroundColor(.gray)
                                                }
                                                .buttonStyle(.plain).help("Open folder in Finder")

                                                Button(action: { 
                                                    if remainingCount > 1 { 
                                                        if licenseManager.canPerformFreeDeletion() {
                                                            pendingDeletePath = fullPath
                                                            showingSingleDeleteConfirm = true
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
                        VStack(spacing: 12) {
                            Image(systemName: scanner.duplicateGroups.isEmpty && !scanner.status.contains("Ready") ? "checkmark.circle" : "folder.badge.plus")
                                .font(.system(size: 80)).foregroundColor(.gray.opacity(0.2))
                            Text(scanner.duplicateGroups.isEmpty && !scanner.status.contains("Ready") ? "No duplicates found" : "Select a folder to begin")
                                .font(.system(size: 18, weight: .medium)).foregroundColor(.secondary.opacity(0.6))
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
                Text(scanner.status + (scanner.fileProgress > 0 && scanner.fileProgress < 1 ? " (\(Int(scanner.fileProgress * 100))%)" : ""))
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
        .frame(minWidth: 1020, minHeight: 520)
        .alert("Confirm Batch Deletion?", isPresented: $showingBatchDeleteConfirm) {
            Button("Clean All", role: .destructive) {
                scanner.recycleAllDuplicates()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("⚠️ This action moves \(scanner.totalDuplicatesCount) duplicate files to the Trash, recovering approximately \(scanner.formattedCurrentSavings) of space.\n\nThis change is irreversible. Original files (one per group) will be kept safe.")
        }
        .alert("Confirm Deletion?", isPresented: $showingSingleDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let path = pendingDeletePath {
                    scanner.recycleFile(atPath: path)
                    licenseManager.recordDeletion()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let path = pendingDeletePath {
                Text("Are you sure you want to move this file to the Trash?\n\n\(path)")
            }
        }
        .alert("Register the application to use this feature", isPresented: $showingRegisterAlert) {
            Button("Register here") {
                if let url = URL(string: "https://www.google.com") {
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
    
    private func selectLogFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select where to save the scan logs"
        
        if panel.runModal() == .OK {
            scanner.logFolderURL = panel.url
            scanner.isLoggingEnabled = true
        }
    }
}
