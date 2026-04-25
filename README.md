# FileLister 📁🛡️

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg?style=flat)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**FileLister** is a native macOS application designed to help you regain control of your storage. It recursively scans directories, identifies duplicate files using high-precision cryptographic hashing, and provides a safe, intuitive interface for cleanup.

---

## 🚀 Key Features

### 🔍 Flexible Scanning
*   **Total Recursion**: Scan any local folder or external drive (USB/Thunderbolt) with ease.
*   **Deep Scan (SHA-256)**: Compares file content byte-by-byte for 100% accurate duplicate detection — goes beyond name and size.
*   **Media Filtering**: Toggle "Media Only" to focus on high-impact files like photos and videos.
*   **Hidden Files**: Optionally include or skip system files (e.g., `.DS_Store`) via the "No Hidden" toggle.
*   **Extension Filter**: Filter results by any file type by typing an extension (e.g., `xls`, `jpg`, `pdf`).

### 🛡️ Smart Duplicate Management
*   **Safety Lock**: Prevents the accidental deletion of the last remaining copy of any file.
*   **Ignore Flag**: Mark individual files as "Ignored" — they are excluded from automatic cleanup and highlighted in the UI.
*   **Auto-Selection Rules**: Automatically pre-select which copies to keep within each group:
    *   **Keep Oldest** — Preserves the earliest created file.
    *   **Keep Newest** — Preserves the most recently created file.
    *   **Keep Largest** — Preserves the highest-quality/largest copy (useful for media).
*   **macOS Trash Integration**: Files are moved to the system Trash rather than permanently deleted.
*   **Deletion Confirmation**: Both individual and batch deletions require explicit confirmation, showing the **number of files** and **space recovered** before proceeding.

### 📋 Action Logging
*   **Session Log**: When the "Log" feature is enabled and a folder is selected, a timestamped log file is automatically created the moment you delete files.
*   **Deletion-Only Logging**: Only actual deletions (single or batch) are recorded — browsing and filtering do not generate logs.
*   **Log Naming**: Files follow the format `FileLister_Log_yyyy_MM_dd_HH_mm_ss.txt`.

### 🎨 Modern Experience
*   **Quick Look Integration**: Preview any file directly within the app using the **Space Bar**, exactly like in Finder.
*   **Dynamic Sorting**: Order groups by number of copies or total size (ascending/descending).
*   **Tooltips**: Hover over any filter or button to see a concise description of what it does.
*   **Real-time Progress**: Visual progress bar and status bar updates during scanning and deep analysis.
*   **Adaptive Layout**: Minimum window size optimized to ensure all filters and controls remain visible on a single line.
*   **Enhanced Empty States**: Clear, large visual cues when waiting for a folder selection or when no duplicates are found.

---

## 🛠️ Usage

1.  **Select Source**: Click **"Select..."** to choose the folder or disk. The scan will **automatically start** upon selection.
2.  **Configure Filters**:
    *   Toggle **Deep Scan** for maximum accuracy.
    *   Toggle **Media** to focus on photos/videos.
    *   Toggle **No Hidden** to exclude system files.
    *   Click **Log** to select a folder where deletion logs will be saved.
    *   Type in the **Ext** box to filter by a specific file extension.
3.  **Audit**: Results appear automatically. You can also manually re-trigger by clicking **"Search for Duplicates"**.
4.  **Review Results**:
    *   Browse duplicate groups sorted by **Copies** or **Size**.
    *   Select an **Auto-Selection Rule** to automatically identify the copy to keep.
    *   Use the **Space Bar** to preview a file.
    *   Check **Ignore** on any file to exclude it from cleanup.
5.  **Cleanup**:
    *   Click the **Trash Icon** on individual files for single-file deletion.
    *   Click **"Clean All Duplicates (N)"** to batch-delete all marked duplicates.
    *   Confirm the dialog, which shows the file count and space to be recovered.

---

## ⚙️ Performance & Security

*   **CryptoKit**: Leverages Apple's `CryptoKit` for high-performance, energy-efficient SHA-256 hashing.
*   **Concurrency**: Uses `DispatchQueue` to keep the UI responsive during intensive disk I/O.
*   **Sandbox Aware**: Designed to respect macOS security protocols. Ensure **"User Selected File"** permissions are set to **Read/Write** in Xcode (`Signing & Capabilities`).

---

## 👨‍💻 Installation

1.  Clone the repository.
2.  Open `FileLister.xcodeproj` in Xcode 15 or later.
3.  Build and Run (`Cmd + R`).

---

## 🗺️ Roadmap

*   [x] **Recursive Scanning** with Quick Scan and Deep Scan (SHA-256) modes.
*   [x] **Safety Lock** — prevents deletion of the last copy of any file.
*   [x] **Batch Cleanup** — "Clean All Duplicates" button with confirmation dialog showing file count and space recovered.
*   [x] **Premium Features** — License key system (XXXX-YYYY-ZZZZ-WWWW) with trial limits.
*   [x] **Media Filtering** — Focus on photos, videos and audio files.
*   [x] **Extension Filter** — Filter results by any file type (e.g., `xls`, `pdf`).
*   [x] **Ignore Flag** — Exclude individual files from auto-cleanup with visual highlighting.
*   [x] **Auto-Selection Rules** — Keep Oldest / Keep Newest / Keep Largest per group.
*   [x] **Action Log** — Timestamped deletion log saved to a user-selected folder.
*   [x] **Tooltips** — Hover descriptions on all filters and controls.
*   [x] **Deletion Confirmation** — File count and space savings shown before any batch action.
*   [x] **Auto-Scan on Selection** — Immediate scan initiation upon choosing a source folder.
*   [x] **Optimized UI Layout** — Guaranteed single-line visibility for all toolbars and filters.
*   [ ] **Public Release** — Pre-compiled and notarized binaries in [Releases](https://github.com/luisdanielsilva/FileLister/releases).

---

*Built with ❤️ for macOS users by Luís Silva.*

---

### 🌐 Project Ecosystem
Looking for the **Single Use Apps** web portal and license generation engine?
The web infrastructure has been moved to its own dedicated repository: [SingleUseApps-Portal](https://github.com/luisdanielsilva/SingleUseApps-Portal)
