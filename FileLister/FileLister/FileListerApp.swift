import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // We try several times to ensure the menu is inserted after system initialization
        for delay in [0.2, 0.5, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.setupCustomMenu()
            }
        }
    }
    
    private func setupCustomMenu() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        
        // Ensure index 0 (App Menu) exists
        if mainMenu.numberOfItems > 0, let appMenu = mainMenu.item(at: 0)?.submenu {
            // Prune other menus if they reappeared
            while mainMenu.numberOfItems > 1 {
                mainMenu.removeItem(at: 1)
            }
            
            // Insert "License Key..." if missing
            if !appMenu.items.contains(where: { $0.title == "License Key..." }) {
                let licenseItem = NSMenuItem(title: "License Key...", action: #selector(self.openLicenseSheet), keyEquivalent: "l")
                licenseItem.target = self
                appMenu.insertItem(licenseItem, at: 1)
            }
        }
    }
    
    @objc func openLicenseSheet() {
        NotificationCenter.default.post(name: NSNotification.Name("toggleLicenseSheet"), object: nil)
    }
}

@main
struct FileListerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var showingLicenseSheet = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(licenseManager)
                .sheet(isPresented: $showingLicenseSheet) {
                    LicenseView(isPresented: $showingLicenseSheet)
                        .environmentObject(licenseManager)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleLicenseSheet"))) { _ in
                    showingLicenseSheet = true
                }
        }
        .commands {
            // We empty the commands or leave only essential ones since we manage the App menu in AppDelegate
            CommandGroup(replacing: .appInfo) {
                Button("About FileLister") {
                    let credits = NSAttributedString(
                        string: "Designed by Luís Silva with support of AI",
                        attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 11)]
                    )
                    let options: [NSApplication.AboutPanelOptionKey: Any] = [
                        .credits: credits,
                        .version: "1.0",
                        .applicationName: "FileLister"
                    ]
                    NSApplication.shared.orderFrontStandardAboutPanel(options: options)
                }
            }
        }
    }
}
