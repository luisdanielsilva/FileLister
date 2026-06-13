import SwiftUI

// Sheet listing the saved remote connections: click to connect, star to set the
// default, "New connection…" to add. Shown on ⌥-click of Remote or when no default.
struct RemoteConnectionPickerSheet: View {
    @ObservedObject var store: RemoteConnectionStore
    let onSelect: (RemoteConnection) -> Void
    let onClose: () -> Void

    @State private var addingNew = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "cloud.fill").foregroundColor(.blue)
                Text("Remote Connections").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(12)
            Divider()

            if store.connections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cloud").font(.system(size: 32)).foregroundColor(.gray.opacity(0.3))
                    Text("No connections yet.").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.connections) { conn in
                        ConnectionRow(store: store, connection: conn,
                                      isActive: store.activeID == conn.id,
                                      isDefault: store.defaultID == conn.id,
                                      onSelect: { onSelect(conn); onClose() })
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Button(action: { addingNew = true }) {
                    Label("New connection…", systemImage: "plus.circle").font(.system(size: 11))
                }.controlSize(.small)
                Spacer()
                Text("Manage in Settings → Connections").font(.system(size: 9)).foregroundColor(.secondary)
                Button("Close", action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 440, height: 320)
        .sheet(isPresented: $addingNew) {
            ConnectionEditSheet(store: store, connection: nil) { newConn in
                onSelect(newConn); onClose()
            }
        }
    }
}

private struct ConnectionRow: View {
    @ObservedObject var store: RemoteConnectionStore
    let connection: RemoteConnection
    let isActive: Bool
    let isDefault: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: connection.kind.icon).foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(connection.displayName).font(.system(size: 12, weight: .semibold))
                    if isDefault {
                        Text("Default").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.blue).cornerRadius(3)
                    }
                    if isActive {
                        Text("Active").font(.system(size: 8, weight: .bold)).foregroundColor(.green)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.green.opacity(0.5), lineWidth: 1))
                    }
                }
                Text(accountLine).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { store.setDefault(connection) }) {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .foregroundColor(isDefault ? .yellow : .secondary)
            }
            .buttonStyle(.plain).help("Set as default (used on single-click of Remote)")
            Button("Select", action: onSelect).controlSize(.small)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onSelect() }
    }

    private var accountLine: String {
        let p = store.provider(for: connection)
        if p.isConnected { return "\(connection.kind.displayName) · \(p.accountLabel)" }
        return "\(connection.kind.displayName) · not signed in"
    }
}

// Add (connection == nil) or rename an existing connection. Provider dropdown shows
// future kinds disabled; sign-in itself happens on first activation.
struct ConnectionEditSheet: View {
    @ObservedObject var store: RemoteConnectionStore
    let connection: RemoteConnection?            // nil = create new
    var onCreated: ((RemoteConnection) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(connection == nil ? "New Remote Connection" : "Edit Connection")
                .font(.system(size: 13, weight: .semibold))

            HStack {
                Text("Provider").frame(width: 90, alignment: .leading)
                Picker("", selection: .constant(RemoteProviderKind.oneDrive)) {
                    Label("OneDrive", systemImage: "cloud").tag(RemoteProviderKind.oneDrive)
                }
                .labelsHidden().frame(width: 180)
                .disabled(connection != nil)
                Text("More providers in a later update.").font(.system(size: 9)).foregroundColor(.secondary)
            }

            HStack {
                Text("Display name").frame(width: 90, alignment: .leading)
                TextField("e.g. Personal OneDrive", text: $displayName)
                    .textFieldStyle(.roundedBorder).frame(width: 220)
            }

            if connection == nil {
                Text("You'll sign in with Microsoft when this connection is first used.")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(connection == nil ? "Add" : "Save") {
                    if let conn = connection {
                        store.rename(conn, to: displayName)
                    } else {
                        let newConn = store.add(displayName: displayName)
                        onCreated?(newConn)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty && connection == nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { displayName = connection?.displayName ?? "" }
    }
}

// Settings → Connections tab: list + Add / Edit / Remove / Set Default.
struct RemoteConnectionsSettingsView: View {
    @ObservedObject private var store = RemoteConnectionStore.shared
    @State private var selectedID: UUID?
    @State private var editing: RemoteConnection?
    @State private var addingNew = false
    @State private var confirmingRemove: RemoteConnection?

    private var selected: RemoteConnection? { store.connections.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remote connections").font(.headline)
            Text("Saved accounts for the Remote source. Single-clicking Remote connects to the default; ⌥-click shows the connection picker. Credentials are stored in the macOS Keychain.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selectedID) {
                ForEach(store.connections) { conn in
                    HStack(spacing: 8) {
                        Image(systemName: conn.kind.icon).foregroundColor(.blue)
                        Text(conn.displayName).font(.system(size: 12))
                        if store.defaultID == conn.id {
                            Text("Default").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.blue).cornerRadius(3)
                        }
                        Spacer()
                        Text(accountLine(conn)).font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    .tag(conn.id)
                }
            }
            .frame(minHeight: 160)

            HStack(spacing: 8) {
                Button(action: { addingNew = true }) { Label("Add", systemImage: "plus") }
                Button(action: { editing = selected }) { Label("Edit", systemImage: "pencil") }
                    .disabled(selected == nil)
                Button(action: { confirmingRemove = selected }) { Label("Remove", systemImage: "minus") }
                    .disabled(selected == nil)
                Button(action: { if let s = selected { store.setDefault(s) } }) {
                    Label("Set Default", systemImage: "star")
                }
                .disabled(selected == nil || store.defaultID == selectedID)
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(20)
        .sheet(isPresented: $addingNew) { ConnectionEditSheet(store: store, connection: nil) }
        .sheet(item: $editing) { conn in ConnectionEditSheet(store: store, connection: conn) }
        .alert("Remove \"\(confirmingRemove?.displayName ?? "")\"?",
               isPresented: Binding(get: { confirmingRemove != nil }, set: { if !$0 { confirmingRemove = nil } })) {
            Button("Remove", role: .destructive) {
                if let c = confirmingRemove { store.remove(c) }
                confirmingRemove = nil
            }
            Button("Cancel", role: .cancel) { confirmingRemove = nil }
        } message: {
            Text("Its sign-in tokens are removed from the Keychain. Nothing in the cloud account is touched.")
        }
    }

    private func accountLine(_ conn: RemoteConnection) -> String {
        let p = store.provider(for: conn)
        return p.isConnected ? p.accountLabel : "not signed in"
    }
}
