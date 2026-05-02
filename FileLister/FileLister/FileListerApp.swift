import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // We only prune the extra menus (File, Edit, etc.) to keep the UI minimal
        // We keep the App menu and the Help menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let mainMenu = NSApplication.shared.mainMenu {
                let itemsToRemove = mainMenu.items.filter { item in
                    let title = item.title.lowercased()
                    return title != "filelister" && title != "help"
                }
                for item in itemsToRemove {
                    mainMenu.removeItem(item)
                }
            }
        }
    }
}

@main
struct FileListerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var licenseManager = LicenseManager.shared
    @State private var showingLicenseSheet = false
    @Environment(\.openWindow) private var openWindow
    
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
                .navigationTitle(licenseManager.isRegistered ? "FileLister - Licensed to \(licenseManager.registeredEmail)" : "FileLister (Trial Version)")
        }
        
        Window("How to find duplicated files", id: "help") {
            HelpView()
        }
        .windowStyle(.hiddenTitleBar)
        
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About FileLister") {
                    let credits = NSAttributedString(
                        string: "Designed by Luís Silva with support of AI",
                        attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 11)]
                    )
                    let options: [NSApplication.AboutPanelOptionKey: Any] = [
                        .credits: credits,
                        .applicationVersion: "1.2.0",
                        .version: "",
                        .applicationName: "FileLister"
                    ]
                    NSApplication.shared.orderFrontStandardAboutPanel(options: options)
                }
                
                Divider()
                
                Button("License Key...") {
                    showingLicenseSheet = true
                }
                .keyboardShortcut("l", modifiers: .command)
            }
            
            CommandGroup(replacing: .help) {
                Button("How to find duplicated files") {
                    openWindow(id: "help")
                }
            }
        }
    }
}
