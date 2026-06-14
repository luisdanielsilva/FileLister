import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import Quartz
import QuickLookUI

// Auxiliary class to handle the macOS System Quick Look Panel
class QuickLookManager: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookManager()
    var currentURL: URL?
    private var eventMonitor: Any?

    override init() {
        super.init()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 49,  // Space
                  let panel = QLPreviewPanel.shared(),
                  QLPreviewPanel.sharedPreviewPanelExists(),
                  panel.isVisible else { return event }
            panel.close()
            self?.currentURL = nil
            return nil  // consume the event
        }
    }

    deinit {
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) }
    }

    func togglePreview(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.close()
        } else {
            self.currentURL = url
            panel.updateController()
            panel.delegate = self
            panel.dataSource = self
            panel.makeKeyAndOrderFront(nil)
        }
    }

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

enum ScanSource: String, CaseIterable, Identifiable {
    case local = "Local"
    case remote = "Remote"
    var id: String { rawValue }
    var icon: String { self == .local ? "internaldrive" : "cloud" }
}

enum AppMode: String, CaseIterable, Identifiable {
    case files   = "Files"
    case folders = "Folders"
    case photos  = "Photos"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .files:   return "doc.on.doc"
        case .folders: return "folder.badge.questionmark"
        case .photos:  return "photo.on.rectangle.angled"
        }
    }
}

struct ContentView: View {
    // Separate engines so Files and Folders keep independent, persistent results.
    @StateObject private var fileScanner = FileScanner(detectFolderDuplicates: false)
    @StateObject private var folderScanner = FileScanner(detectFolderDuplicates: true)
    // The scanner for the current mode (Folders uses its own; everything else uses the file scanner).
    private var scanner: FileScanner { mode == .folders ? folderScanner : fileScanner }
    @StateObject private var photoEngine = PhotoEngine()
    // Saved remote connections (Phase 2 of #6). The store owns one provider per
    // connection; the engine is pointed at the active one on activation.
    @ObservedObject private var connectionStore = RemoteConnectionStore.shared
    @StateObject private var remoteEngine = RemoteEngine()
    @EnvironmentObject var licenseManager: LicenseManager
    @State private var showingConnectionPicker = false

    // Convenience accessors for the active connection's provider state.
    private var activeProvider: OneDriveProvider? { connectionStore.activeProvider }
    private var remoteConnected: Bool { activeProvider?.isConnected ?? false }
    @State private var mode: AppMode = .files
    @State private var source: ScanSource = .local
    @State private var selectedCloudFolders: [CloudFolder] = []
    @State private var showingCloudPicker = false

    // True when the engine for the active source/mode is scanning
    private var activeScanning: Bool {
        if source == .remote { return remoteEngine.isScanning }
        return mode == .photos ? photoEngine.isScanning : scanner.isScanning
    }
    // Folder selection is per-mode, so each mode's bar matches its own results.
    @State private var sourceFoldersByMode: [AppMode: [URL]] = [:]
    private var sourceFolders: [URL] {
        get { sourceFoldersByMode[mode] ?? [] }
        nonmutating set { sourceFoldersByMode[mode] = newValue }
    }
    @State private var collapsedRoots: Set<String> = []
    private let acrossKey = "__across_multiple__"
    
    // Selection state for Quick Look
    @State private var selectedFile: DuplicateFileInfo? = nil
    @State private var selectedPhotoID: UUID? = nil
    @State private var selectedCloudID: String? = nil
    @State private var filesSizeFilter = SizeFilter()
    @State private var showingBatchDeleteConfirm = false
    @State private var showingRegisterAlert = false
    @State private var folderGroupToMerge: FolderDuplicateGroup? = nil
    @State private var showingMergeAllSheet = false
    @State private var selectedFolderGroupID: UUID? = nil
    @State private var previewFolderGroup: FolderDuplicateGroup? = nil
    // Destination folder chosen when "Copy to new folder" is enabled
    @State private var safeMergeDestination: URL? = nil
    // One-by-one merge walkthrough — driven through the existing preview sheet
    @State private var walkthroughActive = false
    @State private var walkthroughQueue: [FolderDuplicateGroup] = []
    @State private var walkthroughIndex = 0
    @State private var approvedFolderIDs: Set<UUID> = []
    // OneDrive folder merge (mirror of the local flow above)
    @State private var previewCloudCluster: CloudFolderDupGroup? = nil
    @State private var showingCloudMergeAllSheet = false
    // OneDrive "Copy to new folder" — destination parent chosen when the toggle is enabled
    @State private var showingCloudDestPicker = false
    @State private var cloudSafeMergeDestination: CloudFolder? = nil
    // Non-nil only when safe merge is active with a destination — drives copy-mode confirmation sheets.
    private var cloudCopyDestinationName: String? {
        remoteEngine.safeMergeToNewFolder ? cloudSafeMergeDestination?.name : nil
    }
    @State private var cloudWalkthroughActive = false
    @State private var cloudWalkthroughQueue: [CloudFolderDupGroup] = []
    @State private var cloudWalkthroughIndex = 0
    @State private var approvedCloudIDs: Set<UUID> = []
    @State private var collapsedFolderGroupIDs: Set<UUID> = []
    @State private var searchedModes: Set<AppMode> = []  // modes that have run at least one search this session

    var hasRemovableDuplicates: Bool {
        for group in displayedFileGroups {
            let activeCount = group.files.filter { !scanner.deletedPaths.contains($0.fullPath) }.count
            if activeCount > 1 { return true }
        }
        return false
    }

    // Results shown for the CURRENT mode only. Files & Folders share the scanner,
    // so gate by which mode last ran it; results persist across mode switches and
    // change only on a new search.
    // Remote source segment: "OneDrive → <profile>" when a connection is active, else "Remote".
    var remoteSegmentLabel: String {
        guard let conn = connectionStore.activeConnection else { return ScanSource.remote.rawValue }
        return "\(conn.kind.displayName) → \(conn.displayName)"
    }

    var shownFileGroups: [DuplicateGroup] {
        (source == .local && mode == .files) ? fileScanner.duplicateGroups : []
    }
    var shownFolderGroups: [FolderDuplicateGroup] {
        (source == .local && mode == .folders) ? folderScanner.folderDuplicateGroups : []
    }
    // Files results after the session-only size filter. Used for display, sections,
    // and bulk clean so the filter scopes everything consistently.
    var displayedFileGroups: [DuplicateGroup] {
        filesSizeFilter.isActive ? shownFileGroups.filter { filesSizeFilter.contains($0.sizeBytes) } : shownFileGroups
    }

    // Show the scanner savings/recoveries only in the local mode that produced them.
    var showScannerStats: Bool {
        source == .local && (mode == .files || mode == .folders) && searchedModes.contains(mode) &&
        (scanner.totalPotentialSavings > 0 || scanner.totalRecovered > 0)
    }

    // True when the Actions row has anything to show (merge controls or Clean All).
    var hasActionControls: Bool {
        let localMerge = !shownFolderGroups.isEmpty && !scanner.isScanning
        let cloudMerge = source == .remote && mode == .folders && !remoteEngine.folderGroups.isEmpty && !remoteEngine.isScanning
        let cleanAll = hasRemovableDuplicates && !scanner.isScanning
        // Keep the row visible for the size filter whenever Files results exist,
        // even if the current filter hides every removable group.
        let filesFilterable = source == .local && mode == .files && !shownFileGroups.isEmpty && !scanner.isScanning
        return localMerge || cloudMerge || cleanAll || filesFilterable
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode switcher + source (Local / OneDrive)
            HStack(spacing: 12) {
                Picker("", selection: $mode) {
                    ForEach(AppMode.allCases) { m in
                        Label(m.rawValue, systemImage: m.icon).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .disabled(scanner.isScanning)
                .onChange(of: mode) { _ in
                    // Each mode has its own engine, so results persist across switches
                    // and change only on a new search. Just clear the visual selection.
                    selectedFolderGroupID = nil
                    selectedFile = nil
                }

                Picker("", selection: $source) {
                    Label(ScanSource.local.rawValue, systemImage: ScanSource.local.icon).tag(ScanSource.local)
                    // Remote segment reflects the active connection's provider + name.
                    Label(remoteSegmentLabel,
                          systemImage: connectionStore.activeConnection?.kind.icon ?? ScanSource.remote.icon)
                        .tag(ScanSource.remote)
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .frame(width: 260)
                .disabled(activeScanning)
                .help("Scan local folders or a remote connection (⌥-click Remote to pick a connection).")
                .onChange(of: source) { s in
                    guard s == .remote else { return }
                    let optionHeld = NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
                    if optionHeld { showingConnectionPicker = true }
                    else if connectionStore.activeConnection != nil { /* keep current session */ }
                    else if let def = connectionStore.defaultConnection { activateConnection(def) }
                    else { showingConnectionPicker = true }
                }
            }
            .padding(.horizontal).padding(.top, 10)

            // Top Bar
            HStack(spacing: 12) {
                let searchDisabled = source == .remote ? (!remoteConnected || (selectedCloudFolders.isEmpty && !remoteEngine.isScanning)) : (sourceFolders.isEmpty && !activeScanning)
                Button(action: { startScanning() }) {
                    HStack {
                        Image(systemName: activeScanning ? "stop.circle.fill" : "magnifyingglass.circle.fill")
                        Text(activeScanning ? "Stop" : "Search for Duplicates")
                    }
                    .fontWeight(.semibold)
                    .frame(width: 180, height: 32)
                    .background(searchDisabled ? Color.gray.opacity(0.3) : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .disabled(searchDisabled)
                .buttonStyle(.plain)

                if source == .local {
                    // Selected folders list + add button
                    HStack(spacing: 8) {
                        if sourceFolders.isEmpty {
                            Text("No Folders Selected")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11, design: .monospaced))
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(sourceFolders, id: \.self) { folder in
                                        HStack(spacing: 4) {
                                            Image(systemName: "folder.fill").font(.system(size: 9)).foregroundColor(.blue.opacity(0.7))
                                            Text(folder.lastPathComponent)
                                                .font(.system(size: 10))
                                                .lineLimit(1)
                                                .help(folder.path)
                                            Button(action: { sourceFolders.removeAll { $0 == folder } }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 9)).foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(scanner.isScanning)
                                        }
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color.blue.opacity(0.08)).cornerRadius(4)
                                    }
                                }
                            }
                        }
                        Spacer(minLength: 0)
                        Button("Add Folder...") { selectSource() }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(scanner.isScanning)
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))

                    // Scan scope — only relevant with 2+ folders
                    if sourceFolders.count >= 2 {
                        Picker("", selection: Binding(get: { scanner.scanScope }, set: { scanner.scanScope = $0 })) {
                            Text("Across all").tag(ScanScope.combined)
                            Text("Within each").tag(ScanScope.perFolder)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .disabled(scanner.isScanning)
                        .help("Across all: find duplicates pooled across every folder.\nWithin each: find duplicates only inside each folder separately.")
                    }
                } else {
                    // Remote connection / folder panel
                    HStack(spacing: 8) {
                        Image(systemName: remoteConnected ? "cloud.fill" : (connectionStore.activeConnection?.kind.icon ?? "cloud"))
                            .foregroundColor(remoteConnected ? .blue : .secondary)
                        if connectionStore.activeConnection == nil {
                            Text("No connection selected").font(.system(size: 11)).foregroundColor(.secondary)
                            Spacer(minLength: 0)
                            Button("Choose Connection…") { showingConnectionPicker = true }
                                .buttonStyle(.bordered).controlSize(.small)
                        } else if remoteConnected {
                            if selectedCloudFolders.isEmpty {
                                Text("\(connectionStore.activeConnection?.displayName ?? "") · \(activeProvider?.accountLabel ?? "") — no folders selected").font(.system(size: 11)).foregroundColor(.secondary)
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(selectedCloudFolders) { f in
                                            HStack(spacing: 4) {
                                                Image(systemName: "cloud").font(.system(size: 9)).foregroundColor(.blue.opacity(0.7))
                                                Text(f.name).font(.system(size: 10)).lineLimit(1).help(f.path)
                                                Button(action: { selectedCloudFolders.removeAll { $0 == f } }) {
                                                    Image(systemName: "xmark.circle.fill").font(.system(size: 9)).foregroundColor(.secondary)
                                                }.buttonStyle(.plain).disabled(remoteEngine.isScanning)
                                            }
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(Color.blue.opacity(0.08)).cornerRadius(4)
                                        }
                                    }
                                }
                            }
                            Spacer(minLength: 0)
                            Button("Add Folder…") { showingCloudPicker = true }
                                .buttonStyle(.bordered).controlSize(.small).disabled(remoteEngine.isScanning)
                            Button("Switch…") { showingConnectionPicker = true }
                                .buttonStyle(.bordered).controlSize(.small).disabled(remoteEngine.isScanning)
                                .help("Switch to another saved connection (⌥-click Remote also works)")
                            Button("Sign Out") { activeProvider?.disconnect(); selectedCloudFolders = [] }
                                .buttonStyle(.bordered).controlSize(.small)
                        } else {
                            Text("\(connectionStore.activeConnection?.displayName ?? "") — not signed in").font(.system(size: 11)).foregroundColor(.secondary)
                            Spacer(minLength: 0)
                            Button("Connect \(connectionStore.activeConnection?.displayName ?? "")…") { activeProvider?.connect() }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("Switch…") { showingConnectionPicker = true }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    .onChange(of: remoteConnected) { connected in
                        if connected && source == .remote && selectedCloudFolders.isEmpty {
                            showingCloudPicker = true
                        }
                    }
                    .sheet(isPresented: $showingCloudPicker) {
                        CloudFolderPickerSheet(engine: remoteEngine,
                                               selected: $selectedCloudFolders,
                                               onClose: { showingCloudPicker = false })
                    }
                    .sheet(isPresented: $showingCloudDestPicker) {
                        CloudFolderPickerSheet(engine: remoteEngine,
                                               selected: .constant([]),
                                               onPick: { cloudSafeMergeDestination = $0 },
                                               onClose: {
                                                   showingCloudDestPicker = false
                                                   if cloudSafeMergeDestination == nil { remoteEngine.safeMergeToNewFolder = false }
                                               })
                    }
                }
            }
            .padding().background(Color(NSColor.windowBackgroundColor))
            
            // Analysis Options + Sorting — two rows: Options (top) / Actions (bottom)
            VStack(alignment: .leading, spacing: 8) {
              // ── Options ──
              HStack(spacing: 20) {
                Text("OPTIONS").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary.opacity(0.6))
                HStack(spacing: 15) {
                    if mode == .files {
                        Toggle(isOn: $fileScanner.useDeepAnalysis) {
                            Label("Deep Scan", systemImage: "checkmark.shield").font(.system(size: 10))
                        }
                        .toggleStyle(.checkbox).disabled(scanner.isScanning)
                        Toggle(isOn: $fileScanner.filterMediaOnly) {
                            Label("Media", systemImage: "photo.on.rectangle").font(.system(size: 10))
                        }
                        .toggleStyle(.checkbox).disabled(scanner.isScanning)
                        Toggle(isOn: $fileScanner.skipHiddenFiles) {
                            Label("No Hidden", systemImage: "eye.slash").font(.system(size: 10))
                        }
                        .toggleStyle(.checkbox).disabled(scanner.isScanning)
                        Toggle(isOn: $fileScanner.detectSymlinks) {
                            Label("Symlinks", systemImage: "link").font(.system(size: 10))
                        }
                        .toggleStyle(.checkbox).disabled(scanner.isScanning)
                    } else if mode == .folders {
                        Toggle(isOn: $folderScanner.filterMediaOnly) {
                            Label("Media", systemImage: "photo.on.rectangle").font(.system(size: 10))
                        }
                        .toggleStyle(.checkbox).disabled(scanner.isScanning)
                        Toggle(isOn: $folderScanner.skipHiddenFiles) {
                            Label("No Hidden", systemImage: "eye.slash").font(.system(size: 10))
                        }
                        .toggleStyle(.checkbox).disabled(scanner.isScanning)
                        HStack(spacing: 4) {
                            Text("Match:").font(.system(size: 10)).foregroundColor(.secondary)
                            Slider(value: $folderScanner.folderMatchThreshold, in: 0.5...1.0, step: 0.05)
                                .frame(width: 80)
                                .disabled(scanner.isScanning)
                            Text("\(Int(scanner.folderMatchThreshold * 100))%").font(.system(size: 10, weight: .medium)).frame(width: 28)
                        }
                    } else if mode == .photos {
                        HStack(spacing: 4) {
                            Text("Similarity:").font(.system(size: 10)).foregroundColor(.secondary)
                            Slider(value: $photoEngine.matchThreshold, in: 0.70...1.0, step: 0.01)
                                .frame(width: 90)
                                .disabled(photoEngine.isScanning)
                            Text("\(Int(photoEngine.matchThreshold * 100))%").font(.system(size: 10, weight: .medium)).frame(width: 32)
                        }
                        Toggle(isOn: $photoEngine.requireExifCorroboration) {
                            Label("EXIF corroboration", systemImage: "calendar.badge.clock").font(.system(size: 10))
                        }
                        .toggleStyle(.checkbox).disabled(photoEngine.isScanning)
                        .help("Also require a metadata match (same capture time, or same camera + dimensions) before grouping two photos.")

                        Toggle(isOn: $photoEngine.expandByMetadata) {
                            Label("Expand by metadata", systemImage: "wand.and.stars").font(.system(size: 10))
                        }
                        .toggleStyle(.checkbox).disabled(photoEngine.isScanning)
                        .help("After visual grouping, pull in additional photos that share the selected metadata (e.g. captured at the same time/place).")

                        if photoEngine.expandByMetadata {
                            Toggle("Time", isOn: $photoEngine.expandUseTime)
                                .toggleStyle(.checkbox).font(.system(size: 10)).disabled(photoEngine.isScanning)
                            Toggle("GPS", isOn: $photoEngine.expandUseGPS)
                                .toggleStyle(.checkbox).font(.system(size: 10)).disabled(photoEngine.isScanning)
                            Toggle("Camera", isOn: $photoEngine.expandUseCamera)
                                .toggleStyle(.checkbox).font(.system(size: 10)).disabled(photoEngine.isScanning)
                        }
                    }
                }
                if mode != .photos {
                    Divider().frame(height: 20)
                    HStack(spacing: 8) {
                        sortButton(label: "Copies", criteria: .count)
                        sortButton(label: "Size", criteria: .size)
                        sortButton(label: "Match Ratio", criteria: .matchRatio)
                    }
                }
                Spacer()
              }   // end Options row

              // ── Actions ──
              if hasActionControls {
                Divider()
                HStack(spacing: 12) {
                  Text("ACTIONS").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary.opacity(0.6))
                if source == .local && mode == .files && !shownFileGroups.isEmpty && !scanner.isScanning {
                    SizeFilterBar(filter: $filesSizeFilter)
                }
                if !shownFolderGroups.isEmpty && !scanner.isScanning {
                    Toggle(isOn: $folderScanner.safeMergeToNewFolder) {
                        Label("Copy to new folder", systemImage: "doc.on.doc").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox)
                    .help("Keep originals untouched — write the merged result into a destination folder you choose")
                    .onChange(of: scanner.safeMergeToNewFolder) { on in
                        if on {
                            // Defer so the toggle's state update finishes before the modal panel opens
                            DispatchQueue.main.async { chooseSafeMergeDestination() }
                        } else {
                            safeMergeDestination = nil
                        }
                    }
                    if scanner.safeMergeToNewFolder, let dest = safeMergeDestination {
                        Button(action: { chooseSafeMergeDestination() }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.right").font(.system(size: 8))
                                Text(dest.lastPathComponent).font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Merged copies are written into \(dest.path). Click to change.")
                    }

                    if !scanner.safeMergeToNewFolder {
                        Toggle(isOn: $folderScanner.renameKeptFolder) {
                            Label("Rename kept folder", systemImage: "pencil").font(.system(size: 10))
                        }
                        .toggleStyle(.checkbox)
                        .help("When on, the kept folder is renamed with the merged tag (e.g. \"…_merged\"). When off, it keeps its original name and just gains the merged files.")
                    }

                    Picker("", selection: $folderScanner.logLocationMode) {
                        Text("Log: App folder").tag(LogLocationMode.appFolder)
                        Text("Log: Ask each time").tag(LogLocationMode.askEachTime)
                    }
                    .pickerStyle(.menu).frame(width: 150)
                    .help("Where the merge log (JSON + HTML) is saved after each merge.")

                    if let logURL = scanner.lastLogURL {
                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }) {
                            Label("Reveal Log", systemImage: "doc.text.magnifyingglass").font(.system(size: 10))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("Show the most recent merge log in Finder")
                    }
                }

                // OneDrive folder-merge controls (mirror local Folders mode)
                if source == .remote && mode == .folders && !remoteEngine.folderGroups.isEmpty && !remoteEngine.isScanning {
                    Toggle(isOn: $remoteEngine.safeMergeToNewFolder) {
                        Label("Copy to new folder", systemImage: "doc.on.doc").font(.system(size: 10))
                    }
                    .toggleStyle(.checkbox)
                    .help("Keep originals untouched — copy the merged result into a new OneDrive folder you choose")
                    .onChange(of: remoteEngine.safeMergeToNewFolder) { on in
                        if on { showingCloudDestPicker = true } else { cloudSafeMergeDestination = nil }
                    }
                    if remoteEngine.safeMergeToNewFolder, let dest = cloudSafeMergeDestination {
                        Button(action: { showingCloudDestPicker = true }) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.right").font(.system(size: 8))
                                Text(dest.name).font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Merged copies are created inside \(dest.path). Click to change.")
                    }

                    if !remoteEngine.safeMergeToNewFolder {
                        Toggle(isOn: $remoteEngine.renameKeptFolder) {
                            Label("Rename kept folder", systemImage: "pencil").font(.system(size: 10))
                        }
                        .toggleStyle(.checkbox)
                        .help("When on, the kept folder is renamed with the merged tag. When off, it keeps its original name and just gains the merged files.")
                    }

                    Picker("", selection: $folderScanner.logLocationMode) {
                        Text("Log: App folder").tag(LogLocationMode.appFolder)
                        Text("Log: Ask each time").tag(LogLocationMode.askEachTime)
                    }
                    .pickerStyle(.menu).frame(width: 150)
                    .help("Where the merge log (JSON + HTML) is saved after each merge.")

                    if let logURL = remoteEngine.lastLogURL {
                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }) {
                            Label("Reveal Log", systemImage: "doc.text.magnifyingglass").font(.system(size: 10))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("Show the most recent merge log in Finder")
                    }
                }
                Spacer()
                // Primary folder-merge actions — right-aligned so "Merge All Folders"
                // lands in the same spot as "Clean All Duplicates" when switching modes.
                if !shownFolderGroups.isEmpty && !scanner.isScanning {
                    Button(action: { startWalkthrough() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.stack.badge.play")
                            Text("Review One-by-One")
                        }
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.indigo)
                        .frame(width: 150, height: 24)
                        .background(Color.indigo.opacity(0.1)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Step through each folder pair and approve or skip individually")

                    Button(action: {
                        if scanner.safeMergeToNewFolder { safeMergeBatch(scanner.folderDuplicateGroups) }
                        else { showingMergeAllSheet = true }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: scanner.safeMergeToNewFolder ? "doc.on.doc" : "arrow.triangle.merge")
                            Text(scanner.safeMergeToNewFolder ? "Merge All to New" : "Merge All Folders")
                        }
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.indigo)
                        .frame(width: 150, height: 24)
                        .background(Color.indigo.opacity(0.1)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                if source == .remote && mode == .folders && !remoteEngine.folderGroups.isEmpty && !remoteEngine.isScanning {
                    Button(action: { startCloudWalkthrough() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.stack.badge.play")
                            Text("Review One-by-One")
                        }
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.indigo)
                        .frame(width: 150, height: 24)
                        .background(Color.indigo.opacity(0.1)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Step through each folder cluster and approve or skip individually")

                    Button(action: { showingCloudMergeAllSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: remoteEngine.safeMergeToNewFolder ? "doc.on.doc" : "arrow.triangle.merge")
                            Text(remoteEngine.safeMergeToNewFolder ? "Merge All to New" : "Merge All Folders")
                        }
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.indigo)
                        .frame(width: 150, height: 24)
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
                        .frame(width: 150, height: 24)
                        .background(Color.red.opacity(0.1)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                }   // end Actions row
              }     // end if hasActionControls
            }       // end VStack
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
            if source == .remote {
                if remoteConnected && mode == .files && (!selectedCloudFolders.isEmpty || !remoteEngine.groups.isEmpty) {
                    CloudFilesView(engine: remoteEngine, selectedCloudID: $selectedCloudID)
                } else if remoteConnected && mode == .folders && (!selectedCloudFolders.isEmpty || !remoteEngine.folderGroups.isEmpty) {
                    CloudFoldersView(engine: remoteEngine, selectedCloudID: $selectedCloudID,
                                     onMergeCluster: { previewCloudCluster = $0 })
                } else {
                    Spacer()
                    VStack(spacing: 12) {
                        let connName = connectionStore.activeConnection?.displayName ?? "Remote"
                        Image(systemName: "cloud").font(.system(size: 48)).foregroundColor(.gray.opacity(0.25))
                        Text(remoteConnected ? "\(connName) — \(mode.rawValue)" : connName)
                            .font(.title3).fontWeight(.semibold)
                        Text(remoteConnected
                             ? ((mode == .files || mode == .folders)
                                ? "Add one or more folders, then press Search."
                                : "Duplicate \(mode.rawValue.lowercased()) on \(connName) arrives in a later update.")
                             : (connectionStore.activeConnection == nil
                                ? "Choose a remote connection to scan for duplicates."
                                : "Connect \(connName) to scan it for duplicates."))
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                        if remoteConnected && (mode == .files || mode == .folders) && selectedCloudFolders.isEmpty {
                            Button("Add Folder…") { showingCloudPicker = true }
                                .controlSize(.small)
                        }
                        if connectionStore.activeConnection == nil {
                            Button("Choose Connection…") { showingConnectionPicker = true }
                                .controlSize(.small)
                        }
                        if let st = activeProvider?.statusMessage, !st.isEmpty {
                            Text(st).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
            } else if mode == .photos {
                PhotosModeView(engine: photoEngine, hasFolders: !sourceFolders.isEmpty, selectedPhotoID: $selectedPhotoID)
            } else if !shownFileGroups.isEmpty || !shownFolderGroups.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        let fileCount = filesSizeFilter.isActive ? "\(displayedFileGroups.count) of \(shownFileGroups.count)" : "\(displayedFileGroups.count + shownFolderGroups.count)"
                        Text("Duplicate Groups found (\(fileCount)):").font(.caption).fontWeight(.bold)
                        Spacer()
                        Text("Space to Preview").font(.system(size: 8, weight: .bold)).foregroundColor(.blue)
                        Text("Safety Lock Active").font(.system(size: 9, weight: .bold)).foregroundColor(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1)).cornerRadius(4)
                    }
                    .padding(.horizontal).padding(.vertical, 8).foregroundColor(.secondary)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if !resultSections.isEmpty {
                                ForEach(resultSections, id: \.self) { key in
                                    collapsibleSectionHeader(key)
                                    if !collapsedRoots.contains(key) {
                                        if scanner.detectFolderDuplicates {
                                            ForEach(shownFolderGroups.filter { sectionKey(forFolderGroup: $0) == key }) { folderGroupRow($0) }
                                        } else {
                                            ForEach(displayedFileGroups.filter { sectionKey(forFileGroup: $0) == key }) { fileGroupRow($0) }
                                        }
                                    }
                                }
                            } else {
                                ForEach(shownFolderGroups) { folderGroupRow($0) }
                                ForEach(displayedFileGroups) { fileGroupRow($0) }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            } else {
                Spacer()
                if !scanner.isScanning && (barStatus.isEmpty || shownFileGroups.isEmpty) {
                    Button(action: { selectSource() }) {
                        VStack {
                            Image(systemName: !barStatus.isEmpty && shownFileGroups.isEmpty && shownFolderGroups.isEmpty ? "checkmark.circle" : "folder.badge.plus")
                                .font(.system(size: 40)).foregroundColor(.gray.opacity(0.2))
                            Text(!barStatus.isEmpty && shownFileGroups.isEmpty && shownFolderGroups.isEmpty ? "No duplicates found" : "Add folder(s) to begin")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            
            // Hidden Button for Keyboard Shortcut (Space)
            Button("") {
                if source == .remote {
                    if let f = selectedCloudFile { remoteEngine.preview(f) }
                } else if mode == .photos {
                    if let p = selectedPhoto { QuickLookManager.shared.togglePreview(url: URL(fileURLWithPath: p.fullPath)) }
                } else if let file = selectedFile {
                    QuickLookManager.shared.togglePreview(url: URL(fileURLWithPath: file.fullPath))
                } else if let id = selectedFolderGroupID,
                          let fg = scanner.folderDuplicateGroups.first(where: { $0.id == id }) {
                    previewFolderGroup = previewFolderGroup == nil ? fg : nil
                }
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)

            Button("") { if source == .remote { navigateCloud(by: -1) } else if mode == .photos { navigatePhoto(by: -1) } else { navigateFolderGroup(by: -1) } }
                .keyboardShortcut(.upArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)

            Button("") { if source == .remote { navigateCloud(by: 1) } else if mode == .photos { navigatePhoto(by: 1) } else { navigateFolderGroup(by: 1) } }
                .keyboardShortcut(.downArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)

            Button("") { if source == .remote { navigateCloud(by: -1) } else if mode == .photos { navigatePhoto(by: -1) } }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)

            Button("") { if source == .remote { navigateCloud(by: 1) } else if mode == .photos { navigatePhoto(by: 1) } }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)

            // Status Bar
            HStack {
                if !barStatus.isEmpty {
                    Circle().fill(barStatusColor)
                        .frame(width: 7, height: 7)
                    Text(barStatus)
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                
                if showScannerStats {
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
        .sheet(isPresented: $showingBatchDeleteConfirm) {
            CleanAllConfirmationSheet(
                composition: cleanComposition(displayedFileGroups, deleted: scanner.deletedPaths),
                onClean: {
                    showingBatchDeleteConfirm = false
                    if filesSizeFilter.isActive {
                        scanner.recycleAllDuplicates(matching: { filesSizeFilter.contains($0.sizeBytes) })
                    } else {
                        scanner.recycleAllDuplicates()
                    }
                },
                onCancel: { showingBatchDeleteConfirm = false }
            )
        }
        .sheet(item: $previewFolderGroup) { fg in
            if walkthroughActive && walkthroughIndex < walkthroughQueue.count {
                // Walkthrough mode reuses this same sheet (a single sheet avoids the
                // multiple-.sheet-on-one-view conflict). The sheet's item identity
                // stays fixed; stepping swaps the content via .id(walkthroughIndex).
                FolderDiffPreviewSheet(
                    folderGroup: walkthroughQueue[walkthroughIndex],
                    scanner: scanner,
                    onMerge: {},
                    onClose: { cancelWalkthrough() },
                    progressLabel: "Folder \(walkthroughIndex + 1) of \(walkthroughQueue.count)",
                    onApproveNext: { approveAndAdvance() },
                    onSkip: { advanceWalkthrough() }
                )
                .id(walkthroughIndex)
            } else {
                FolderDiffPreviewSheet(
                    folderGroup: fg,
                    scanner: scanner,
                    onMerge: {
                        previewFolderGroup = nil
                        if scanner.safeMergeToNewFolder { safeMergeSingle(fg) }
                        else { folderGroupToMerge = fg }
                    },
                    onClose: { previewFolderGroup = nil }
                )
            }
        }
        .sheet(isPresented: $showingMergeAllSheet) {
            MergeAllConfirmationSheet(
                scanner: scanner,
                onMergeAll: {
                    showingMergeAllSheet = false
                    scanner.mergeFolders(scanner.folderDuplicateGroups, logDirectory: resolveLogDirectory())
                },
                onCancel: { showingMergeAllSheet = false }
            )
        }
        .sheet(item: $folderGroupToMerge) { fg in
            MergeConfirmationSheet(
                folderGroup: fg,
                scanner: scanner,
                onMerge: {
                    folderGroupToMerge = nil
                    scanner.mergeFolder(fg, logDirectory: resolveLogDirectory())
                },
                onCancel: { folderGroupToMerge = nil }
            )
        }
        .sheet(item: $previewCloudCluster) { cluster in
            if cloudWalkthroughActive && cloudWalkthroughIndex < cloudWalkthroughQueue.count {
                CloudClusterSheet(
                    engine: remoteEngine,
                    cluster: cloudWalkthroughQueue[cloudWalkthroughIndex],
                    selectedCloudID: $selectedCloudID,
                    progressLabel: "Cluster \(cloudWalkthroughIndex + 1) of \(cloudWalkthroughQueue.count)",
                    copyDestinationName: cloudCopyDestinationName,
                    onApproveNext: { approveAndAdvanceCloud() },
                    onSkip: { advanceCloudWalkthrough() },
                    onClose: { cancelCloudWalkthrough() }
                )
                .id(cloudWalkthroughIndex)
            } else {
                CloudClusterSheet(
                    engine: remoteEngine,
                    cluster: cluster, selectedCloudID: $selectedCloudID,
                    copyDestinationName: cloudCopyDestinationName,
                    onMerge: {
                        previewCloudCluster = nil
                        if remoteEngine.safeMergeToNewFolder { safeMergeCloudSingle(cluster) }
                        else { mergeCloud([cluster]) }
                    },
                    onClose: { previewCloudCluster = nil }
                )
            }
        }
        .sheet(isPresented: $showingCloudMergeAllSheet) {
            CloudMergeAllSheet(
                engine: remoteEngine, scanner: scanner,
                copyDestinationName: cloudCopyDestinationName,
                onMergeAll: {
                    showingCloudMergeAllSheet = false
                    if remoteEngine.safeMergeToNewFolder { safeMergeCloudBatch(remoteEngine.folderGroups) }
                    else { mergeCloud(remoteEngine.folderGroups) }
                },
                onCancel: { showingCloudMergeAllSheet = false }
            )
        }
        .sheet(isPresented: $showingConnectionPicker) {
            RemoteConnectionPickerSheet(store: connectionStore,
                                        onSelect: { activateConnection($0) },
                                        onClose: { showingConnectionPicker = false })
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("undoLastOperation"))) { _ in
            performUndo()
        }
    }

    private func performUndo() {
        guard let result = OperationHistory.shared.undoLast() else {
            scanner.status = "Nothing to undo."
            photoEngine.status = "Nothing to undo."
            return
        }
        let restored = Set(result.restoredOriginals)
        scanner.deletedPaths.subtract(restored)
        photoEngine.deletedPaths.subtract(restored)
        scanner.status = result.status
        photoEngine.status = result.status
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
    
    private func navigateFolderGroup(by delta: Int) {
        let groups = scanner.folderDuplicateGroups
        guard !groups.isEmpty else { return }
        let currentIndex = groups.firstIndex(where: { $0.id == selectedFolderGroupID }) ?? -1
        let nextIndex = min(max(currentIndex + delta, 0), groups.count - 1)
        let nextGroup = groups[nextIndex]
        selectedFolderGroupID = nextGroup.id
        // If the preview is open, update it to the new selection
        if previewFolderGroup != nil { previewFolderGroup = nextGroup }
    }

    // Flattened photo order across all groups, skipping already-deleted ones
    private var photoOrder: [PhotoInfo] {
        photoEngine.groups.flatMap { $0.photos.filter { !photoEngine.deletedPaths.contains($0.fullPath) } }
    }
    private var selectedPhoto: PhotoInfo? {
        photoOrder.first { $0.id == selectedPhotoID }
    }

    private func navigatePhoto(by delta: Int) {
        let order = photoOrder
        guard !order.isEmpty else { return }
        let currentIndex = order.firstIndex { $0.id == selectedPhotoID } ?? -1
        let nextIndex = min(max(currentIndex + delta, 0), order.count - 1)
        let next = order[nextIndex]
        selectedPhotoID = next.id
        // If Quick Look is already open, flip it to the newly selected photo
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared()?.isVisible == true {
            QuickLookManager.shared.showPreview(url: URL(fileURLWithPath: next.fullPath))
        }
    }

    // Cloud (OneDrive) navigation — flattened over all groups, skipping deleted files
    private var cloudOrder: [CloudFileInfo] {
        remoteEngine.displayGroups.flatMap { $0.files.filter { !remoteEngine.deletedIDs.contains($0.id) } }
    }
    private var selectedCloudFile: CloudFileInfo? { cloudOrder.first { $0.id == selectedCloudID } }

    private func navigateCloud(by delta: Int) {
        let order = cloudOrder
        guard !order.isEmpty else { return }
        let currentIndex = order.firstIndex { $0.id == selectedCloudID } ?? -1
        let nextIndex = min(max(currentIndex + delta, 0), order.count - 1)
        let next = order[nextIndex]
        selectedCloudID = next.id
        // If Quick Look is open, flip to the newly selected cloud file (downloads it)
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared()?.isVisible == true {
            remoteEngine.preview(next)
        }
    }

    private var selectedRootPaths: [String] { sourceFolders.map { $0.path } }

    // The single selected root that contains all the given paths, or nil if they
    // span more than one selected folder (a cross-folder duplicate). Longest match
    // wins so nested selections resolve to the most specific folder.
    private func owningRoot(_ paths: [String]) -> String? {
        var roots = Set<String>()
        for p in paths {
            let matches = selectedRootPaths.filter { p == $0 || p.hasPrefix($0 + "/") }
            if let best = matches.max(by: { $0.count < $1.count }) { roots.insert(best) }
        }
        return roots.count == 1 ? roots.first : nil
    }

    private func sectionKey(forFolderGroup fg: FolderDuplicateGroup) -> String {
        owningRoot(fg.folders) ?? acrossKey
    }
    private func sectionKey(forFileGroup g: DuplicateGroup) -> String {
        owningRoot(g.files.map { $0.path }) ?? acrossKey
    }

    private func sectionCount(_ key: String) -> Int {
        scanner.detectFolderDuplicates
            ? scanner.folderDuplicateGroups.filter { sectionKey(forFolderGroup: $0) == key }.count
            : displayedFileGroups.filter { sectionKey(forFileGroup: $0) == key }.count
    }

    // Ordered section keys (selected folders first in selection order, then the
    // "across folders" bucket). Empty when only one folder is selected — then the
    // list stays flat.
    private var resultSections: [String] {
        guard sourceFolders.count >= 2 else { return [] }
        var keys = selectedRootPaths.filter { sectionCount($0) > 0 }
        if sectionCount(acrossKey) > 0 { keys.append(acrossKey) }
        return keys
    }

    @ViewBuilder
    private func folderGroupRow(_ folderGroup: FolderDuplicateGroup) -> some View {
        let isCollapsed = collapsedFolderGroupIDs.contains(folderGroup.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button(action: {
                    if isCollapsed { collapsedFolderGroupIDs.remove(folderGroup.id) }
                    else { collapsedFolderGroupIDs.insert(folderGroup.id) }
                }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.indigo).frame(width: 12)
                }
                .buttonStyle(.plain)
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.indigo)
                VStack(alignment: .leading, spacing: 1) {
                    Text(URL(fileURLWithPath: folderGroup.keepFolder).lastPathComponent)
                        .fontWeight(.bold).font(.system(size: 12))
                    Text(folderGroup.keepFolder)
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 9)).foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    if folderGroup.otherFolders.count == 1 {
                        Text(URL(fileURLWithPath: folderGroup.folderB).lastPathComponent)
                            .fontWeight(.bold).font(.system(size: 12))
                        Text(folderGroup.folderB)
                            .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("\(folderGroup.otherFolders.count) other folders")
                            .fontWeight(.bold).font(.system(size: 12)).foregroundColor(.indigo)
                        ForEach(folderGroup.otherFolders, id: \.self) { path in
                            Text(path)
                                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                                .help(path)
                        }
                    }
                }
                Spacer()
                Text("\(Int(folderGroup.matchRatio * 100))% match")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.indigo)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.indigo.opacity(0.1)).cornerRadius(3)
                    .help(folderGroup.tooltipText)
            }
            if !isCollapsed {
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
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive").font(.system(size: 8))
                    Text("Saves \(scanner.formatBytes(Int64(folderGroup.potentialSavings)))")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.green.opacity(0.4), lineWidth: 1))
                Button(action: {
                    if scanner.safeMergeToNewFolder { safeMergeSingle(folderGroup) }
                    else { folderGroupToMerge = folderGroup }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: scanner.safeMergeToNewFolder ? "doc.on.doc" : "arrow.triangle.merge")
                        Text(scanner.safeMergeToNewFolder ? "Merge to New" : "Merge & Clean")
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

    @ViewBuilder
    private func fileGroupRow(_ group: DuplicateGroup) -> some View {
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

    @ViewBuilder
    private func collapsibleSectionHeader(_ key: String) -> some View {
        let isCollapsed = collapsedRoots.contains(key)
        let isAcross = key == acrossKey
        Button(action: {
            if isCollapsed { collapsedRoots.remove(key) } else { collapsedRoots.insert(key) }
        }) {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.blue)
                    .frame(width: 12)
                Image(systemName: isAcross ? "arrow.triangle.branch" : "folder.fill")
                    .font(.system(size: 11)).foregroundColor(.blue)
                Text(isAcross ? "Across multiple folders" : URL(fileURLWithPath: key).lastPathComponent)
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.primary)
                if !isAcross {
                    Text(key)
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text("\(sectionCount(key))")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.blue.opacity(0.12)).cornerRadius(8)
            }
            .padding(.vertical, 5).padding(.horizontal, 8)
            .background(Color.blue.opacity(0.08)).cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls where !sourceFolders.contains(url) {
                sourceFolders.append(url)
            }
        }
    }

    // Switch the Remote source to a saved connection: point the engine at its
    // provider, clear per-drive state, and start sign-in if it has no tokens yet.
    private func activateConnection(_ conn: RemoteConnection) {
        if connectionStore.activeID == conn.id {
            if !(activeProvider?.isConnected ?? false) { activeProvider?.connect() }
            return
        }
        let p = connectionStore.activate(conn)
        remoteEngine.setProvider(p)
        selectedCloudFolders = []
        selectedCloudID = nil
        cloudSafeMergeDestination = nil
        if !p.isConnected { p.connect() }
    }

    private func startScanning() {
        if source == .remote {
            if remoteEngine.isScanning { remoteEngine.stop(); return }
            guard remoteConnected, !selectedCloudFolders.isEmpty else { return }
            if mode == .files {
                remoteEngine.scan(folders: selectedCloudFolders)
            } else if mode == .folders {
                remoteEngine.scan(folders: selectedCloudFolders, folderMode: true)
            } else {
                activeProvider?.statusMessage = "\(mode.rawValue) scanning on remote drives arrives in a later update."
            }
            return
        }
        if mode == .photos {
            if photoEngine.isScanning { photoEngine.stop(); return }
            guard !sourceFolders.isEmpty else { return }
            searchedModes.insert(.photos)
            photoEngine.startScan(sourceFolders)
            return
        }
        if scanner.isScanning { scanner.stopScan(); return }
        guard !sourceFolders.isEmpty else { return }
        searchedModes.insert(mode)   // .files or .folders — each has its own engine
        scanner.startScan(sourceURLs: sourceFolders)
    }

    // The bottom-bar status pertains to the current mode only (empty if that mode
    // hasn't run a search, or for the OneDrive source which shows its own status).
    private var barStatus: String {
        guard source == .local, searchedModes.contains(mode) else { return "" }
        return mode == .photos ? photoEngine.status : scanner.status
    }

    private var barScanning: Bool {
        mode == .photos ? photoEngine.isScanning : scanner.isScanning
    }

    private var barStatusColor: Color {
        if barStatus.contains("Error") || barStatus.contains("failed") { return .red }
        if barScanning { return .green }
        if barStatus.contains("Completed") || barStatus.contains("Trash") { return .blue }
        return .gray
    }

    // MARK: - One-by-one merge walkthrough

    private func startWalkthrough() {
        walkthroughQueue = scanner.folderDuplicateGroups
        guard let first = walkthroughQueue.first else { return }
        walkthroughIndex = 0
        approvedFolderIDs = []
        walkthroughActive = true
        previewFolderGroup = first   // presents the shared preview sheet in walkthrough mode
    }

    private func approveAndAdvance() {
        approvedFolderIDs.insert(walkthroughQueue[walkthroughIndex].id)
        advanceWalkthrough()
    }

    private func advanceWalkthrough() {
        let next = walkthroughIndex + 1
        if next >= walkthroughQueue.count {
            finishWalkthrough()
        } else {
            walkthroughIndex = next
        }
    }

    private func finishWalkthrough() {
        walkthroughActive = false
        previewFolderGroup = nil
        let approved = walkthroughQueue.filter { approvedFolderIDs.contains($0.id) }
        guard !approved.isEmpty else { return }
        if scanner.safeMergeToNewFolder { safeMergeBatch(approved) }
        else { scanner.mergeFolders(approved, logDirectory: resolveLogDirectory()) }
    }

    private func cancelWalkthrough() {
        walkthroughActive = false
        previewFolderGroup = nil
        approvedFolderIDs = []
    }

    // MARK: - OneDrive folder merge + walkthrough

    private func mergeCloud(_ groups: [CloudFolderDupGroup]) {
        remoteEngine.mergeFolders(groups,
            mergedName: { a, b in scanner.computeMergedFolderName(folderA: a, folderB: b) },
            logDir: resolveLogDirectory())
    }

    private func startCloudWalkthrough() {
        cloudWalkthroughQueue = remoteEngine.folderGroups
        guard let first = cloudWalkthroughQueue.first else { return }
        cloudWalkthroughIndex = 0
        approvedCloudIDs = []
        cloudWalkthroughActive = true
        previewCloudCluster = first
    }

    private func approveAndAdvanceCloud() {
        approvedCloudIDs.insert(cloudWalkthroughQueue[cloudWalkthroughIndex].id)
        advanceCloudWalkthrough()
    }

    private func advanceCloudWalkthrough() {
        let next = cloudWalkthroughIndex + 1
        if next >= cloudWalkthroughQueue.count { finishCloudWalkthrough() }
        else { cloudWalkthroughIndex = next }
    }

    private func finishCloudWalkthrough() {
        cloudWalkthroughActive = false
        previewCloudCluster = nil
        let approved = cloudWalkthroughQueue.filter { approvedCloudIDs.contains($0.id) }
        guard !approved.isEmpty else { return }
        if remoteEngine.safeMergeToNewFolder { safeMergeCloudBatch(approved) }
        else { mergeCloud(approved) }
    }

    // MARK: - OneDrive safe merge (copy to a new OneDrive folder chosen via the toggle)

    private func safeMergeCloudSingle(_ g: CloudFolderDupGroup) { safeMergeCloudBatch([g]) }

    private func safeMergeCloudBatch(_ groups: [CloudFolderDupGroup]) {
        guard !groups.isEmpty else { return }
        guard let dest = cloudSafeMergeDestination else { showingCloudDestPicker = true; return }
        remoteEngine.safeMergeFolders(groups, intoParent: dest.id,
            mergedName: { a, b in scanner.computeMergedFolderName(folderA: a, folderB: b) },
            logDir: resolveLogDirectory())
    }

    private func cancelCloudWalkthrough() {
        cloudWalkthroughActive = false
        previewCloudCluster = nil
        approvedCloudIDs = []
    }

    // When the log mode is "ask each time", prompt for a folder; otherwise return nil
    // so the scanner writes to its default app logs folder.
    private func resolveLogDirectory() -> URL? {
        guard scanner.logLocationMode == .askEachTime else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose where to save the merge log (JSON + HTML)."
        panel.prompt = "Save Log Here"
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: - Safe merge (copy to a destination chosen when the toggle is enabled)

    private func chooseSafeMergeDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose the destination folder for merged copies. Originals are kept untouched; one merged subfolder is created per cluster."
        panel.prompt = "Choose Destination"
        if panel.runModal() == .OK, let url = panel.url {
            safeMergeDestination = url
        } else {
            // Cancelled — revert the toggle
            scanner.safeMergeToNewFolder = false
            safeMergeDestination = nil
        }
    }

    private func safeMergeSingle(_ fg: FolderDuplicateGroup) {
        guard let parent = safeMergeDestination ?? promptDestinationFallback() else { return }
        scanner.safeMergeFolders([fg], intoParent: parent, logDirectory: resolveLogDirectory())
    }

    private func safeMergeBatch(_ groups: [FolderDuplicateGroup]) {
        guard !groups.isEmpty else { return }
        guard let parent = safeMergeDestination ?? promptDestinationFallback() else { return }
        scanner.safeMergeFolders(groups, intoParent: parent, logDirectory: resolveLogDirectory())
    }

    // Safety net: if a copy-merge is triggered without a stored destination, ask now.
    private func promptDestinationFallback() -> URL? {
        chooseSafeMergeDestination()
        return safeMergeDestination
    }
}

// MARK: - Folder Diff Preview

struct DiffRow: Identifiable {
    enum Kind {
        case matched(fileA: DuplicateFileInfo, fileB: DuplicateFileInfo)
        case uniqueToA(DuplicateFileInfo)
        case uniqueToB(DuplicateFileInfo, wouldDuplicate: Bool, renamedTo: String?)
    }
    let id = UUID()
    let kind: Kind
}

struct FolderDiffPreviewSheet: View {
    let folderGroup: FolderDuplicateGroup
    @ObservedObject var scanner: FileScanner
    let onMerge: () -> Void
    let onClose: () -> Void
    // Walkthrough mode (one-by-one review). When onApproveNext is non-nil, the sheet
    // shows progress + Cancel / Skip / Merge & Next instead of Close / Merge & Clean.
    var progressLabel: String? = nil
    var onApproveNext: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    @State private var focusedRowIndex: Int = -1

    private var isWalkthrough: Bool { onApproveNext != nil }

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

    // filename-only set for name collision detection
    private var filenamesInA: Set<String> {
        var names = Set<String>()
        for group in folderGroup.matchedGroups {
            if let fA = group.files.first(where: { $0.path == folderGroup.folderA }) {
                names.insert(fA.name)
            }
        }
        for f in folderGroup.uniqueToA { names.insert(f.name) }
        return names
    }

    private var diffRows: [DiffRow] {
        let aKeys = filesInAKeys
        let keep = folderGroup.keepFolder
        let moveIDs = Set(folderGroup.filesToMove.map { $0.id })
        var rows: [DiffRow] = []

        // DELETE rows — every removable duplicate copy (all copies except the kept/moved one)
        for group in folderGroup.matchedGroups.sorted(by: { $0.name < $1.name }) {
            let keepCopy = group.files.first { $0.path == keep }
            let moveRep = group.files.first { moveIDs.contains($0.id) }
            let kept = keepCopy ?? moveRep
            for f in group.files {
                if f.path == keep { continue }       // keep's copy stays
                if moveIDs.contains(f.id) { continue } // this one is shown as MOVE below
                rows.append(DiffRow(kind: .matched(fileA: kept ?? f, fileB: f)))
            }
        }

        // NO CHANGE rows — files that exist only in the keep folder
        for file in folderGroup.uniqueToKeep.sorted(by: { $0.name < $1.name }) {
            rows.append(DiffRow(kind: .uniqueToA(file)))
        }

        // MOVE rows — unique files brought into keep from the other folders
        let nameCollisions = filenamesInA
        for file in folderGroup.filesToMove.sorted(by: { $0.name < $1.name }) {
            let sourceFolderName = URL(fileURLWithPath: file.path).lastPathComponent
            let wouldDuplicate = aKeys.contains("\(file.name)_\(file.sizeBytes)")
            let renamedTo: String? = (!wouldDuplicate && nameCollisions.contains(file.name))
                ? FileScanner.resolveCollisionName(for: file.name, sourceFolderName: sourceFolderName)
                : nil
            rows.append(DiffRow(kind: .uniqueToB(file, wouldDuplicate: wouldDuplicate, renamedTo: renamedTo)))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {

            // Walkthrough progress strip
            if let progressLabel {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.play").foregroundColor(.indigo)
                    Text("Reviewing folder pairs").font(.system(size: 11, weight: .bold))
                    Spacer()
                    Text(progressLabel).font(.system(size: 11, weight: .semibold)).foregroundColor(.indigo)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.indigo.opacity(0.08))
                Divider()
            }

            // Content area with column background strip
            VStack(spacing: 0) {

                // Header
                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").foregroundColor(.green)
                            Text(nameA).fontWeight(.bold).font(.system(size: 13))
                        }
                        Text("KEEP").font(.system(size: 9, weight: .bold)).foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color.green.opacity(0.08))

                    Text("Operations")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 110, maxWidth: 110, maxHeight: .infinity, alignment: .center)

                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").foregroundColor(.red)
                            Text(folderGroup.otherFolders.count == 1 ? nameB : "\(folderGroup.otherFolders.count) folders")
                                .fontWeight(.bold).font(.system(size: 13))
                        }
                        Text("MERGE & CLEAN").font(.system(size: 9, weight: .bold)).foregroundColor(.red)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .background(Color.red.opacity(0.06))
                }
                .frame(height: 50)

                Divider()

                // Legend
                HStack(spacing: 16) {
                    legendItem(color: .orange, label: "Duplicate (kept in A)")
                    legendItem(color: .red, label: "Duplicate (deleted from B)")
                    legendItem(color: .blue, label: "Unique (moved to A)")
                    legendItem(color: .orange, label: "Unique (moved & renamed)")
                    legendItem(color: .secondary, label: "Unique (no change)")
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.gray.opacity(0.04))

                Divider()

                // Diff rows
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(diffRows.enumerated()), id: \.element.id) { index, row in
                                diffRowView(row)
                                    .background(index == focusedRowIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                                    .id(index)
                                Divider().opacity(0.4)
                            }
                        }
                    }
                    .onChange(of: focusedRowIndex) { newIndex in
                        withAnimation { proxy.scrollTo(newIndex, anchor: .center) }
                    }
                    .background(
                        Group {
                            Button("") {
                                focusedRowIndex = max(0, focusedRowIndex < 0 ? 0 : focusedRowIndex - 1)
                            }
                            .keyboardShortcut(.upArrow, modifiers: [])
                            .buttonStyle(.plain)
                            .opacity(0).frame(width: 0, height: 0)

                            Button("") {
                                focusedRowIndex = min(diffRows.count - 1, focusedRowIndex < 0 ? 0 : focusedRowIndex + 1)
                            }
                            .keyboardShortcut(.downArrow, modifiers: [])
                            .buttonStyle(.plain)
                            .opacity(0).frame(width: 0, height: 0)
                        }
                    )
                }
            }
            .background(
                HStack(spacing: 0) {
                    Color.clear.frame(maxWidth: .infinity)
                    Color(NSColor.windowBackgroundColor).frame(width: 110)
                    Color.clear.frame(maxWidth: .infinity)
                }
                .ignoresSafeArea()
            )

            Divider()

            // Footer — no column background
            HStack {
                Text("\(folderGroup.matchedGroups.count) duplicate · \(folderGroup.uniqueToB.count) to move · \(folderGroup.uniqueToA.count) unchanged")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Spacer()
                if isWalkthrough {
                    Button("Cancel", action: onClose).buttonStyle(.bordered)
                        .help("Cancel the whole review — nothing is changed")
                    Button(action: { onSkip?() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.forward")
                            Text("Skip")
                        }
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.gray.opacity(0.15)).cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                    .help("Leave this folder untouched and go to the next (→)")
                    Button(action: { onApproveNext?() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.merge")
                            Text("Merge & Next")
                        }
                        .fontWeight(.semibold).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.indigo).cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                    .help("Approve this merge and go to the next (Return)")
                } else {
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
            }
            .padding(12)
        }
        .frame(width: 820, height: 560)
        // Keyboard shortcuts
        .background(
            Group {
                if isWalkthrough {
                    Button("") { onApproveNext?() }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.plain).opacity(0).frame(width: 0, height: 0)
                    Button("") { onSkip?() }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .buttonStyle(.plain).opacity(0).frame(width: 0, height: 0)
                    Button("") { onClose() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.plain).opacity(0).frame(width: 0, height: 0)
                } else {
                    // Space bar closes the sheet, mirroring the Close button
                    Button("") { onClose() }
                        .keyboardShortcut(.space, modifiers: [])
                        .buttonStyle(.plain).opacity(0).frame(width: 0, height: 0)
                }
            }
        )
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

            case .uniqueToB(let f, let wouldDuplicate, let renamedTo):
                if wouldDuplicate {
                    emptyCell()
                    operationCell(icon: "xmark.circle.fill", label: "DELETE", color: .red)
                    fileCell(name: f.name, size: f.size, color: .red, icon: "doc.fill", side: .leading, strikethrough: true)
                } else if let newName = renamedTo {
                    emptyCell()
                    operationCell(icon: "arrow.left.circle.fill", label: "MOVE & RENAME", color: .orange)
                    fileCellRenamed(originalName: f.name, newName: newName, size: f.size)
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
        HStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundColor(color)
                    Text(label)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(color)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            }
            Spacer()
        }
        .frame(minWidth: 110, maxWidth: 110, minHeight: 0, maxHeight: .infinity)
    }

    private func fileCellRenamed(originalName: String, newName: String, size: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: "doc.fill").font(.system(size: 10)).foregroundColor(.orange)
                Text(newName)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .lineLimit(1).truncationMode(.middle)
            }
            Text("was: \(originalName)")
                .font(.system(size: 9))
                .foregroundColor(.orange.opacity(0.7))
                .lineLimit(1).truncationMode(.middle)
            Text(size).font(.system(size: 9)).foregroundColor(.orange.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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

// Confirm "Clean All Duplicates" with a pie chart of what gets erased vs. kept.
struct CleanAllConfirmationSheet: View {
    let composition: MergeComposition
    let onClean: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill").font(.title2).foregroundColor(.red)
                Text("Clean All Duplicates").font(.title2).fontWeight(.bold)
            }

            Divider()

            MergePieChart(composition: composition)

            HStack(spacing: 4) {
                Image(systemName: "internaldrive").font(.system(size: 9)).foregroundColor(.green)
                Text("Frees \(cloudByteString(composition.removedBytes))").font(.system(size: 12, weight: .semibold)).foregroundColor(.green)
            }

            Text("⚠️ Moves \(composition.removedCount) duplicate file(s) to the Trash. One copy per group is kept safe. This change is irreversible.")
                .font(.system(size: 11)).foregroundColor(.secondary)

            Divider()

            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button(action: onClean) {
                    HStack(spacing: 6) { Image(systemName: "trash.fill"); Text("Clean All") }
                        .fontWeight(.semibold).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.red).cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(composition.removedCount == 0)
            }
        }
        .padding(24)
        .frame(width: 480)
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

            MergePieChart(composition: mergeComposition(scanner.folderDuplicateGroups))

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
                    Label("\(mergeComposition(folderGroup).removedCount) duplicate file(s) moved to Trash", systemImage: "trash")
                    Label("\(folderGroup.uniqueToB.count) unique file(s) moved into \(nameA)", systemImage: "arrow.right.doc.on.clipboard")
                    Label("\"\(nameB)\" deleted after merge", systemImage: "folder.badge.minus")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            }

            MergePieChart(composition: mergeComposition(folderGroup))

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
