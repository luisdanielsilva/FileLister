import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Remove standard menus (File, Edit, View, Window) but keep the app menu and Help menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let mainMenu = NSApplication.shared.mainMenu else { return }
            let keepTitles: Set<String> = ["FileLister", "Help"]
            var toRemove: [NSMenuItem] = []
            for item in mainMenu.items {
                if !keepTitles.contains(item.title) {
                    toRemove.append(item)
                }
            }
            toRemove.forEach { mainMenu.removeItem($0) }
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

            CommandGroup(replacing: .help) {
                Button("FileLister Help") {
                    openWindow(id: "help")
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window("FileLister Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 820, height: 600)
    }
}
