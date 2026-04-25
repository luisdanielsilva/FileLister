import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                // Header
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        Text("How to Find Duplicates")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("A guide to using FileLister effectively")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 10)
                
                // Screenshot
                if let path = Bundle.main.path(forResource: "screenshot", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: path) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                            .shadow(radius: 5)
                        Text("The main interface with filters and duplicate groups.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Step 1: Select Source
                HelpSection(
                    title: "1. Select a Folder",
                    icon: "folder.badge.plus",
                    color: .blue,
                    description: "Click the 'Select...' button or the large folder icon in the center to choose the directory or drive you want to scan. FileLister will automatically start scanning immediately after you pick a folder."
                )

                // Step 2: Configure Analysis
                HelpSection(
                    title: "2. Choose Analysis Type",
                    icon: "cpu",
                    color: .orange,
                    description: "Use 'Deep Scan' for 100% accuracy using SHA-256 hashing (recommened for identical photos/videos). Turn it off for a faster scan based on filename and size."
                )

                // Step 3: Use Filters
                HelpSection(
                    title: "3. Refine Results",
                    icon: "line.3.horizontal.decrease.circle",
                    color: .purple,
                    description: "• Use 'Media' to focus only on photos and videos.\n• Type an extension like 'jpg' or 'pdf' in the 'Ext' box to filter by type.\n• Toggle 'No Hidden' to hide system files like .DS_Store."
                )

                // Step 4: Auto-Selection
                HelpSection(
                    title: "4. Smart Selection",
                    icon: "wand.and.stars",
                    color: .green,
                    description: "Instead of clicking one by one, use the Rule Menu to automatically mark files for deletion. You can choose to 'Keep Oldest', 'Keep Newest', or 'Keep Largest' in every group."
                )

                // Step 5: Safety First
                HelpSection(
                    title: "5. Safe Cleanup",
                    icon: "shield.checkered",
                    color: .red,
                    description: "FileLister never lets you delete the last copy of a file (Safety Lock). Use 'Ignore' on files you want to keep regardless of rules. When ready, click 'Clean All Duplicates' to move them to the macOS Trash."
                )
                
                Spacer(minLength: 20)
                
                Text("Tip: Hover your mouse over any button in the app to see a quick description of its function.")
                    .font(.caption)
                    .italic()
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
            }
            .padding(30)
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct HelpSection: View {
    let title: String
    let icon: String
    let color: Color
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }
        }
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        HelpView()
    }
}
