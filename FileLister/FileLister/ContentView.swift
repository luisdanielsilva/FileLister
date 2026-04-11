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
    @State private var sourceURL: URL?
    
    // Selection state for Quick Look
    @State private var selectedFile: DuplicateFileInfo? = nil
    
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
                }
                Divider().frame(height: 20)
                HStack(spacing: 8) {
                    sortButton(label: "Copies", criteria: .count)
                    sortButton(label: "Size", criteria: .size)
                }
            }
            .padding(.bottom, 10).padding(.horizontal).frame(maxWidth: .infinity, alignment: .leading)


            if scanner.isScanning {
                ProgressView(value: scanner.progress, total: 1.0)
                    .accentColor(.green).progressViewStyle(.linear).padding(.horizontal).padding(.bottom, 10)
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
                                let remainingCount = group.files.filter { !scanner.deletedPaths.contains($0.fullPath) }.count
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
                                        HStack(spacing: 8) {
                                            SelectionButton(file: file, selectedFile: $selectedFile, isDeleted: isDeleted)
                                            
                                            if !isDeleted {
                                                Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: file.path)) }) {
                                                    Image(systemName: "folder")
                                                        .font(.system(size: 9)).foregroundColor(.gray)
                                                }
                                                .buttonStyle(.plain).help("Open folder in Finder")

                                                Button(action: { if remainingCount > 1 { scanner.recycleFile(atPath: fullPath) } }) {
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
                Text(scanner.status).font(.system(size: 10)).foregroundColor(.secondary)
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
            }
            .padding(.horizontal, 10).frame(height: 24).background(Color.gray.opacity(0.05)).overlay(Divider(), alignment: .top)
        }
        .frame(minWidth: 700, minHeight: 520)
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
        if panel.runModal() == .OK { self.sourceURL = panel.url }
    }
    
    private func startScanning() {
        guard let source = sourceURL else { return }
        scanner.startScan(sourceURL: source)
    }
}
