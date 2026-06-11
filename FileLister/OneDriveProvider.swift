import Foundation
import Combine

// OneDrive concrete provider. Wraps the existing OneDriveAuth (OAuth/PKCE + Keychain)
// and republishes its connection state so SwiftUI views can observe the provider
// without depending on OneDriveAuth directly.
final class OneDriveProvider: ObservableObject, RemoteProvider {
    let kind: RemoteProviderKind = .oneDrive
    let auth: OneDriveAuth
    private var bag: Set<AnyCancellable> = []

    init(auth: OneDriveAuth = OneDriveAuth()) {
        self.auth = auth
        auth.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
    }

    var isConnected: Bool { auth.isConnected }
    var accountLabel: String { auth.accountName }
    var statusMessage: String {
        get { auth.status }
        set { auth.status = newValue }
    }

    func connect() { auth.connect() }
    func disconnect() { auth.disconnect() }
    func validAccessToken() async -> String? { await auth.validAccessToken() }
}
