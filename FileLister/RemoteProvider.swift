import Foundation

// Identifies a remote backend. Display name + icon live here so the UI can render the
// active provider without knowing the concrete type. New providers add a case (issue #6).
enum RemoteProviderKind: String, Codable {
    case oneDrive

    var displayName: String {
        switch self {
        case .oneDrive: return "OneDrive"
        }
    }
    var icon: String {
        switch self {
        case .oneDrive: return "cloud"
        }
    }
}

// The connection/identity surface the app talks to instead of a concrete provider.
// Phase 1 extracts auth + identity only; listing, crawl, and mutations stay inside
// RemoteEngine until a second provider forces them up (issues #8 / #9).
protocol RemoteProvider: AnyObject {
    var kind: RemoteProviderKind { get }
    var isConnected: Bool { get }
    var accountLabel: String { get }
    var statusMessage: String { get }

    func connect()
    func disconnect()
    func validAccessToken() async -> String?
}
