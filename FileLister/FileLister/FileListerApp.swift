import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // We only prune the extra menus (File, Edit, etc.) to keep the UI minimal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let mainMenu = NSApplication.shared.mainMenu {
                while mainMenu.numberOfItems > 1 {
                    mainMenu.removeItem(at: 1)
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
                .navigationTitle(licenseManager.isRegistered ? "FileLister - Licensed to \(licenseManager.registeredName)" : "FileLister (Trial Version)")
        }
        .commands {
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
                
                Divider()
                
                Button("License Key...") {
                    showingLicenseSheet = true
                }
                .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}
