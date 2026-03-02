import Foundation

/// Represents a conflict between a locally modified recording mode and an incoming API update.
struct SyncConflict: Identifiable {
    let id = UUID()
    let cameraID: String
    let cameraLabel: String
    let modeID: String
    let localMode: RecordingMode
    let remoteMode: RecordingMode
}

/// Resolution choices for a single sync conflict.
enum ConflictResolution {
    case keepLocal
    case acceptRemote
}

@MainActor
class CameraDBStore: ObservableObject {
    @Published var cameras: [CameraSpec] = []
    @Published var isLoaded = false
    @Published var databaseVersion: String = ""
    @Published var lastUpdated: String = ""
    @Published var errorMessage: String?
    @Published var pendingConflicts: [SyncConflict] = []

    /// All unique manufacturers, sorted
    var manufacturers: [String] {
        Array(Set(cameras.map(\.manufacturer))).sorted()
    }

    // MARK: - Persistence Paths

    static let appSupportDir: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FDLTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let localCameraDBURL: URL = {
        appSupportDir.appendingPathComponent("cameras_local.json")
    }()

    // MARK: - Loading

    /// Load from a JSON file at a given URL (bundled format).
    func load(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let db = try JSONDecoder().decode(CameraDatabase.self, from: data)
            var bundled = db.cameras
            for i in bundled.indices {
                bundled[i].source = .bundled
            }
            cameras = bundled
            databaseVersion = db.version
            lastUpdated = db.lastUpdated
            isLoaded = true
        } catch {
            errorMessage = "Failed to load camera database: \(error.localizedDescription)"
        }
    }

    /// Load from the bundled cameras.json, then overlay any locally persisted cameras on top.
    func loadBundled() {
        // 1. Try app bundle resource
        if let bundlePath = Bundle.main.url(forResource: "cameras", withExtension: "json") {
            load(from: bundlePath)
        }

        // 2. Try known development paths relative to executable
        if !isLoaded {
            let candidatePaths = [
                "../../../resources/camera_db/cameras.json",
                "resources/camera_db/cameras.json",
            ]
            let executableURL = Bundle.main.executableURL?.deletingLastPathComponent()
            for relative in candidatePaths {
                if let base = executableURL {
                    let url = base.appendingPathComponent(relative).standardized
                    if FileManager.default.fileExists(atPath: url.path) {
                        load(from: url)
                        if isLoaded { break }
                    }
                }
            }
        }

        // 3. Try environment variable
        if !isLoaded {
            if let envPath = ProcessInfo.processInfo.environment["FDL_CAMERA_DB"] {
                let url = URL(fileURLWithPath: envPath)
                if FileManager.default.fileExists(atPath: url.path) {
                    load(from: url)
                }
            }
        }

        // 4. Even with no bundled data, mark as loaded
        if !isLoaded {
            isLoaded = true
        }

        // 5. Overlay locally persisted cameras (synced + custom)
        loadLocalCameras()
    }

    /// Load locally persisted cameras (synced/custom) and merge them in.
    private func loadLocalCameras() {
        let url = Self.localCameraDBURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let local = try JSONDecoder().decode([CameraSpec].self, from: data)
            mergeFromLocal(local)
        } catch {
            print("Failed to load local camera DB: \(error)")
        }
    }

    /// Save all non-bundled cameras to disk.
    func saveLocalCameras() {
        let local = cameras.filter { $0.source != .bundled }
        do {
            let data = try JSONEncoder().encode(local)
            try data.write(to: Self.localCameraDBURL, options: .atomic)
        } catch {
            print("Failed to save local camera DB: \(error)")
        }
    }

    private func mergeFromLocal(_ localCameras: [CameraSpec]) {
        var existingByID = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        for cam in localCameras {
            existingByID[cam.id] = cam
        }
        cameras = Array(existingByID.values)
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

    // MARK: - API Sync

    /// Merge cameras fetched from the API into the store and persist.
    /// Detects conflicts for locally modified recording modes whose API versions have changed.
    /// Deduplicates cameras with matching manufacturer+model (case-insensitive).
    func mergeFromAPI(_ apiCameras: [CameraSpec]) {
        var existingByID = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        var conflicts: [SyncConflict] = []

        // Build a lookup of existing cameras by normalized manufacturer+model for dedup
        var nameToID: [String: String] = [:]
        for cam in cameras {
            let key = "\(cam.manufacturer)|\(cam.model)".lowercased()
            nameToID[key] = cam.id
        }

        for var cam in apiCameras {
            cam.source = .synced

            // Deduplicate: if a bundled camera with the same name exists under a different ID, remove it
            let key = "\(cam.manufacturer)|\(cam.model)".lowercased()
            if let existingID = nameToID[key], existingID != cam.id {
                if let existing = existingByID[existingID], existing.source == .bundled {
                    existingByID.removeValue(forKey: existingID)
                }
            }
            nameToID[key] = cam.id

            if let existing = existingByID[cam.id] {
                let modifiedModes = existing.recordingModes.filter { $0.source == .modified }
                if !modifiedModes.isEmpty {
                    let remoteByID = Dictionary(uniqueKeysWithValues: cam.recordingModes.map { ($0.id, $0) })
                    var mergedModes = cam.recordingModes
                    for localMode in modifiedModes {
                        if let remoteMode = remoteByID[localMode.id],
                           let snapshot = localMode.syncedSnapshot,
                           !snapshot.matches(remoteMode) {
                            conflicts.append(SyncConflict(
                                cameraID: cam.id,
                                cameraLabel: "\(cam.manufacturer) \(cam.model)",
                                modeID: localMode.id,
                                localMode: localMode,
                                remoteMode: remoteMode
                            ))
                            if let idx = mergedModes.firstIndex(where: { $0.id == localMode.id }) {
                                mergedModes[idx] = localMode
                            }
                        } else if remoteByID[localMode.id] != nil {
                            if let idx = mergedModes.firstIndex(where: { $0.id == localMode.id }) {
                                mergedModes[idx] = localMode
                            }
                        } else {
                            mergedModes.append(localMode)
                        }
                    }
                    cam.recordingModes = mergedModes
                }
            }
            existingByID[cam.id] = cam
        }

        cameras = Array(existingByID.values)
        isLoaded = true
        pendingConflicts = conflicts
        saveLocalCameras()
    }

    /// Merge a single camera from the API (for per-camera resync).
    func mergeSingleFromAPI(_ apiCamera: CameraSpec) {
        mergeFromAPI([apiCamera])
    }

    /// Replace a single recording mode from the API for a given camera.
    func resyncRecordingMode(cameraID: String, remoteMode: RecordingMode) {
        guard let camIdx = cameras.firstIndex(where: { $0.id == cameraID }) else { return }
        if let modeIdx = cameras[camIdx].recordingModes.firstIndex(where: { $0.id == remoteMode.id }) {
            var mode = remoteMode
            mode.source = .synced
            mode.syncedSnapshot = nil
            cameras[camIdx].recordingModes[modeIdx] = mode
        }
        saveLocalCameras()
    }

    // MARK: - Custom Cameras

    /// Add a user-created custom camera and persist.
    func addCustomCamera(_ camera: CameraSpec) {
        var cam = camera
        cam.source = .custom
        cameras.append(cam)
        saveLocalCameras()
    }

    /// Remove a non-bundled camera and persist.
    func removeCamera(byID id: String) {
        cameras.removeAll { $0.id == id && $0.source != .bundled }
        saveLocalCameras()
    }

    func updateCamera(_ camera: CameraSpec) {
        if let idx = cameras.firstIndex(where: { $0.id == camera.id }) {
            cameras[idx] = camera
            saveLocalCameras()
        }
    }

    func addRecordingMode(toCameraID cameraID: String, mode: RecordingMode) {
        if let idx = cameras.firstIndex(where: { $0.id == cameraID }) {
            cameras[idx].recordingModes.append(mode)
            saveLocalCameras()
        }
    }

    func removeRecordingMode(fromCameraID cameraID: String, modeID: String) {
        if let idx = cameras.firstIndex(where: { $0.id == cameraID }) {
            cameras[idx].recordingModes.removeAll { $0.id == modeID }
            saveLocalCameras()
        }
    }

    // MARK: - Conflict Resolution

    func resolveConflict(_ conflict: SyncConflict, resolution: ConflictResolution) {
        guard let camIdx = cameras.firstIndex(where: { $0.id == conflict.cameraID }),
              let modeIdx = cameras[camIdx].recordingModes.firstIndex(where: { $0.id == conflict.modeID }) else { return }

        switch resolution {
        case .keepLocal:
            break
        case .acceptRemote:
            var accepted = conflict.remoteMode
            accepted.source = .synced
            accepted.syncedSnapshot = nil
            cameras[camIdx].recordingModes[modeIdx] = accepted
        }

        pendingConflicts.removeAll { $0.id == conflict.id }
        saveLocalCameras()
    }

    func resolveAllConflicts(resolution: ConflictResolution) {
        for conflict in pendingConflicts {
            guard let camIdx = cameras.firstIndex(where: { $0.id == conflict.cameraID }),
                  let modeIdx = cameras[camIdx].recordingModes.firstIndex(where: { $0.id == conflict.modeID }) else { continue }
            if case .acceptRemote = resolution {
                var accepted = conflict.remoteMode
                accepted.source = .synced
                accepted.syncedSnapshot = nil
                cameras[camIdx].recordingModes[modeIdx] = accepted
            }
        }
        pendingConflicts.removeAll()
        saveLocalCameras()
    }
}
