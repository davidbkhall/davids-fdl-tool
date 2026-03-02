import Foundation

struct RecordingMode: Codable, Identifiable {
    var id: String
    var name: String
    var activePhotosites: Dimensions
    var activeImageAreaMM: PhysicalDimensions
    var maxFPS: Int
    var codecOptions: [String]

    enum CodingKeys: String, CodingKey {
        case id, name
        case activePhotosites = "active_photosites"
        case activeImageAreaMM = "active_image_area_mm"
        case maxFPS = "max_fps"
        case codecOptions = "codec_options"
    }
}
