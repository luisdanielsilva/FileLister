import SwiftUI

enum HelpSection: String, CaseIterable, Identifiable {
    case welcome          = "Welcome to FileLister"
    case whatsNew         = "Modes & What's New"
    case atAGlance        = "FileLister at a Glance"
    case folderDuplicates = "Folder Duplicates & Merging"
    case photos           = "Duplicate Photos"
    case oneDrive         = "OneDrive (Cloud)"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .welcome:          return "star.circle.fill"
        case .whatsNew:         return "sparkles"
        case .atAGlance:        return "rectangle.on.rectangle"
        case .folderDuplicates: return "folder.badge.questionmark"
        case .photos:           return "photo.on.rectangle.angled"
        case .oneDrive:         return "cloud"
        }
    }
}

struct HelpView: View {
    @State private var selection: HelpSection? = .welcome

    var body: some View {
        NavigationSplitView {
            List(HelpSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
                    .padding(.vertical, 2)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            ScrollView {
                Group {
                    switch selection {
                    case .welcome:          WelcomeSection()
                    case .whatsNew:         WhatsNewSection()
                    case .atAGlance:        AtAGlanceSection()
                    case .folderDuplicates: FolderDuplicatesSection()
                    case .photos:           PhotosHelpSection()
                    case .oneDrive:         OneDriveHelpSection()
                    case nil:               WelcomeSection()
                    }
                }
                .padding(32)
                .frame(maxWidth: 700, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 560)
    }
}

// ── Welcome ───────────────────────────────────────────────────────────────────

private struct WelcomeSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {

            // Header
            HStack(spacing: 16) {
                Image(systemName: "checkmark.rectangle.stack.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to FileLister")
                        .font(.largeTitle).fontWeight(.bold)
                    Text("Version 1.2.0  ·  macOS Duplicate Finder")
                        .font(.subheadline).foregroundColor(.secondary)
                }
            }

            Divider()

            // About
            helpGroup(title: "About the App") {
                Text("FileLister is a fast, privacy-friendly macOS utility that scans any folder on your Mac and finds duplicate files — files that share the same content regardless of their name or location. All processing happens entirely on-device; no files or metadata are ever sent to the internet.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Whether you're cleaning up a Downloads folder, a photo library, or a project archive, FileLister shows you exactly which files are redundant and lets you recycle them safely — always keeping at least one copy per group.")
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            Divider()

            // Features
            helpGroup(title: "Features") {
                featureRow(icon: "magnifyingglass.circle.fill", color: .blue,
                           title: "Instant Duplicate Detection",
                           body: "Automatically scans after you select a folder. No extra button press needed.")
                featureRow(icon: "shield.checkerboard", color: .purple,
                           title: "Deep Scan (SHA-256)",
                           body: "Byte-level file comparison using SHA-256 hashing ensures zero false positives. Toggle it on for thorough verification beyond filename and size matching.")
                featureRow(icon: "photo.on.rectangle", color: .orange,
                           title: "Media Filter",
                           body: "Restrict the scan to media files only (images, videos, audio) to focus on the files that take up the most space.")
                featureRow(icon: "eye.slash", color: .gray,
                           title: "Skip Hidden Files",
                           body: "Ignore macOS hidden files and system folders (files starting with '.') to reduce noise in the results.")
                featureRow(icon: "arrow.up.arrow.down", color: .teal,
                           title: "Smart Sorting",
                           body: "Sort duplicate groups by number of copies or by file size, ascending or descending, to prioritise the most impactful clean-ups.")
                featureRow(icon: "trash.fill", color: .red,
                           title: "Safe Deletion",
                           body: "Files are moved to Trash — never permanently deleted. One file per group is always locked and protected so you never lose your only copy.")
                featureRow(icon: "sparkles", color: .yellow,
                           title: "Space Recovery Tracking",
                           body: "The status bar shows potential savings (space you could free) and actual recoveries (space already freed this session).")
                featureRow(icon: "eye", color: .indigo,
                           title: "Quick Look Preview",
                           body: "Select any file in the list and press Space to preview it instantly using macOS Quick Look — no need to open Finder.")
                featureRow(icon: "lock.fill", color: .green,
                           title: "Trial & License System",
                           body: "FileLister is free to use with up to 15 file deletions. Unlock unlimited access with a one-time license key.")
            }

            Divider()

            // System requirements
            helpGroup(title: "System Requirements") {
                requirementRow(label: "Operating System", value: "macOS 13 Ventura or later")
                requirementRow(label: "Architecture",     value: "Apple Silicon (arm64) and Intel (x86_64)")
                requirementRow(label: "Disk Space",       value: "Less than 5 MB")
                requirementRow(label: "Permissions",      value: "Read access to the folder you want to scan. No special entitlements required.")
                requirementRow(label: "Internet",         value: "Not required. The app works fully offline.")
            }
        }
    }
}

// ── At a Glance ───────────────────────────────────────────────────────────────

private struct AtAGlanceSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {

            VStack(alignment: .leading, spacing: 4) {
                Text("FileLister at a Glance")
                    .font(.largeTitle).fontWeight(.bold)
                Text("A tour of the interface and every control explained.")
                    .font(.subheadline).foregroundColor(.secondary)
            }

            Divider()

            // Main window — empty state
            screenshotBlock(
                name: "fl_main",
                caption: "Main window — ready state. No folder selected yet."
            )

            Divider()

            // Toolbar
            glanceGroup(
                title: "① Top Bar — Folder Selection & Scan",
                icon: "rectangle.topthird.inset.filled"
            ) {
                glanceItem(label: "Search for Duplicates button",
                           body: "Starts the duplicate scan for the currently selected folder. The button is disabled until a folder is chosen. While scanning it becomes a Stop button that cancels the operation mid-way.")
                glanceItem(label: "Folder path display",
                           body: "Shows the full path of the selected folder. Truncates in the middle if the path is too long so both the drive root and the deepest folder name remain visible.")
                glanceItem(label: "Select… button",
                           body: "Opens the standard macOS folder picker. Once you confirm a folder the scan starts automatically — no need to press the Search button separately.")
            }

            Divider()

            // Options bar
            glanceGroup(
                title: "② Options Bar — Scan Behaviour & Sorting",
                icon: "slider.horizontal.3"
            ) {
                glanceItem(label: "Deep Scan toggle",
                           body: "When enabled, FileLister reads every file in full and computes a SHA-256 fingerprint. This is the most accurate mode and produces zero false positives. Slightly slower on large folders. When disabled, FileLister matches files by size and name only — faster but may miss some duplicates.")
                glanceItem(label: "Media toggle",
                           body: "Restricts the scan to media file extensions: JPEG, PNG, HEIC, GIF, MP4, MOV, MP3, AAC, FLAC and others. Ideal for cleaning photo libraries or video archives.")
                glanceItem(label: "No Hidden toggle",
                           body: "Skips files and folders whose names begin with a dot (.) — these are typically macOS or application config files and are usually not user-facing duplicates.")
                glanceItem(label: "Sort by Copies / Size",
                           body: "Two sort buttons let you order the results list. Click once to sort ascending; click again to reverse the order. An arrow indicator shows the active sort direction. Copies sorts by how many duplicates exist in each group; Size sorts by the individual file size.")
                glanceItem(label: "Clean All Duplicates button",
                           body: "Appears only after a scan finds results. Moves all detected duplicates to Trash in one action, keeping exactly one file per group safe. Requires a valid license key.")
            }

            Divider()

            // Progress
            glanceGroup(
                title: "③ Progress Bars — Scan Progress",
                icon: "chart.bar.fill"
            ) {
                glanceItem(label: "Green progress bar",
                           body: "Overall scan progress from 0 to 100 %. Reflects how many files have been catalogued out of the total discovered.")
                glanceItem(label: "Blue progress bar (thin)",
                           body: "Per-file hashing progress. Visible only during Deep Scan when a large individual file is being read. Disappears automatically once the file hash is complete.")
            }

            Divider()

            // Results window screenshot
            screenshotBlock(
                name: "fl_results",
                caption: "Main window — after a scan completes, showing 94 duplicate groups with potential savings and recoveries in the status bar."
            )

            Divider()

            // Results list
            glanceGroup(
                title: "④ Duplicate Groups List — Results",
                icon: "list.bullet.rectangle"
            ) {
                glanceItem(label: "Group header",
                           body: "Each group shows a file-type icon, the filename shared by all duplicates, the file size, and a badge indicating how many copies remain active. An orange badge means duplicates are still present; a green badge means only one copy remains (fully cleaned).")
                glanceItem(label: "File path row",
                           body: "Lists the full path of each duplicate. Click a row to select it (highlighted in blue). Strike-through red text means the file has already been moved to Trash this session.")
                glanceItem(label: "Open in Finder button (folder icon)",
                           body: "Reveals the file's parent folder in Finder without opening the file itself. Useful for understanding where duplicates are stored.")
                glanceItem(label: "Delete button (trash icon)",
                           body: "Moves this specific duplicate to Trash. Only active when the group still has more than one copy — the last remaining file is protected and shows a green lock icon instead.")
                glanceItem(label: "Space bar — Quick Look",
                           body: "With a file row selected, press Space to open macOS Quick Look and preview the file content without leaving FileLister.")
                glanceItem(label: "Empty state",
                           body: "When no folder is selected the centre of the window shows a large folder icon with 'Select a folder to begin'. After a clean scan with no duplicates it shows a checkmark with 'No duplicates found'.")
            }

            Divider()

            // Status bar
            glanceGroup(
                title: "⑤ Status Bar — Live Feedback",
                icon: "info.circle.fill"
            ) {
                glanceItem(label: "Status indicator dot",
                           body: "A small coloured circle gives an at-a-glance system state: grey = idle, green = scanning, blue = completed or file moved to Trash, red = error.")
                glanceItem(label: "Status message",
                           body: "Plain-language description of what FileLister is currently doing, e.g. 'Scanning…', 'Completed — 12 duplicate groups found', or a specific error message.")
                glanceItem(label: "Potential Savings",
                           body: "Total size of all duplicate files that could be removed (one file per group is excluded as the keeper). Updates live as you delete files during the session.")
                glanceItem(label: "Recoveries",
                           body: "Cumulative space already freed this session by moving duplicates to Trash. Shown in green.")
                glanceItem(label: "Trial Mode indicator",
                           body: "Visible when the app is not licensed. Shows how many of the 15 free deletions have been used and provides a quick link to open the license registration sheet.")
            }

            Divider()

            // Help window screenshot
            screenshotBlock(
                name: "fl_help",
                caption: "Help window — accessible from Help › FileLister Help or ⌘?."
            )

            Divider()

            // App menu
            glanceGroup(
                title: "⑥ Menu Bar",
                icon: "menubar.rectangle"
            ) {
                glanceItem(label: "FileLister › About FileLister",
                           body: "Opens the standard macOS About panel showing the app version and credits.")
                glanceItem(label: "FileLister › License Key… (⌘L)",
                           body: "Opens the license registration sheet where you can enter a key to unlock unlimited access.")
                glanceItem(label: "Help › FileLister Help",
                           body: "Opens this Help window.")
            }
        }
    }
}

// ── Folder Duplicates & Merging ───────────────────────────────────────────────

private struct FolderDuplicatesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {

            VStack(alignment: .leading, spacing: 4) {
                Text("Folder Duplicates & Merging")
                    .font(.largeTitle).fontWeight(.bold)
                Text("How FileLister finds duplicate folders, groups them, and merges them — and why similar-looking folders are sometimes kept apart.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            helpGroup(title: "What it does") {
                Text("With the Folders option enabled, FileLister looks beyond individual files and finds folders that contain largely the same files. Instead of listing hundreds of separate duplicate files, it shows you the folders themselves so you can merge and clean them in one step.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            helpGroup(title: "How folders are matched") {
                featureRow(icon: "shield.checkerboard", color: .purple,
                           title: "Byte-identical content (SHA-256)",
                           body: "Two files count as \"the same\" only when their contents are byte-for-byte identical, verified with a SHA-256 fingerprint. Filenames are ignored for matching — only the actual bytes matter.")
                featureRow(icon: "percent", color: .blue,
                           title: "Match ratio",
                           body: "For any two folders, the match ratio is the number of shared (byte-identical) files divided by the file count of the smaller folder. 100% means the smaller folder is fully contained in the other.")
                featureRow(icon: "slider.horizontal.3", color: .teal,
                           title: "The Match threshold",
                           body: "The Match slider sets how similar folders must be to be treated as duplicates (50%–100%). Folders are only grouped when their match ratio meets or exceeds this threshold. Lower it to catch looser matches; raise it to be stricter.")
            }

            Divider()

            helpGroup(title: "Clustering — folders are grouped, not paired") {
                Text("When three or more folders are all similar to one another, FileLister groups them into a single cluster rather than listing every pair separately. Each cluster has one keep folder (the one with the most files) and one or more other folders that merge into it. This is why a set of near-identical folders appears as a single result row, however many folders are involved.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            helpGroup(title: "Why similar folders are sometimes kept separate") {
                Text("You may see two or more result groups that share the same folder name — for example three results all called \"My Project\". This is intentional and correct:")
                    .fixedSize(horizontal: false, vertical: true)
                calloutRow(icon: "checkmark.seal.fill", color: .green,
                           text: "A shared folder name does not make folders duplicates. FileLister compares the actual file contents, not the names.")
                calloutRow(icon: "doc.on.doc", color: .orange,
                           text: "Different versions of the same project usually share filenames but have different bytes inside (an edited drawing, a re-exported file, a newer build). Those files are not byte-identical, so they don't count toward the match ratio.")
                calloutRow(icon: "scissors", color: .blue,
                           text: "If the shared (byte-identical) portion falls below your Match threshold, the folders stay in separate clusters — each becomes its own result.")
                calloutRow(icon: "lock.shield", color: .purple,
                           text: "This is the safe behaviour: it prevents different versions from being fused into one folder, which could overwrite or hide the version you actually wanted to keep.")
                Text("If you want looser, version-tolerant grouping, lower the Match threshold — but be aware this starts grouping folders that are not byte-identical, so review the preview before merging.")
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            Divider()

            helpGroup(title: "What a merge does") {
                Text("Merging a cluster keeps one folder and brings the others' content into it:")
                    .fixedSize(horizontal: false, vertical: true)
                calloutRow(icon: "arrow.left.circle.fill", color: .blue,
                           text: "Files that exist only in the other folders are moved into the keep folder. If a name already exists there, the incoming file is renamed (e.g. \"file_moved_from_OtherFolder.ext\") so nothing is overwritten.")
                calloutRow(icon: "xmark.circle.fill", color: .red,
                           text: "Files that are already byte-identical to a copy in the keep folder are redundant and are removed (the other folders are sent to Trash once their unique files have been moved out).")
                calloutRow(icon: "minus.circle", color: .gray,
                           text: "Files only in the keep folder are left unchanged.")
                Text("Press Space on a selected folder result to preview every action (Keep · Operations · Merge & Clean) before committing.")
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            Divider()

            helpGroup(title: "Merge options") {
                featureRow(icon: "arrow.triangle.merge", color: .indigo,
                           title: "Merge & Clean / Merge All",
                           body: "Performs the merge in place: other folders are sent to Trash after their unique files move into the keep folder. Nothing is permanently deleted — everything goes to the Trash.")
                featureRow(icon: "rectangle.stack.badge.play", color: .indigo,
                           title: "Review One-by-One",
                           body: "Steps through each cluster so you can approve (Return), skip (→), or cancel (Esc). Approved merges run together at the end; cancelling applies nothing.")
                featureRow(icon: "doc.on.doc", color: .green,
                           title: "Copy to new folder",
                           body: "Non-destructive mode. Instead of changing your originals, FileLister writes the merged result into a new folder you choose, leaving every original folder exactly as it was.")
                featureRow(icon: "pencil", color: .orange,
                           title: "Rename kept folder",
                           body: "When on, the kept folder is renamed with a merged tag. When off, it keeps its original name and simply gains the merged files. (Copy-to-new-folder always names its new folder with the merged tag.)")
            }
        }
    }
}

// ── Modes & What's New ────────────────────────────────────────────────────────

private struct WhatsNewSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Modes & What's New").font(.largeTitle).fontWeight(.bold)
                Text("FileLister now works in three modes, on local folders or OneDrive.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Divider()

            helpGroup(title: "Three modes") {
                featureRow(icon: "doc.on.doc", color: .blue, title: "Files",
                           body: "Find byte-identical duplicate files and recycle the extras, keeping one copy safe.")
                featureRow(icon: "folder.badge.questionmark", color: .indigo, title: "Folders",
                           body: "Find duplicate folders (clustered), preview the merge, and combine them — in place or as a non-destructive copy to a new folder.")
                featureRow(icon: "photo.on.rectangle.angled", color: .orange, title: "Photos",
                           body: "Find visually similar photos (not just identical), auto-pick the best copy, and clean up or export the keepers.")
            }
            Divider()

            helpGroup(title: "Local or OneDrive") {
                Text("A source switch at the top lets you scan your local folders or your OneDrive account. Choose multiple local folders (Across-all or Within-each), or connect OneDrive and pick which cloud folders to scan.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()

            helpGroup(title: "Recent additions") {
                featureRow(icon: "rectangle.stack.badge.play", color: .indigo, title: "Review One-by-One",
                           body: "Step through each folder cluster and approve, skip, or cancel before anything is merged.")
                featureRow(icon: "doc.on.doc", color: .green, title: "Safe copy & keeper export",
                           body: "Merge into a new folder, or copy photo keepers elsewhere — originals untouched, structure preserved.")
                featureRow(icon: "doc.text.magnifyingglass", color: .purple, title: "Operation logs (JSON · HTML · PDF)",
                           body: "Every delete, merge, copy and cloud action writes a detailed report with paths, sizes and hashes.")
                featureRow(icon: "arrow.uturn.backward", color: .blue, title: "Undo & Operation History",
                           body: "Undo the last operation (⌘Z) restores from Trash. Operation History (⌘Y) browses every past report.")
                featureRow(icon: "cloud", color: .blue, title: "OneDrive",
                           body: "Connect your Microsoft account and find/clean duplicate files in chosen OneDrive folders.")
            }
        }
    }
}

// ── Duplicate Photos ──────────────────────────────────────────────────────────

private struct PhotosHelpSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duplicate Photos").font(.largeTitle).fontWeight(.bold)
                Text("Find photos that look the same even when the files differ.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Divider()
            helpGroup(title: "How it finds similar photos") {
                Text("Exact (byte-identical) duplicates are found in Files mode. Photos mode goes further: it compares the actual image content using perceptual hashing (a fast dHash pre-filter, then a pHash check), so it catches re-exports, resizes, recompression, crops and format conversions that byte comparison misses.")
                    .fixedSize(horizontal: false, vertical: true)
                calloutRow(icon: "slider.horizontal.3", color: .teal,
                           text: "The Similarity slider controls how alike photos must be to group. Optional EXIF corroboration and metadata expansion (same time / GPS / camera) refine the groups.")
            }
            Divider()
            helpGroup(title: "Best copy & cleanup") {
                calloutRow(icon: "star.fill", color: .green,
                           text: "Each group auto-picks a keeper using your priority (Settings ▸ Photos): resolution, file size, date, RAW, GPS. You can override which photo is kept.")
                calloutRow(icon: "eye", color: .blue,
                           text: "Select a photo and press Space for Quick Look; use ← → to move between photos.")
                calloutRow(icon: "trash", color: .red,
                           text: "Delete the non-keepers (with a confirmation showing the comparison and space saved), or copy the keepers to another folder, replicating their structure.")
            }
        }
    }
}

// ── OneDrive ──────────────────────────────────────────────────────────────────

private struct OneDriveHelpSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OneDrive (Cloud)").font(.largeTitle).fontWeight(.bold)
                Text("Find and clean duplicate files directly in your OneDrive.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Divider()

            helpGroup(title: "Connecting") {
                Text("Switch the source toggle (top right) from Local to OneDrive, then click Connect OneDrive. You'll sign in with your Microsoft account in your default browser; FileLister never sees your password. Your sign-in is remembered securely in the macOS Keychain.")
                    .fixedSize(horizontal: false, vertical: true)
                calloutRow(icon: "network", color: .blue,
                           text: "OneDrive is the only feature that uses the internet. All local scanning stays fully offline.")
            }
            Divider()

            helpGroup(title: "Choosing folders") {
                Text("After connecting, pick which OneDrive folders to scan. Browse your cloud folders, add one or more (or the entire drive), and remove them anytime — just like selecting local folders.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()

            helpGroup(title: "Finding & cleaning duplicates (Files)") {
                calloutRow(icon: "shield.checkerboard", color: .purple,
                           text: "Files are matched by OneDrive's own content hash (quickXorHash) — no downloads needed to find duplicates.")
                calloutRow(icon: "eye", color: .blue,
                           text: "Select a file and press Space to preview it (the file is downloaded on demand, with a progress ring); ← → move between files.")
                calloutRow(icon: "trash", color: .red,
                           text: "Delete individual copies or all duplicates. Deleted files go to the OneDrive recycle bin (recoverable there). At least one copy per group is always kept.")
                calloutRow(icon: "doc.text", color: .gray,
                           text: "Cloud actions are logged like local ones (JSON / HTML / PDF).")
            }
            Divider()

            helpGroup(title: "Scan limits & notes") {
                calloutRow(icon: "gauge", color: .orange,
                           text: "To keep the first scan fast, scanning is capped (Settings ▸ OneDrive — default 5000 files / 5 GB). Raise or remove the limit there.")
                calloutRow(icon: "exclamationmark.triangle", color: .secondary,
                           text: "Folders and Photos on OneDrive are coming in a later update. Cloud deletes can't be undone from the app (restore them from the OneDrive recycle bin).")
            }
        }
    }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

private func helpGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
        content()
    }
}

private func glanceGroup<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundColor(.primary)
        content()
    }
}

private func calloutRow(icon: String, color: Color, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundColor(color)
            .frame(width: 20)
        Text(text)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func featureRow(icon: String, color: Color, title: String, body: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 20))
            .foregroundColor(color)
            .frame(width: 28)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.semibold)
            Text(body).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func requirementRow(label: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 0) {
        Text(label)
            .fontWeight(.medium)
            .frame(width: 160, alignment: .leading)
        Text(value)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private func screenshotBlock(name: String, caption: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Image(name)
            .resizable()
            .scaledToFit()
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        Text(caption)
            .font(.caption)
            .foregroundColor(.secondary)
            .italic()
    }
}

private func glanceItem(label: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(label).fontWeight(.semibold).foregroundColor(.primary)
        Text(body).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(6)
}
