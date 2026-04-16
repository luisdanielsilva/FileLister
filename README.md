# FileLister 📁🛡️

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat)](https://developer.apple.com/swift/)
[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg?style=flat)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**FileLister** is a native macOS application designed to help you regain control of your storage. It recursively scans directories, identifies duplicate files using high-precision cryptographic hashing, and provides a safe, intuitive interface for cleanup.

---

## 🚀 Key Features

### 🔍 Deep & Multi-Threaded Scanning
*   **Total Recursion**: Scan any local folder or external drive (USB/Thunderbolt) with ease.
*   **Media Filtering**: Toggle "Media Only" to focus on high-impact files like photos and videos.
*   **Hidden Files**: Optionally include or skip system files (e.g., `.DS_Store`).

### 🛡️ Smart Duplicate Management
*   **SHA-256 Analysis**: Uses mathematical SHA-256 hashing to ensure files are 100% identical, going beyond just name and size.
*   **Safety Lock**: Our unique "Safety Lock" mechanism prevents the accidental deletion of the last remaining copy of a file.
*   **macOS Trash Integration**: For extra peace of mind, files are moved to the system Trash rather than being permanently deleted.

### 🎨 Modern Experience
*   **Quick Look Integration**: Preview any duplicate directly within the app using the **Space Bar**, exactly like in Finder.
*   **Dynamic Sorting**: Order groups by the number of copies or total size.
*   **Real-time Progress**: Visual feedback and status bar updates during deep analysis.

---

## 🛠️ Usage

1.  **Select Source**: Click **"Select..."** to choose the folder or disk you want to audit.
2.  **Toggle Analysis**: Choose between a quick scan (Name + Size) or a **Deep Scan** (SHA-256).
3.  **Search**: Click **"Search for Duplicates"** to start the scan immediately.
4.  **Audit & Cleanup**:
    *   Browse the identified duplicate groups.
    *   Use **Space Bar** to preview a file.
    *   Click the **Trash Icon** to safely move duplicates to the Trash.

---

## ⚙️ Performance & Security

*   **CryptoKit**: Leverages Apple's `CryptoKit` for high-performance, energy-efficient hashing.
*   **Concurrency**: Uses `DispatchQueue` to ensure the interface remains responsive even during intensive disk I/O.
*   **Sandbox Aware**: Designed to respect macOS security protocols. Ensure "User Selected File" permissions are set to **Read/Write** in Xcode.

---

## 👨‍💻 Installation

1.  Clone the repository.
2.  Open `FileLister.xcodeproj` in Xcode 15 or later.
3.  Build and Run (`Cmd + R`).

---

## 🗺️ Roadmap (Future Improvements)

We are constantly planning new features. Here are the next steps:

*   [x] **Batch Cleanup**: Added a "Clean All Duplicates" button with a safety confirmation dialog.
*   [x] **Premium Features**: Implemented a license key system (XXXX-YYYY-ZZZZ-WWWW) with trial limits and registration requirements.
*   [ ] **Public Release**: Provide pre-compiled and notarized binaries in the [Releases](https://github.com/luisdanielsilva/FileLister/releases) section so any user can download and run FileLister instantly without needing Xcode or technical knowledge.
*   [ ] **Action Log**: Keep a detailed log of all files found and safely eliminated during the cleanup process.
*   [x] **Detailed Progress Monitoring**: Display granular file reading progress during hashing and verification.
*   [x] **Final Binary Verification**: Added a mandatory byte-by-byte content comparison before any deletion to guarantee 100% identity.

---

*Built with ❤️ for macOS users by Luís Silva.*

---

### 🌐 Project Ecosystem
Looking for the **Single Use Apps** web portal and license generation engine? 
The web infrastructure has been moved to its own dedicated repository: [SingleUseApps-Portal](https://github.com/luisdanielsilva/SingleUseApps-Portal)
