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
    var source: CameraSource

    enum CameraSource: String, Codable {
        case bundled
        case synced
        case custom
    }

    enum CodingKeys: String, CodingKey {
        case id, manufacturer, model, sensor, source
        case recordingModes = "recording_modes"
        case commonDeliverables = "common_deliverables"
    }

    init(id: String, manufacturer: String, model: String, sensor: SensorSpec,
         recordingModes: [RecordingMode], commonDeliverables: [String],
         source: CameraSource = .bundled) {
        self.id = id
        self.manufacturer = manufacturer
        self.model = model
        self.sensor = sensor
        self.recordingModes = recordingModes
        self.commonDeliverables = commonDeliverables
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        manufacturer = try c.decode(String.self, forKey: .manufacturer)
        model = try c.decode(String.self, forKey: .model)
        sensor = try c.decode(SensorSpec.self, forKey: .sensor)
        recordingModes = try c.decode([RecordingMode].self, forKey: .recordingModes)
        commonDeliverables = try c.decodeIfPresent([String].self, forKey: .commonDeliverables) ?? []
        source = try c.decodeIfPresent(CameraSource.self, forKey: .source) ?? .bundled
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
