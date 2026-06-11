import SwiftUI

struct CloudFolderPickerSheet: View {
    @ObservedObject var engine: RemoteEngine
    @Binding var selected: [CloudFolder]
    var onPick: ((CloudFolder) -> Void)? = nil   // single-folder pick mode (e.g. safe-merge destination)
    let onClose: () -> Void

    @State private var stack: [CloudFolder] = []   // breadcrumb; last = current folder
    @State private var children: [CloudFolder] = []
    @State private var loading = false
    @State private var creatingFolder = false
    @State private var newFolderName = ""

    private var isPicking: Bool { onPick != nil }
    private var currentID: String { stack.last?.id ?? "root" }
    private var currentFolder: CloudFolder {
        stack.last ?? CloudFolder(id: "root", name: "OneDrive (entire drive)", path: "/")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header / breadcrumb
            HStack(spacing: 8) {
                Button(action: goUp) { Image(systemName: "chevron.up") }
                    .disabled(stack.isEmpty).help("Up one level")
                Image(systemName: "cloud.fill").foregroundColor(.blue)
                Text(stack.isEmpty ? "OneDrive" : currentFolder.path)
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if isPicking {
                    Button(action: { newFolderName = ""; creatingFolder = true }) {
                        Label("New Folder", systemImage: "folder.badge.plus").font(.system(size: 11))
                    }.controlSize(.small).disabled(loading)
                }
                Button(action: { if isPicking { onPick?(currentFolder); onClose() } else { add(currentFolder) } }) {
                    Label(isPicking ? "Use this folder" : "Add this folder",
                          systemImage: isPicking ? "checkmark.circle" : "plus.circle").font(.system(size: 11))
                }.controlSize(.small)
            }
            .padding(12)
            Divider()

            // Child folders
            ZStack {
                List {
                    if children.isEmpty && !loading {
                        Text("No subfolders here.").font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(children) { folder in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill").foregroundColor(.blue.opacity(0.8))
                            Button(action: { drill(into: folder) }) {
                                Text(folder.name).lineLimit(1)
                            }.buttonStyle(.plain)
                            Spacer()
                            Button(action: { if isPicking { onPick?(folder); onClose() } else { add(folder) } }) {
                                Image(systemName: isPicking ? "checkmark.circle" : (selected.contains(folder) ? "checkmark.circle.fill" : "plus.circle"))
                                    .foregroundColor(isPicking ? .blue : (selected.contains(folder) ? .green : .blue))
                            }.buttonStyle(.plain).help(isPicking ? "Use this folder" : "Add this folder")
                            Button(action: { drill(into: folder) }) {
                                Image(systemName: "chevron.right").foregroundColor(.secondary)
                            }.buttonStyle(.plain).help("Open")
                        }
                    }
                }
                if loading { ProgressView() }
            }

            Divider()
            // Selected folders
            if !isPicking && !selected.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Folders to scan (\(selected.count)):").font(.caption).foregroundColor(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(selected) { f in
                                HStack(spacing: 4) {
                                    Image(systemName: "cloud").font(.system(size: 9)).foregroundColor(.blue.opacity(0.7))
                                    Text(f.name).font(.system(size: 10)).help(f.path)
                                    Button(action: { selected.removeAll { $0 == f } }) {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 9)).foregroundColor(.secondary)
                                    }.buttonStyle(.plain)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.blue.opacity(0.08)).cornerRadius(4)
                            }
                        }
                    }
                }
                .padding(10)
            }

            HStack {
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 520)
        .onAppear { Task { await load() } }
        .alert("New Folder", isPresented: $creatingFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { Task { await createNewFolder() } }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        } message: {
            Text("Create a new folder in \(stack.isEmpty ? "OneDrive" : currentFolder.name).")
        }
    }

    private func createNewFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        loading = true
        if let folder = await engine.createFolder(named: name, in: currentID) {
            await load()                       // refresh so the new folder appears
            if isPicking { onPick?(folder); onClose() }   // creating a destination → use it
        } else {
            loading = false
        }
    }

    private func drill(into folder: CloudFolder) {
        stack.append(folder)
        Task { await load() }
    }
    private func goUp() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
        Task { await load() }
    }
    private func add(_ folder: CloudFolder) {
        if !selected.contains(folder) { selected.append(folder) }
    }
    private func load() async {
        loading = true
        let result = await engine.listFolders(parentID: currentID)
        children = result
        loading = false
    }
}
