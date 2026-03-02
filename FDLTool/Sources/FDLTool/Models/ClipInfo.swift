import Foundation

struct ClipInfo: Codable, Identifiable {
    var id: String { filePath }
    var filePath: String
    var fileName: String
    var width: Int
    var height: Int
    var codec: String
    var fps: Double
    var duration: Double
    var fileSize: Int64?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case fileName = "file_name"
        case width, height, codec, fps, duration
        case fileSize = "file_size"
    }
}
