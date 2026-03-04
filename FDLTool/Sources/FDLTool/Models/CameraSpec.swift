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
    var source: CameraSource
    /// Which data sources contributed to this camera (e.g. "Bundled", "MatchMove Machine", "CineD").
    var syncSources: [String]
    /// Extra metadata from CineD or other sources.
    var releaseDate: String?
    var lensMount: String?
    var baseSensitivity: String?

    enum CameraSource: String, Codable {
        case bundled
        case synced
        case custom
    }

    enum CodingKeys: String, CodingKey {
        case id, manufacturer, model, sensor, source
        case recordingModes = "recording_modes"
        case syncSources = "sync_sources"
        case releaseDate = "release_date"
        case lensMount = "lens_mount"
        case baseSensitivity = "base_sensitivity"
    }

    init(id: String, manufacturer: String, model: String, sensor: SensorSpec,
         recordingModes: [RecordingMode],
         source: CameraSource = .bundled, syncSources: [String] = []) {
        self.id = id
        self.manufacturer = manufacturer
        self.model = model
        self.sensor = sensor
        self.recordingModes = recordingModes
        self.source = source
        self.syncSources = syncSources
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        manufacturer = try c.decode(String.self, forKey: .manufacturer)
        model = try c.decode(String.self, forKey: .model)
        sensor = try c.decode(SensorSpec.self, forKey: .sensor)
        recordingModes = try c.decode([RecordingMode].self, forKey: .recordingModes)
        source = try c.decodeIfPresent(CameraSource.self, forKey: .source) ?? .bundled
        syncSources = try c.decodeIfPresent([String].self, forKey: .syncSources) ?? []
        releaseDate = try c.decodeIfPresent(String.self, forKey: .releaseDate)
        lensMount = try c.decodeIfPresent(String.self, forKey: .lensMount)
        baseSensitivity = try c.decodeIfPresent(String.self, forKey: .baseSensitivity)
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
