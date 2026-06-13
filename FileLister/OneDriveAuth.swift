import Foundation
import Combine
import AppKit
import AuthenticationServices
import CryptoKit

// MARK: - Keychain (stores the token blob)

private enum Keychain {
    static let service = "FileLister.OneDrive"

    static func save(_ data: Data, account: String) {
        delete(account: account)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func load(account: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
    static func delete(account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
    }
}

private struct TokenSet: Codable {
    var accessToken: String
    var refreshToken: String
    var expiry: Date
    var isValid: Bool { Date() < expiry }
}

enum OneDriveError: Error { case cancelled, network(String), token(String) }

final class OneDriveAuth: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isConnected = false
    @Published private(set) var accountName = ""
    @Published var status = ""

    private var tokens: TokenSet? { didSet { persist() } }
    private var session: ASWebAuthenticationSession?
    private var pkceVerifier = ""
    // One Keychain slot per saved connection ("default" = the original single-account slot).
    private let account: String
    private var nameKey: String { "oneDriveAccountName-" + account }

    init(keychainAccount: String = "default") {
        self.account = keychainAccount
        super.init()
        if let data = Keychain.load(account: account),
           let t = try? JSONDecoder().decode(TokenSet.self, from: data) {
            tokens = t
            isConnected = true
            accountName = UserDefaults.standard.string(forKey: nameKey)
                ?? UserDefaults.standard.string(forKey: "oneDriveAccountName")   // legacy single-account key
                ?? "OneDrive"
        }
    }

    // True when tokens exist in the original single-account slot (pre-connections migration).
    static var hasLegacyDefaultTokens: Bool { Keychain.load(account: "default") != nil }

    // Remove a connection's stored tokens + cached account name (used when deleting a connection).
    static func purgeTokens(keychainAccount: String) {
        Keychain.delete(account: keychainAccount)
        UserDefaults.standard.removeObject(forKey: "oneDriveAccountName-" + keychainAccount)
    }

    private func persist() {
        guard let t = tokens, let data = try? JSONEncoder().encode(t) else { return }
        Keychain.save(data, account: account)
    }

    // MARK: Connect / disconnect

    func connect() {
        pkceVerifier = Self.randomURLSafe(64)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(pkceVerifier.utf8))))

        var comps = URLComponents(string: OneDriveConfig.authorizeURL)!
        comps.queryItems = [
            .init(name: "client_id", value: OneDriveConfig.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: OneDriveConfig.redirectURI),
            .init(name: "scope", value: OneDriveConfig.scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account")
        ]
        guard let url = comps.url else { return }

        status = "Opening sign-in…"
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: OneDriveConfig.redirectScheme) { [weak self] callback, error in
            guard let self else { return }
            if let error = error {
                let nsErr = error as NSError
                if nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    DispatchQueue.main.async { self.status = "Sign-in cancelled." }
                } else {
                    DispatchQueue.main.async { self.status = "Sign-in failed: \(error.localizedDescription)" }
                }
                return
            }
            guard let callback,
                  let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else {
                DispatchQueue.main.async { self.status = "Sign-in failed: no code returned." }
                return
            }
            Task { await self.exchangeCode(code) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    func disconnect() {
        tokens = nil
        Keychain.delete(account: account)
        UserDefaults.standard.removeObject(forKey: nameKey)
        if account == "default" { UserDefaults.standard.removeObject(forKey: "oneDriveAccountName") }
        isConnected = false
        accountName = ""
        status = "Disconnected."
    }

    // MARK: Token exchange / refresh

    private func exchangeCode(_ code: String) async {
        let body = [
            "client_id": OneDriveConfig.clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OneDriveConfig.redirectURI,
            "code_verifier": pkceVerifier,
            "scope": OneDriveConfig.scopes
        ]
        do {
            try await requestTokens(body)
            await fetchAccountName()
            await MainActor.run { self.isConnected = true; self.status = "Connected to OneDrive." }
        } catch {
            await MainActor.run { self.status = "Token exchange failed: \(error.localizedDescription)" }
        }
    }

    // Returns a valid access token, refreshing if needed.
    func validAccessToken() async -> String? {
        if let t = tokens, t.isValid { return t.accessToken }
        guard let refresh = tokens?.refreshToken else { return nil }
        let body = [
            "client_id": OneDriveConfig.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "redirect_uri": OneDriveConfig.redirectURI,
            "scope": OneDriveConfig.scopes
        ]
        do {
            try await requestTokens(body)
            return tokens?.accessToken
        } catch {
            await MainActor.run { self.isConnected = false; self.status = "Session expired — please reconnect." }
            return nil
        }
    }

    private func requestTokens(_ body: [String: String]) async throws {
        var req = URLRequest(url: URL(string: OneDriveConfig.tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_description"] as? String ?? "HTTP error"
            throw OneDriveError.token(msg)
        }
        let refresh = (json["refresh_token"] as? String) ?? tokens?.refreshToken ?? ""
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let newTokens = TokenSet(accessToken: access, refreshToken: refresh, expiry: Date().addingTimeInterval(expiresIn - 60))
        await MainActor.run { self.tokens = newTokens }
    }

    private func fetchAccountName() async {
        guard let token = tokens?.accessToken else { return }
        var req = URLRequest(url: URL(string: OneDriveConfig.graphBase + "/me")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let name = (json["displayName"] as? String) ?? (json["userPrincipalName"] as? String) ?? "OneDrive"
            await MainActor.run {
                self.accountName = name
                UserDefaults.standard.set(name, forKey: self.nameKey)
            }
        }
    }

    // MARK: Helpers

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64url(Data(bytes))
    }
    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    private static func formEncode(_ s: String) -> String {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: cs) ?? s
    }
}
