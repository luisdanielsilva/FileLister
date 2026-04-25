import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // Header
                HStack(spacing: 15) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How to Find Duplicates")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Mastering the features of FileLister")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 10)

                Divider()

                VStack(alignment: .leading, spacing: 25) {
                    HelpSection(
                        title: "Select a Source",
                        icon: "folder.badge.plus",
                        color: .blue,
                        description: "Click 'Select...' to choose a folder or drive. Scanning begins automatically the moment you confirm your selection."
                    )

                    HelpSection(
                        title: "Deep Scan (SHA-256)",
                        icon: "cpu",
                        color: .orange,
                        description: "Switch this on to compare file contents byte-by-byte. It guarantees files are 100% identical even if they have different names."
                    )

                    HelpSection(
                        title: "Media & Hidden Filters",
                        icon: "film",
                        color: .purple,
                        description: "Filter for photos and videos using the 'Media' toggle. Use 'No Hidden' to exclude system files like .DS_Store from your results."
                    )

                    HelpSection(
                        title: "Extension Filtering",
                        icon: "text.magnifyingglass",
                        color: .teal,
                        description: "Type an extension (e.g., 'xls', 'pdf') in the 'Ext' box to instantly focus on specific file types within your scan results."
                    )

                    HelpSection(
                        title: "Smart Selection Rules",
                        icon: "wand.and.stars.inverse",
                        color: .green,
                        description: "Use the Rules menu to automatically mark files. Choose to keep the 'Oldest', 'Newest', or 'Largest' version in every group."
                    )

                    HelpSection(
                        title: "Ignore & Safety Lock",
                        icon: "lock.shield",
                        color: .red,
                        description: "Mark individual files as 'Ignore' to protect them. Our 'Safety Lock' automatically prevents you from deleting the last remaining copy of any file."
                    )
                    
                    HelpSection(
                        title: "Action Logging",
                        icon: "doc.text.magnifyingglass",
                        color: .secondary,
                        description: "Enable 'Log' and select a folder to save a record of every deletion. Logs are created only when you actually move files to the Trash."
                    )
                }
                
                Spacer(minLength: 20)
                
                VStack(spacing: 8) {
                    Text("💡 Pro Tip")
                        .font(.headline)
                    Text("Hover your mouse over any button in the main window to see a quick description of what it does.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)
            }
            .padding(40)
        }
        .frame(minWidth: 550, minHeight: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct HelpSection: View {
    let title: String
    let icon: String
    let color: Color
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
