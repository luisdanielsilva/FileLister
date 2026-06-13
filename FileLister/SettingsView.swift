import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            PhotoSettingsView()
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle.angled") }
            OneDriveSettingsView()
                .tabItem { Label("OneDrive", systemImage: "cloud") }
            RemoteConnectionsSettingsView()
                .tabItem { Label("Connections", systemImage: "person.crop.circle.badge.plus") }
        }
        .frame(width: 460, height: 400)
    }
}

struct OneDriveSettingsView: View {
    @ObservedObject private var prefs = OneDrivePreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OneDrive scan limits").font(.headline)
            Text("Scanning OneDrive uses your network. Limits keep the first scan fast; raise or remove them when you're ready for a full scan (slower on large drives).")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Maximum files").frame(width: 130, alignment: .leading)
                TextField("", value: $prefs.maxFiles, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 90)
                Text("0 = no limit").font(.caption2).foregroundColor(.secondary)
            }
            HStack {
                Text("Maximum size (GB)").frame(width: 130, alignment: .leading)
                TextField("", value: $prefs.maxGB, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 90)
                Text("0 = no limit").font(.caption2).foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button("No limit") { prefs.maxFiles = 0; prefs.maxGB = 0 }
                Button("Reset (5000 / 5 GB)") { prefs.maxFiles = 5000; prefs.maxGB = 5 }
            }
            .controlSize(.small)

            Text("The size limit mainly affects Photos on OneDrive (thumbnail downloads). File and folder duplicate scans read metadata only.")
                .font(.caption2).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(20)
    }
}
