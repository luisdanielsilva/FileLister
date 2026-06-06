import Foundation
import AppKit

// MARK: - Where merge logs are written

enum LogLocationMode: String {
    case appFolder    // app container ~/.../Documents/FileLister Logs
    case askEachTime  // prompt for a folder before each merge
}

// MARK: - Log model (Codable → JSON; also rendered to HTML)

struct MergeLogEntry: Codable {
    let action: String              // MOVED, MOVED+RENAMED, COPIED, COPIED+RENAMED, TRASHED, FOLDER_TRASHED, FOLDER_COPIED, UNCHANGED, SKIPPED, ERROR
    let fileName: String
    let sourcePath: String
    let sourceFolder: String
    let destinationPath: String
    let destinationFolder: String
    let sizeBytes: Int
    let sha256: String
    let note: String
}

struct MergeLogCluster: Codable {
    let keepFolder: String
    let otherFolders: [String]
    let resultName: String
    let resultPath: String
    let entries: [MergeLogEntry]
}

struct MergeLogReport: Codable {
    let timestamp: Date
    let appVersion: String
    let mode: String                // human-readable description of the merge mode
    let renameKeptFolder: Bool
    let clusters: [MergeLogCluster]

    var totalFilesMoved: Int {
        clusters.reduce(0) { $0 + $1.entries.filter { $0.action.hasPrefix("MOVED") || $0.action.hasPrefix("COPIED") && $0.action != "FOLDER_COPIED" }.count }
    }
    var totalFilesRemoved: Int {
        clusters.reduce(0) { $0 + $1.entries.filter { $0.action == "TRASHED" }.count }
    }
    var totalBytesRemoved: Int {
        clusters.reduce(0) { $0 + $1.entries.filter { $0.action == "TRASHED" }.reduce(0) { $0 + $1.sizeBytes } }
    }
    var errorCount: Int {
        clusters.reduce(0) { $0 + $1.entries.filter { $0.action == "ERROR" }.count }
    }
}

// MARK: - Writer

enum MergeLogWriter {

    static let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }()

    // The app's default logs folder (sandbox container Documents/FileLister Logs).
    static func defaultAppLogDirectory() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent("FileLister Logs", isDirectory: true)
    }

    /// Writes the report as both .json and .html into `directory`.
    /// Returns the HTML URL on success (for revealing in Finder).
    @discardableResult
    static func write(_ report: MergeLogReport, to directory: URL) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stamp = fmt.string(from: report.timestamp)
        let base = "FileLister-merge-\(stamp)"

        // JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(report) {
            try? data.write(to: directory.appendingPathComponent("\(base).json"))
        }

        // HTML
        let htmlURL = directory.appendingPathComponent("\(base).html")
        let html = renderHTML(report)
        try? html.data(using: .utf8)?.write(to: htmlURL)

        // PDF (rendered offline via AppKit print-to-PDF — no WebKit/network)
        LogPDFRenderer.render(report, to: directory.appendingPathComponent("\(base).pdf"))

        return htmlURL
    }

    // MARK: HTML rendering

    private static func renderHTML(_ report: MergeLogReport) -> String {
        let df = DateFormatter()
        df.dateStyle = .long; df.timeStyle = .medium
        let when = df.string(from: report.timestamp)

        var rows = ""
        for cluster in report.clusters {
            let others = cluster.otherFolders.map { "<div class='path'>\(esc($0))</div>" }.joined()
            rows += """
            <section class="cluster">
              <h2>\(esc(cluster.resultName))</h2>
              <div class="meta">
                <div><span class="lbl">Keep</span><div class="path">\(esc(cluster.keepFolder))</div></div>
                <div><span class="lbl">Merged & cleaned</span>\(others)</div>
                <div><span class="lbl">Result</span><div class="path">\(esc(cluster.resultPath))</div></div>
              </div>
              <table>
                <thead><tr>
                  <th>Action</th><th>File</th><th>Size</th><th>From</th><th>To</th><th>SHA-256</th><th>Note</th>
                </tr></thead>
                <tbody>
            """
            for e in cluster.entries {
                rows += """
                  <tr class="\(cssClass(e.action))">
                    <td class="action">\(esc(e.action))</td>
                    <td>\(esc(e.fileName))</td>
                    <td class="num">\(byteString(e.sizeBytes))</td>
                    <td class="path">\(esc(e.sourcePath))</td>
                    <td class="path">\(esc(e.destinationPath))</td>
                    <td class="hash">\(esc(e.sha256))</td>
                    <td>\(esc(e.note))</td>
                  </tr>
                """
            }
            rows += "</tbody></table></section>"
        }

        return """
        <!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
        <title>FileLister Merge Log — \(esc(when))</title>
        <style>
          :root { color-scheme: light dark; }
          body { font: 13px -apple-system, system-ui, sans-serif; margin: 24px; color: #1d1d1f; }
          h1 { font-size: 20px; margin: 0 0 4px; }
          .sub { color: #6e6e73; margin-bottom: 16px; }
          .summary { display: flex; gap: 24px; flex-wrap: wrap; background: #f5f5f7; padding: 14px 18px; border-radius: 10px; margin-bottom: 22px; }
          .summary div b { display:block; font-size: 18px; }
          .summary div span { color:#6e6e73; font-size: 11px; }
          section.cluster { border: 1px solid #e2e2e6; border-radius: 10px; padding: 14px 16px; margin-bottom: 18px; }
          h2 { font-size: 15px; margin: 0 0 10px; }
          .meta { display:flex; gap: 24px; flex-wrap: wrap; margin-bottom: 12px; }
          .meta .lbl { display:block; font-size: 10px; text-transform: uppercase; color:#8e8e93; letter-spacing:.04em; }
          .path { font-family: ui-monospace, Menlo, monospace; font-size: 11px; color:#3a3a3c; word-break: break-all; }
          .hash { font-family: ui-monospace, Menlo, monospace; font-size: 10px; color:#8e8e93; word-break: break-all; }
          table { width:100%; border-collapse: collapse; }
          th, td { text-align:left; padding: 5px 8px; border-bottom: 1px solid #ececf0; vertical-align: top; }
          th { font-size: 10px; text-transform: uppercase; color:#8e8e93; letter-spacing:.04em; }
          td.action { font-weight: 700; font-size: 11px; white-space: nowrap; }
          td.num { white-space: nowrap; text-align: right; }
          tr.move td.action { color:#0a84ff; }
          tr.del  td.action { color:#ff3b30; }
          tr.keep td.action { color:#8e8e93; }
          tr.copy td.action { color:#34c759; }
          tr.err  td.action { color:#ff9500; }
          @media (prefers-color-scheme: dark) {
            body { color:#f5f5f7; } .summary { background:#1c1c1e; } section.cluster { border-color:#3a3a3c; }
            .path { color:#aeaeb2; } th,td { border-color:#2c2c2e; }
          }
        </style></head><body>
          <h1>FileLister — Merge Log</h1>
          <div class="sub">\(esc(when)) · \(esc(report.mode)) · v\(esc(report.appVersion))</div>
          <div class="summary">
            <div><b>\(report.clusters.count)</b><span>folder cluster(s)</span></div>
            <div><b>\(report.totalFilesMoved)</b><span>files moved/copied</span></div>
            <div><b>\(report.totalFilesRemoved)</b><span>duplicates removed</span></div>
            <div><b>\(byteString(report.totalBytesRemoved))</b><span>space reclaimed</span></div>
            <div><b>\(report.errorCount)</b><span>error(s)</span></div>
          </div>
          \(rows)
        </body></html>
        """
    }

    private static func cssClass(_ action: String) -> String {
        if action.hasPrefix("MOVED") { return "move" }
        if action.hasPrefix("COPIED") || action == "FOLDER_COPIED" { return "copy" }
        if action == "TRASHED" || action == "FOLDER_TRASHED" { return "del" }
        if action == "ERROR" { return "err" }
        return "keep"
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func byteString(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024, mb = kb / 1024, gb = mb / 1024
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        if mb >= 1 { return String(format: "%.2f MB", mb) }
        if kb >= 1 { return String(format: "%.1f KB", kb) }
        return "\(bytes) B"
    }
}

// Renders a log report to a paginated PDF using AppKit print-to-PDF.
// Fully offline (no WebKit), sandbox-safe. Runs on the main thread.
enum LogPDFRenderer {
    static func render(_ report: MergeLogReport, to url: URL) {
        DispatchQueue.main.async {
            let pageWidth: CGFloat = 612, margin: CGFloat = 36   // US Letter, 0.5" margins
            let textWidth = pageWidth - margin * 2

            let textView = NSTextView(frame: CGRect(x: 0, y: 0, width: textWidth, height: 100))
            textView.drawsBackground = true
            textView.backgroundColor = .white
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.textContainer?.containerSize = CGSize(width: textWidth, height: .greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
            textView.textStorage?.setAttributedString(attributedReport(report))
            if let tc = textView.textContainer, let lm = textView.layoutManager {
                lm.ensureLayout(for: tc)
                let used = lm.usedRect(for: tc)
                textView.frame = CGRect(x: 0, y: 0, width: textWidth, height: ceil(used.height) + 8)
            }

            let info = NSPrintInfo()
            info.paperSize = NSSize(width: pageWidth, height: 792)
            info.topMargin = margin; info.bottomMargin = margin
            info.leftMargin = margin; info.rightMargin = margin
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

            let op = NSPrintOperation(view: textView, printInfo: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            op.run()
        }
    }

    private static func attributedReport(_ report: MergeLogReport) -> NSAttributedString {
        let s = NSMutableAttributedString()
        func add(_ text: String, font: NSFont, color: NSColor = .black, after: CGFloat = 2) {
            let p = NSMutableParagraphStyle(); p.paragraphSpacing = after; p.lineBreakMode = .byCharWrapping
            s.append(NSAttributedString(string: text + "\n",
                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p]))
        }
        let mono9 = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let df = DateFormatter(); df.dateStyle = .long; df.timeStyle = .medium

        add("FileLister — Operation Log", font: .boldSystemFont(ofSize: 18))
        add("\(df.string(from: report.timestamp))  ·  \(report.mode)  ·  v\(report.appVersion)",
            font: .systemFont(ofSize: 10), color: .darkGray, after: 10)
        add("Summary: \(report.clusters.count) group(s) · \(report.totalFilesMoved) moved/copied · \(report.totalFilesRemoved) removed · \(byteString(report.totalBytesRemoved)) reclaimed · \(report.errorCount) error(s)",
            font: .systemFont(ofSize: 11), after: 14)

        for c in report.clusters {
            add(c.resultName, font: .boldSystemFont(ofSize: 13), after: 1)
            add("keep: \(c.keepFolder)", font: .systemFont(ofSize: 9), color: .gray)
            if !c.otherFolders.isEmpty {
                add("others: \(c.otherFolders.joined(separator: ", "))", font: .systemFont(ofSize: 9), color: .gray)
            }
            for e in c.entries {
                let color: NSColor
                if e.action.hasPrefix("MOVED") { color = .systemBlue }
                else if e.action.hasPrefix("COPIED") || e.action == "FOLDER_COPIED" { color = .systemGreen }
                else if e.action == "TRASHED" || e.action == "FOLDER_TRASHED" { color = .systemRed }
                else if e.action == "ERROR" { color = .systemOrange }
                else { color = .darkGray }
                add("  [\(e.action)] \(e.fileName)  ·  \(byteString(e.sizeBytes))", font: mono9, color: color, after: 0)
                add("      from: \(e.sourcePath)", font: mono9, color: .gray, after: 0)
                if !e.destinationPath.isEmpty { add("      to:   \(e.destinationPath)", font: mono9, color: .gray, after: 0) }
                if !e.sha256.isEmpty { add("      \(e.sha256)", font: mono9, color: .lightGray, after: 0) }
            }
            add("", font: .systemFont(ofSize: 6), after: 8)
        }
        return s
    }

    private static func byteString(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024, mb = kb / 1024, gb = mb / 1024
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        if mb >= 1 { return String(format: "%.2f MB", mb) }
        if kb >= 1 { return String(format: "%.1f KB", kb) }
        return "\(bytes) B"
    }
}
