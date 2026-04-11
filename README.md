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

## 🗺️ Roadmap (Próximas Melhorias)

Estamos constantemente a planear novas funcionalidades. Aqui estão os próximos passos:

*   [ ] **Limpeza em Lote**: Adicionar um botão "Limpar Tudo" para apagar todos os duplicados de um grupo de uma só vez, mantendo apenas o exemplar original.
*   [ ] **Funcionalidades Premium**: Implementar um sistema de ativação por chave para disponibilizar recursos extras na aplicação.
*   [ ] **Downloads Diretos**: Disponibilizar executáveis pré-compilados na secção de [Releases](https://github.com/luisdanielsilva/FileLister/releases) do GitHub para que não seja necessário compilar o código para usar a app.

---

*Built with ❤️ for macOS users by Luís Silva.*
