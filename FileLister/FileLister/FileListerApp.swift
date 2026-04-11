import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // We use a small delay to ensure SwiftUI has finished its default menu setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let mainMenu = NSApplication.shared.mainMenu {
                // Index 0 is the Application menu (FileLister)
                // We remove everything from index 1 onwards (File, Edit, Format, View, Window, Help)
                while mainMenu.numberOfItems > 1 {
                    mainMenu.removeItem(at: 1)
                }
                
                // Now we add our custom "License Key..." menu item to the Application menu
                if let appMenu = mainMenu.item(at: 0)?.submenu {
                    // Check if it's already there to avoid duplicates
                    if !appMenu.items.contains(where: { $0.title == "License Key..." }) {
                        let licenseItem = NSMenuItem(title: "License Key...", action: #selector(self.openLicenseSheet), keyEquivalent: "l")
                        licenseItem.target = self
                        // Insert After "About FileLister" (which is usually index 0)
                        appMenu.insertItem(licenseItem, at: 1)
                    }
                }
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
