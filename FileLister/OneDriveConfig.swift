import Foundation

enum OneDriveConfig {
    static let clientID = "dd02061c-c9c8-47b7-907a-d1dc2882d910"

    // Custom scheme caught by ASWebAuthenticationSession (must match the Azure redirect URI).
    static let redirectScheme = "msauth.Luis.FileLister"
    static let redirectURI = "msauth.Luis.FileLister://auth"

    // "common" supports both personal and work/school accounts.
    static let authority = "https://login.microsoftonline.com/common/oauth2/v2.0"
    static var authorizeURL: String { authority + "/authorize" }
    static var tokenURL: String { authority + "/token" }

    static let graphBase = "https://graph.microsoft.com/v1.0"

    // Files.ReadWrite to allow deleting; offline_access for refresh tokens.
    static let scopes = "Files.ReadWrite offline_access User.Read"

    // v1 analysis caps (lift later)
    static let maxFiles = 500
    static let maxBytes: Int64 = 1_073_741_824   // 1 GB
}
