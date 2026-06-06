import SwiftUI

struct LogRecord: Identifiable {
    let id = UUID()
    let jsonURL: URL
    let report: MergeLogReport
    var htmlURL: URL { jsonURL.deletingPathExtension().appendingPathExtension("html") }
    var pdfURL: URL  { jsonURL.deletingPathExtension().appendingPathExtension("pdf") }
}

struct LogsHistoryView: View {
    @State private var directory: URL? = MergeLogWriter.defaultAppLogDirectory()
    @State private var records: [LogRecord] = []
    @State private var selection: LogRecord.ID?

    private var selected: LogRecord? { records.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            List(records, selection: $selection) { rec in
                sidebarRow(rec).tag(rec.id)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
            .overlay {
                if records.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 36)).foregroundColor(.gray.opacity(0.3))
                        Text("No operation logs yet").font(.callout).foregroundColor(.secondary)
                        Text("Deletes, merges and exports write a report here.").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        } detail: {
            if let rec = selected { detail(rec) }
            else { Text("Select an operation").foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .frame(minWidth: 860, minHeight: 580)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: reload) { Image(systemName: "arrow.clockwise") }.help("Refresh")
            }
            ToolbarItem(placement: .automatic) {
                Button(action: openFolder) { Image(systemName: "folder") }.help("Open logs folder")
            }
            ToolbarItem(placement: .automatic) {
                Button(action: chooseFolder) { Image(systemName: "tray.and.arrow.down") }.help("Browse logs in another folder")
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: Sidebar

    @ViewBuilder
    private func sidebarRow(_ rec: LogRecord) -> some View {
        let r = rec.report
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.dateFmt.string(from: r.timestamp)).font(.system(size: 12, weight: .semibold))
            Text(r.mode).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
            HStack(spacing: 6) {
                if r.totalFilesRemoved > 0 { tag("\(r.totalFilesRemoved) removed", .red) }
                if r.totalFilesMoved > 0 { tag("\(r.totalFilesMoved) moved/copied", .blue) }
                if r.totalBytesRemoved > 0 { tag(byteString(r.totalBytesRemoved), .green) }
                if r.errorCount > 0 { tag("\(r.errorCount) err", .orange) }
            }
        }
        .padding(.vertical, 2)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 8, weight: .bold)).foregroundColor(color)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.12)).cornerRadius(3)
    }

    // MARK: Detail

    @ViewBuilder
    private func detail(_ rec: LogRecord) -> some View {
        let r = rec.report
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(r.mode).font(.headline)
                Text("\(Self.dateFmt.string(from: r.timestamp)) · v\(r.appVersion)")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Button(action: { open(rec.htmlURL) }) { Label("Open HTML", systemImage: "safari") }
                        .controlSize(.small).disabled(!FileManager.default.fileExists(atPath: rec.htmlURL.path))
                    Button(action: { open(rec.pdfURL) }) { Label("Open PDF", systemImage: "doc.richtext") }
                        .controlSize(.small).disabled(!FileManager.default.fileExists(atPath: rec.pdfURL.path))
                    Button(action: { NSWorkspace.shared.activateFileViewerSelecting([rec.jsonURL]) }) { Label("Reveal", systemImage: "magnifyingglass") }
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.top, 4)
                Text("To recover deleted items: restore them from the Trash (paths are listed below), or use ⌘Z right after an operation.")
                    .font(.caption2).foregroundColor(.secondary).padding(.top, 2)
            }
            .padding(14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(r.clusters.enumerated()), id: \.offset) { _, cluster in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cluster.resultName).font(.system(size: 12, weight: .bold))
                            ForEach(Array(cluster.entries.enumerated()), id: \.offset) { _, e in
                                entryRow(e)
                            }
                        }
                        .padding(10)
                        .background(Color.gray.opacity(0.05)).cornerRadius(6)
                    }
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ e: MergeLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(e.action).font(.system(size: 9, weight: .bold)).foregroundColor(actionColor(e.action))
                    .frame(width: 110, alignment: .leading)
                Text(e.fileName).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                Spacer()
                if e.sizeBytes > 0 { Text(byteString(e.sizeBytes)).font(.system(size: 9)).foregroundColor(.secondary) }
            }
            Text("from: \(e.sourcePath)").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                .lineLimit(1).truncationMode(.middle)
            if !e.destinationPath.isEmpty {
                Text("to: \(e.destinationPath)").font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }

    private func actionColor(_ action: String) -> Color {
        if action.hasPrefix("MOVED") { return .blue }
        if action.hasPrefix("COPIED") || action == "FOLDER_COPIED" { return .green }
        if action == "TRASHED" || action == "FOLDER_TRASHED" { return .red }
        if action == "ERROR" { return .orange }
        return .secondary
    }

    // MARK: Loading

    private func reload() {
        guard let dir = directory else { records = []; return }
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var recs: [LogRecord] = []
        for url in urls where url.pathExtension == "json" && url.lastPathComponent.hasPrefix("FileLister-merge-") {
            if let data = try? Data(contentsOf: url),
               let report = try? decoder.decode(MergeLogReport.self, from: data) {
                recs.append(LogRecord(jsonURL: url, report: report))
            }
        }
        records = recs.sorted { $0.report.timestamp > $1.report.timestamp }
        if selection == nil { selection = records.first?.id }
    }

    private func openFolder() {
        if let dir = directory { NSWorkspace.shared.activateFileViewerSelecting([dir]) }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing FileLister logs"
        if panel.runModal() == .OK, let url = panel.url { directory = url; selection = nil; reload() }
    }
    private func open(_ url: URL) { NSWorkspace.shared.open(url) }

    private func byteString(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024, mb = kb / 1024, gb = mb / 1024
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", kb)
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
}
