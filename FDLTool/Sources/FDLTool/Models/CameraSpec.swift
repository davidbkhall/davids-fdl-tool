import Foundation

struct CameraDatabase: Codable {
    var version: String
    var lastUpdated: String
    var cameras: [CameraSpec]

    enum CodingKeys: String, CodingKey {
        case version
        case lastUpdated = "last_updated"
        case cameras
    }
}

struct CameraSpec: Codable, Identifiable {
    var id: String
    var manufacturer: String
    var model: String
    var sensor: SensorSpec
    var recordingModes: [RecordingMode]
    var commonDeliverables: [String]

    enum CodingKeys: String, CodingKey {
        case id, manufacturer, model, sensor
        case recordingModes = "recording_modes"
        case commonDeliverables = "common_deliverables"
    }
}

struct SensorSpec: Codable {
    var name: String
    var photositeDimensions: Dimensions
    var physicalDimensionsMM: PhysicalDimensions
    var pixelPitchUM: Double

    enum CodingKeys: String, CodingKey {
        case name
        case photositeDimensions = "photosite_dimensions"
        case physicalDimensionsMM = "physical_dimensions_mm"
        case pixelPitchUM = "pixel_pitch_um"
    }
}

struct Dimensions: Codable {
    var width: Int
    var height: Int
}

struct PhysicalDimensions: Codable {
    var width: Double
    var height: Double
}
