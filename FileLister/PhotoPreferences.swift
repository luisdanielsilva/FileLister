import Foundation
import Combine

// Ordered rules used to pick the "best copy" (keeper) within a similar-photo group.
enum BestCopyCriterion: String, CaseIterable, Codable, Identifiable {
    case resolution, fileSize, newest, oldest, preferRaw, hasGPS
    var id: String { rawValue }
    var label: String {
        switch self {
        case .resolution: return "Highest resolution"
        case .fileSize:   return "Largest file size"
        case .newest:     return "Newest (capture date)"
        case .oldest:     return "Oldest (capture date)"
        case .preferRaw:  return "Prefer RAW / original"
        case .hasGPS:     return "Has GPS location"
        }
    }
    var icon: String {
        switch self {
        case .resolution: return "arrow.up.left.and.arrow.down.right"
        case .fileSize:   return "internaldrive"
        case .newest:     return "clock.arrow.circlepath"
        case .oldest:     return "clock"
        case .preferRaw:  return "camera.aperture"
        case .hasGPS:     return "location"
        }
    }
}

final class PhotoPreferences: ObservableObject {
    static let shared = PhotoPreferences()

    @Published var bestCopyPriority: [BestCopyCriterion] { didSet { persist() } }

    private let key = "photoBestCopyPriority"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([BestCopyCriterion].self, from: data),
           !arr.isEmpty {
            // Make sure any newly-added criteria still appear at the end
            let missing = BestCopyCriterion.allCases.filter { !arr.contains($0) }
            bestCopyPriority = arr + missing
        } else {
            bestCopyPriority = [.resolution, .fileSize, .newest, .preferRaw, .hasGPS, .oldest]
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bestCopyPriority) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // True if `a` is a strictly better keeper than `b` per the configured priority.
    func isBetter(_ a: PhotoInfo, _ b: PhotoInfo) -> Bool {
        for c in bestCopyPriority {
            switch c {
            case .resolution:
                if a.pixels != b.pixels { return a.pixels > b.pixels }
            case .fileSize:
                if a.sizeBytes != b.sizeBytes { return a.sizeBytes > b.sizeBytes }
            case .newest:
                let da = a.captureDate ?? .distantPast, db = b.captureDate ?? .distantPast
                if da != db { return da > db }
            case .oldest:
                let da = a.captureDate ?? .distantFuture, db = b.captureDate ?? .distantFuture
                if da != db { return da < db }
            case .preferRaw:
                if a.isRaw != b.isRaw { return a.isRaw }
            case .hasGPS:
                let ga = a.gps != nil, gb = b.gps != nil
                if ga != gb { return ga }
            }
        }
        return false
    }
}
