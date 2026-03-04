import Foundation

/// Syncs camera data from the matchmovemachine.com Camera Database API.
/// Maps API responses to the existing `CameraSpec` / `RecordingMode` models
/// and merges them into the local `CameraDBStore`.
@MainActor
class CameraDBSyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var syncProgress: String = ""
    @Published var lastSyncError: String?

    private let baseURL = URL(string: "https://camdb.matchmovemachine.com")!

    // MARK: - API Response Models

    struct APICamera: Codable {
        let id: Int
        let make: String
        let name: String
        let camType: String

        enum CodingKeys: String, CodingKey {
            case id, make, name
            case camType = "cam_type"
        }
    }

    struct APISensor: Codable {
        let id: Int
        let camId: Int
        let sensorWidth: Double
        let sensorHeight: Double
        let resWidth: Int
        let resHeight: Int
        let modeName: String
        let formatAspect: String

        enum CodingKeys: String, CodingKey {
            case id
            case camId = "cam_id"
            case sensorWidth = "sensor_width"
            case sensorHeight = "sensor_height"
            case resWidth = "res_width"
            case resHeight = "res_height"
            case modeName = "mode_name"
            case formatAspect = "format_aspect"
        }
    }

    struct APICameraWithSensors: Codable {
        let camera: APICamera
        let sensors: [APISensor]
    }

    struct APISensorMatch: Codable {
        let id: Int
        let camId: Int
        let sensorWidth: Double
        let sensorHeight: Double
        let resWidth: Int
        let resHeight: Int
        let modeName: String
        let formatAspect: String
        let cameraName: String?
        let cameraMake: String?

        enum CodingKeys: String, CodingKey {
            case id
            case camId = "cam_id"
            case sensorWidth = "sensor_width"
            case sensorHeight = "sensor_height"
            case resWidth = "res_width"
            case resHeight = "res_height"
            case modeName = "mode_name"
            case formatAspect = "format_aspect"
            case cameraName = "camera_name"
            case cameraMake = "camera_make"
        }
    }

    // MARK: - Sync All

    func syncAll(cameraDBStore: CameraDBStore) async {
        isSyncing = true
        lastSyncError = nil
        syncProgress = "Fetching camera list..."

        do {
            let cameras = try await fetchCameras()
            syncProgress = "Found \(cameras.count) cameras. Fetching sensors..."

            var specs: [CameraSpec] = []
            for (index, camera) in cameras.enumerated() {
                if index % 10 == 0 {
                    syncProgress = "Fetching sensors... (\(index)/\(cameras.count))"
                }

                do {
                    let detail = try await fetchSensors(cameraId: camera.id)
                    if let spec = mapToCameraSpec(camera: camera, sensors: detail.sensors) {
                        specs.append(spec)
                    }
                } catch {
                    // Skip cameras whose sensors fail to load
                    continue
                }

                // Small delay to be polite to the API
                if index % 5 == 4 {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }

            syncProgress = "Loaded \(specs.count) cameras with sensor data"
            cameraDBStore.mergeFromAPI(specs)
            cameraDBStore.databaseVersion = "API sync"
            cameraDBStore.lastUpdated = ISO8601DateFormatter().string(from: Date())

        } catch {
            lastSyncError = error.localizedDescription
            syncProgress = "Sync failed"
        }

        isSyncing = false
    }

    // MARK: - Sync Single Camera

    /// Re-sync a single camera by its API ID (the integer portion of "mmm-XX").
    func syncCamera(apiCameraID: Int, cameraDBStore: CameraDBStore) async throws {
        let detail = try await fetchSensors(cameraId: apiCameraID)
        let apiCamera = detail.camera
        guard let spec = mapToCameraSpec(camera: apiCamera, sensors: detail.sensors) else {
            throw URLError(.cannotParseResponse)
        }
        cameraDBStore.mergeSingleFromAPI(spec)
    }

    /// Re-sync a single recording mode by fetching the parent camera's sensors.
    func syncRecordingMode(apiCameraID: Int, modeID: String, cameraDBStore: CameraDBStore) async throws {
        let detail = try await fetchSensors(cameraId: apiCameraID)
        let apiCamera = detail.camera
        guard let spec = mapToCameraSpec(camera: apiCamera, sensors: detail.sensors) else {
            throw URLError(.cannotParseResponse)
        }
        if let remoteMode = spec.recordingModes.first(where: { $0.id == modeID }) {
            cameraDBStore.resyncRecordingMode(cameraID: spec.id, remoteMode: remoteMode)
        }
    }

    // MARK: - Search by Resolution

    func searchByResolution(width: Int, height: Int) async throws -> [APISensorMatch] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/sensors/search/"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "res_width", value: String(width)),
            URLQueryItem(name: "res_height", value: String(height)),
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode([APISensorMatch].self, from: data)
    }

    // MARK: - API Fetchers

    private func fetchCameras() async throws -> [APICamera] {
        let url = baseURL.appendingPathComponent("/cameras/")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([APICamera].self, from: data)
    }

    private func fetchSensors(cameraId: Int) async throws -> APICameraWithSensors {
        let url = baseURL.appendingPathComponent("/cameras/\(cameraId)/sensors/")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(APICameraWithSensors.self, from: data)
    }

    // MARK: - Mapping

    private func mapToCameraSpec(camera: APICamera, sensors: [APISensor]) -> CameraSpec? {
        guard !sensors.isEmpty else { return nil }

        let maxSensor = sensors.max(by: { $0.resWidth * $0.resHeight < $1.resWidth * $1.resHeight })!

        let pixelPitch: Double
        if maxSensor.sensorWidth > 0 && maxSensor.resWidth > 0 {
            pixelPitch = (maxSensor.sensorWidth / Double(maxSensor.resWidth)) * 1000.0
        } else {
            pixelPitch = 0
        }

        let modes = sensors.map { sensor -> RecordingMode in
            let imageAreaW = sensor.sensorWidth
            let imageAreaH = sensor.sensorHeight
            return RecordingMode(
                id: "mmm-\(sensor.id)",
                name: sensor.modeName.isEmpty ? "\(sensor.resWidth)x\(sensor.resHeight)" : sensor.modeName,
                activePhotosites: Dimensions(width: sensor.resWidth, height: sensor.resHeight),
                activeImageAreaMM: PhysicalDimensions(width: imageAreaW, height: imageAreaH),
                maxFPS: 0,
                codecOptions: [],
                source: .synced
            )
        }

        return CameraSpec(
            id: "mmm-\(camera.id)",
            manufacturer: camera.make,
            model: camera.name,
            sensor: SensorSpec(
                name: "\(maxSensor.resWidth)x\(maxSensor.resHeight)",
                photositeDimensions: Dimensions(width: maxSensor.resWidth, height: maxSensor.resHeight),
                physicalDimensionsMM: PhysicalDimensions(width: maxSensor.sensorWidth, height: maxSensor.sensorHeight),
                pixelPitchUM: pixelPitch
            ),
            recordingModes: modes,
            source: .synced
        )
    }
}
