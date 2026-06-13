import Foundation
import Combine

// One saved remote connection. Carries NO secrets — tokens/passwords live in the
// Keychain under `keychainAccount`; this record is safe to persist as plain JSON.
struct RemoteConnection: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: RemoteProviderKind
    var displayName: String
    var keychainAccount: String
}

// Owns the saved connections, the default, and the active provider instance.
// Singleton so the main window and the Settings scene share one source of truth.
@MainActor
final class RemoteConnectionStore: ObservableObject {
    static let shared = RemoteConnectionStore()

    @Published private(set) var connections: [RemoteConnection] = []
    @Published private(set) var defaultID: UUID?
    @Published private(set) var activeID: UUID?

    // One provider (with its own OneDriveAuth/keychain slot) per connection, kept
    // alive so OAuth sessions and connection state survive switching back and forth.
    private var providers: [UUID: OneDriveProvider] = [:]
    private var forward: AnyCancellable?

    var activeConnection: RemoteConnection? { connections.first { $0.id == activeID } }
    var defaultConnection: RemoteConnection? { connections.first { $0.id == defaultID } }
    var activeProvider: OneDriveProvider? { activeID.flatMap { providers[$0] } }

    init() {
        load()
        migrateLegacyIfNeeded()
    }

    // MARK: Providers

    func provider(for connection: RemoteConnection) -> OneDriveProvider {
        if let p = providers[connection.id] { return p }
        let p = OneDriveProvider(auth: OneDriveAuth(keychainAccount: connection.keychainAccount))
        providers[connection.id] = p
        return p
    }

    @discardableResult
    func activate(_ connection: RemoteConnection) -> OneDriveProvider {
        let p = provider(for: connection)
        activeID = connection.id
        // Republish the active provider's changes (isConnected, accountName, status)
        // so views observing the store refresh.
        forward = p.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        return p
    }

    func deactivate() {
        activeID = nil
        forward = nil
    }

    // MARK: CRUD

    @discardableResult
    func add(displayName: String, kind: RemoteProviderKind = .oneDrive) -> RemoteConnection {
        let id = UUID()
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let conn = RemoteConnection(id: id, kind: kind,
                                    displayName: name.isEmpty ? kind.displayName : name,
                                    keychainAccount: "conn-" + id.uuidString)
        connections.append(conn)
        if defaultID == nil { defaultID = conn.id }
        save()
        return conn
    }

    func rename(_ connection: RemoteConnection, to newName: String) {
        guard let i = connections.firstIndex(where: { $0.id == connection.id }) else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        connections[i].displayName = name
        save()
    }

    func remove(_ connection: RemoteConnection) {
        OneDriveAuth.purgeTokens(keychainAccount: connection.keychainAccount)
        providers[connection.id] = nil
        connections.removeAll { $0.id == connection.id }
        if defaultID == connection.id { defaultID = connections.first?.id }
        if activeID == connection.id { deactivate() }
        save()
    }

    func setDefault(_ connection: RemoteConnection) {
        defaultID = connection.id
        save()
    }

    func purgeAllTokens() {
        for conn in connections {
            OneDriveAuth.purgeTokens(keychainAccount: conn.keychainAccount)
        }
    }

    // MARK: Persistence (Application Support/FileLister/connections.json)

    private struct Snapshot: Codable {
        var connections: [RemoteConnection]
        var defaultID: UUID?
    }

    private var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let folder = dir.appendingPathComponent("FileLister", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("connections.json")
    }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        connections = snap.connections
        defaultID = snap.defaultID
    }

    private func save() {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(Snapshot(connections: connections, defaultID: defaultID))
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    // Pre-connections installs kept a single OneDrive token in the "default" Keychain
    // slot. Wrap it in a connection record so nothing is lost on upgrade.
    private func migrateLegacyIfNeeded() {
        guard connections.isEmpty, OneDriveAuth.hasLegacyDefaultTokens else { return }
        let conn = RemoteConnection(id: UUID(), kind: .oneDrive,
                                    displayName: "OneDrive", keychainAccount: "default")
        connections = [conn]
        defaultID = conn.id
        save()
    }
}
