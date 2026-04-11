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
        let pattern = "^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: key.utf16.count)
        return regex?.firstMatch(in: key, options: [], range: range) != nil
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
