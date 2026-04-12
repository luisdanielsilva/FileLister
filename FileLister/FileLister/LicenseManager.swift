import Foundation
import SwiftUI
import Combine

class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    
    @Published var isRegistered: Bool = false
    @Published var trialDeletions: Int = 0
    @Published var licenseKey: String = ""
    
    private let kIsRegistered = "FileLister_IsRegistered"
    private let kTrialDeletions = "FileLister_TrialDeletions"
    private let kLicenseKey = "FileLister_LicenseKey"
    
    init() {
        self.isRegistered = UserDefaults.standard.bool(forKey: kIsRegistered)
        self.trialDeletions = UserDefaults.standard.integer(forKey: kTrialDeletions)
        self.licenseKey = UserDefaults.standard.string(forKey: kLicenseKey) ?? ""
    }
    
    func register(key: String) -> Bool {
        if validate(key: key) {
            self.isRegistered = true
            self.licenseKey = key
            UserDefaults.standard.set(true, forKey: kIsRegistered)
            UserDefaults.standard.set(key, forKey: kLicenseKey)
            return true
        }
        return false
    }
    
    func validate(key: String) -> Bool {
        // 1. Basic Format Check (REGEX)
        let pattern = "^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: key.utf16.count)
        guard regex?.firstMatch(in: key, options: [], range: range) != nil else { return false }
        
        // 2. Cryptographic Checksum Validation
        let parts = key.uppercased().split(separator: "-")
        guard parts.count == 4 else { return false }
        
        let seed = parts[0] + parts[1] + parts[2]
        let providedSignature = String(parts[3])
        
        // The Secret Salt (Keep this private)
        let salt = "FileLister-Secret-Salt-2026-Porto"
        
        // Generate the expected signature
        let inputString = seed + salt
        let inputData = Data(inputString.utf8)
        let hashed = SHA256.hash(data: inputData)
        
        // Extract first 4 chars of the hash as the signature
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
