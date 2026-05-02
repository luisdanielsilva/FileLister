import Foundation
import SwiftUI
import Combine
import CryptoKit

class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    
    @Published var isRegistered: Bool = false
    @Published var trialDeletions: Int = 0
    @Published var licenseKey: String = ""
    @Published var registeredEmail: String = "Trial Version"
    
    private let kIsRegistered = "FileLister_IsRegistered"
    private let kTrialDeletions = "FileLister_TrialDeletions"
    private let kLicenseKey = "FileLister_LicenseKey"
    private let kRegisteredEmail = "FileLister_RegisteredEmail"
    
    init() {
        self.isRegistered = UserDefaults.standard.bool(forKey: kIsRegistered)
        self.trialDeletions = UserDefaults.standard.integer(forKey: kTrialDeletions)
        self.licenseKey = UserDefaults.standard.string(forKey: kLicenseKey) ?? ""
        self.registeredEmail = UserDefaults.standard.string(forKey: kRegisteredEmail) ?? "Trial Version"
    }
    
    func register(key: String, email: String) -> Bool {
        if validate(key: key, email: email) {
            self.isRegistered = true
            self.licenseKey = key
            self.registeredEmail = email
            UserDefaults.standard.set(true, forKey: kIsRegistered)
            UserDefaults.standard.set(key, forKey: kLicenseKey)
            UserDefaults.standard.set(email, forKey: kRegisteredEmail)
            return true
        }
        return false
    }
    
    func deactivate() {
        self.isRegistered = false
        self.licenseKey = ""
        self.registeredEmail = "Trial Version"
        UserDefaults.standard.set(false, forKey: kIsRegistered)
        UserDefaults.standard.set("", forKey: kLicenseKey)
        UserDefaults.standard.set("Trial Version", forKey: kRegisteredEmail)
    }
    
    func validate(key: String, email: String) -> Bool {
        let pattern = "^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{6}$"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: key.utf16.count)
        guard regex?.firstMatch(in: key, options: [], range: range) != nil else { return false }
        
        let parts = key.uppercased().split(separator: "-")
        guard parts.count == 6 else { return false }
        
        let seed = parts[0...4].joined()
        let providedSignature = String(parts[5])
        
        // Obfuscated Salt Builder
        let saltBytes: [UInt8] = [70, 105, 108, 101, 76, 105, 115, 116, 101, 114, 45, 83, 101, 99, 114, 101, 116, 45, 83, 97, 108, 116, 45, 50, 48, 50, 54, 45, 80, 111, 114, 116, 111]
        let salt = String(bytes: saltBytes, encoding: .utf8) ?? ""
        
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let inputString = seed + cleanEmail + salt
        let inputData = Data(inputString.utf8)
        let hashed = SHA256.hash(data: inputData)
        
        // 6 character signature instead of 4
        let expectedSignature = hashed.compactMap { String(format: "%02x", $0) }.joined().uppercased().prefix(6)
        
        return providedSignature == expectedSignature
    }
    
    func recordDeletion() {
        if !isRegistered {
            self.trialDeletions += 1
            UserDefaults.standard.set(self.trialDeletions, forKey: kTrialDeletions)
        }
    }
    
    func canPerformFreeDeletion() -> Bool {
        return isRegistered || trialDeletions < 15
    }
}
