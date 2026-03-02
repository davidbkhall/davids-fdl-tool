import Foundation

struct RecordingMode: Codable, Identifiable {
    var id: String
    var name: String
    var activePhotosites: Dimensions
    var activeImageAreaMM: PhysicalDimensions
    var maxFPS: Int
    var codecOptions: [String]
    var source: ModeSource
    /// Snapshot of the original synced values for conflict detection.
    var syncedSnapshot: RecordingModeSnapshot?

    enum ModeSource: String, Codable {
        case bundled
        case synced
        case custom
        case modified
    }

    enum CodingKeys: String, CodingKey {
        case id, name, source
        case activePhotosites = "active_photosites"
        case activeImageAreaMM = "active_image_area_mm"
        case maxFPS = "max_fps"
        case codecOptions = "codec_options"
        case syncedSnapshot = "synced_snapshot"
    }

    init(id: String, name: String, activePhotosites: Dimensions,
         activeImageAreaMM: PhysicalDimensions, maxFPS: Int,
         codecOptions: [String], source: ModeSource = .bundled) {
        self.id = id
        self.name = name
        self.activePhotosites = activePhotosites
        self.activeImageAreaMM = activeImageAreaMM
        self.maxFPS = maxFPS
        self.codecOptions = codecOptions
        self.source = source
        self.syncedSnapshot = nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        activePhotosites = try c.decode(Dimensions.self, forKey: .activePhotosites)
        activeImageAreaMM = try c.decode(PhysicalDimensions.self, forKey: .activeImageAreaMM)
        maxFPS = try c.decodeIfPresent(Int.self, forKey: .maxFPS) ?? 0
        codecOptions = try c.decodeIfPresent([String].self, forKey: .codecOptions) ?? []
        source = try c.decodeIfPresent(ModeSource.self, forKey: .source) ?? .bundled
        syncedSnapshot = try c.decodeIfPresent(RecordingModeSnapshot.self, forKey: .syncedSnapshot)
    }
}

/// Lightweight snapshot of synced values for conflict comparison.
struct RecordingModeSnapshot: Codable, Equatable {
    let name: String
    let resWidth: Int
    let resHeight: Int
    let sensorWidth: Double
    let sensorHeight: Double
    let maxFPS: Int

    init(from mode: RecordingMode) {
        self.name = mode.name
        self.resWidth = mode.activePhotosites.width
        self.resHeight = mode.activePhotosites.height
        self.sensorWidth = mode.activeImageAreaMM.width
        self.sensorHeight = mode.activeImageAreaMM.height
        self.maxFPS = mode.maxFPS
    }

    func matches(_ mode: RecordingMode) -> Bool {
        name == mode.name &&
        resWidth == mode.activePhotosites.width &&
        resHeight == mode.activePhotosites.height &&
        abs(sensorWidth - mode.activeImageAreaMM.width) < 0.01 &&
        abs(sensorHeight - mode.activeImageAreaMM.height) < 0.01
    }
}
