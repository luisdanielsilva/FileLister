import Foundation
import SwiftUI
import Combine

class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    
    @Published var isRegistered: Bool = false
    @Published var trialDeletions: Int = 0
    @Published var licenseKey: String = ""
    @Published var registeredName: String = "Trial Version"
    
    private let kIsRegistered = "FileLister_IsRegistered"
    private let kTrialDeletions = "FileLister_TrialDeletions"
    private let kLicenseKey = "FileLister_LicenseKey"
    private let kRegisteredName = "FileLister_RegisteredName"
    
    init() {
        self.isRegistered = UserDefaults.standard.bool(forKey: kIsRegistered)
        self.trialDeletions = UserDefaults.standard.integer(forKey: kTrialDeletions)
        self.licenseKey = UserDefaults.standard.string(forKey: kLicenseKey) ?? ""
        self.registeredName = UserDefaults.standard.string(forKey: kRegisteredName) ?? "Trial Version"
    }
    
    func register(key: String, name: String = "User") -> Bool {
        if validate(key: key) {
            self.isRegistered = true
            self.licenseKey = key
            self.registeredName = name
            UserDefaults.standard.set(true, forKey: kIsRegistered)
            UserDefaults.standard.set(key, forKey: kLicenseKey)
            UserDefaults.standard.set(name, forKey: kRegisteredName)
            return true
        }
        return false
    }
    
    func deactivate() {
        self.isRegistered = false
        self.licenseKey = ""
        self.registeredName = "Trial Version"
        UserDefaults.standard.set(false, forKey: kIsRegistered)
        UserDefaults.standard.set("", forKey: kLicenseKey)
        UserDefaults.standard.set("Trial Version", forKey: kRegisteredName)
    }
    
    func validate(key: String) -> Bool {
        // Updated for Phase 2: Support longer keys (6 groups of 4 characters = 24 chars)
        let pattern = "^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: key.utf16.count)
        guard regex?.firstMatch(in: key, options: [], range: range) != nil else { return false }
        
        let parts = key.uppercased().split(separator: "-")
        guard parts.count == 6 else { return false }
        
        // Seed consists of the first 5 groups
        let seed = parts[0...4].joined()
        let providedSignature = String(parts[5])
        
        let salt = "FileLister-Secret-Salt-2026-Porto"
        let inputString = seed + salt
        let inputData = Data(inputString.utf8)
        let hashed = SHA256.hash(data: inputData)
        
        let expectedSignature = hashed.compactMap { String(format: "%02X", $0) }.joined().prefix(4)
        
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
