import Foundation

// A OneDrive image with the perceptual hashes + metadata needed to group similar
// photos (cloud counterpart of PhotoInfo). #4. Hashes are computed from a downloaded
// thumbnail; metadata comes from the Graph photo/image/location facets.
struct CloudPhotoInfo: Identifiable, Hashable {
    let id: String          // drive item id
    let name: String
    let path: String        // display path within the drive
    let size: Int64
    let pixelWidth: Int
    let pixelHeight: Int
    let captureDate: Date?
    let cameraModel: String?
    let gps: (lat: Double, lon: Double)?
    let dHash: UInt64
    let pHash: UInt64
    let webURL: String?

    var fullPath: String { path.isEmpty ? name : path + "/" + name }
    var pixels: Int { pixelWidth * pixelHeight }

    static func == (l: CloudPhotoInfo, r: CloudPhotoInfo) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

// A cluster of visually-similar OneDrive photos with a chosen keeper.
struct CloudPhotoGroup: Identifiable {
    let id = UUID()
    var photos: [CloudPhotoInfo]
    var keeperID: String

    var keeper: CloudPhotoInfo? { photos.first { $0.id == keeperID } }

    func reclaimableBytes(excluding deleted: Set<String>) -> Int64 {
        photos.filter { $0.id != keeperID && !deleted.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
}
