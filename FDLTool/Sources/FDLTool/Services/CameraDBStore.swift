import Foundation

@MainActor
class CameraDBStore: ObservableObject {
    @Published var cameras: [CameraSpec] = []
    @Published var isLoaded = false
    @Published var databaseVersion: String = ""
    @Published var lastUpdated: String = ""
    @Published var errorMessage: String?

    /// All unique manufacturers, sorted
    var manufacturers: [String] {
        Array(Set(cameras.map(\.manufacturer))).sorted()
    }

    // MARK: - Loading

    /// Load from a JSON file at a given URL.
    func load(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let db = try JSONDecoder().decode(CameraDatabase.self, from: data)
            cameras = db.cameras
            databaseVersion = db.version
            lastUpdated = db.lastUpdated
            isLoaded = true
        } catch {
            errorMessage = "Failed to load camera database: \(error.localizedDescription)"
        }
    }

    /// Load from the bundled cameras.json in the resources directory.
    /// Tries several known paths: bundle resource, project resources dir, working directory.
    func loadBundled() {
        // 1. Try app bundle resource
        if let bundlePath = Bundle.main.url(forResource: "cameras", withExtension: "json") {
            load(from: bundlePath)
            if isLoaded { return }
        }

        // 2. Try known development paths relative to executable
        let candidatePaths = [
            "../../../resources/camera_db/cameras.json",   // relative from .build/debug
            "resources/camera_db/cameras.json",             // from project root
        ]

        let executableURL = Bundle.main.executableURL?.deletingLastPathComponent()
        for relative in candidatePaths {
            if let base = executableURL {
                let url = base.appendingPathComponent(relative).standardized
                if FileManager.default.fileExists(atPath: url.path) {
                    load(from: url)
                    if isLoaded { return }
                }
            }
        }

        // 3. Try environment variable
        if let envPath = ProcessInfo.processInfo.environment["FDL_CAMERA_DB"] {
            let url = URL(fileURLWithPath: envPath)
            if FileManager.default.fileExists(atPath: url.path) {
                load(from: url)
                if isLoaded { return }
            }
        }

        // 4. If still not loaded, just mark as loaded with empty data (no cameras available)
        if !isLoaded {
            isLoaded = true
            errorMessage = "Camera database not found. Set FDL_CAMERA_DB environment variable to the path of cameras.json."
        }
    }

    // MARK: - Search & Filter

    /// Search cameras by query string (matches manufacturer, model, sensor name).
    func search(query: String) -> [CameraSpec] {
        guard !query.isEmpty else { return cameras }
        let lowered = query.lowercased()
        return cameras.filter {
            $0.manufacturer.lowercased().contains(lowered) ||
            $0.model.lowercased().contains(lowered) ||
            $0.sensor.name.lowercased().contains(lowered)
        }
    }

    /// Filter cameras by manufacturer.
    func cameras(byManufacturer manufacturer: String) -> [CameraSpec] {
        cameras.filter { $0.manufacturer == manufacturer }
    }

    /// Group cameras by manufacturer, sorted.
    func camerasGroupedByManufacturer() -> [(manufacturer: String, cameras: [CameraSpec])] {
        let grouped = Dictionary(grouping: cameras, by: \.manufacturer)
        return grouped.keys.sorted().map { key in
            (manufacturer: key, cameras: grouped[key]!.sorted { $0.model < $1.model })
        }
    }

    /// Look up a specific camera by ID.
    func camera(byID id: String) -> CameraSpec? {
        cameras.first { $0.id == id }
    }

    /// Find recording modes for a camera that match a given resolution.
    func recordingModes(forCameraID cameraID: String, matchingWidth width: Int, height: Int) -> [RecordingMode] {
        guard let camera = camera(byID: cameraID) else { return [] }
        return camera.recordingModes.filter {
            $0.activePhotosites.width == width && $0.activePhotosites.height == height
        }
    }
}
