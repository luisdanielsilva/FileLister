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
            }
        }
    }
}

@main
struct FileListerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
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
            }
        }
    }
}
