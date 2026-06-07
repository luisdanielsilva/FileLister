import Foundation
import Combine

final class OneDrivePreferences: ObservableObject {
    static let shared = OneDrivePreferences()

    // 0 = unlimited
    @Published var maxFiles: Int { didSet { UserDefaults.standard.set(maxFiles, forKey: "oneDriveMaxFiles") } }
    @Published var maxGB: Double { didSet { UserDefaults.standard.set(maxGB, forKey: "oneDriveMaxGB") } }

    private init() {
        let f = UserDefaults.standard.object(forKey: "oneDriveMaxFiles") as? Int
        let g = UserDefaults.standard.object(forKey: "oneDriveMaxGB") as? Double
        maxFiles = f ?? 5000
        maxGB = g ?? 5.0
    }

    var fileLimit: Int { maxFiles <= 0 ? Int.max : maxFiles }
    var byteLimit: Int64 { maxGB <= 0 ? Int64.max : Int64(maxGB * 1_073_741_824) }
}
