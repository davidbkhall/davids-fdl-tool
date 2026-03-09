import Foundation

/// Syncs camera data from the CineD Camera Database (cined.com/camera-database/).
/// Parses HTML pages to extract camera metadata and recording modes.
@MainActor
class CineDSyncService: ObservableObject {
    @Published var isSyncing = false
    @Published var syncProgress: String = ""
    @Published var lastSyncError: String?

    static let sourceName = "CineD"
    private let baseURL = URL(string: "https://www.cined.com/camera-database/")!
    private var sessionCookies: [HTTPCookie] = []

    // MARK: - Parsed Data Structures

    struct CineDCamera {
        let manufacturer: String
        let model: String
        let slug: String
        var hasLabTest: Bool = false
    }

    struct CineDCameraDetail {
        var releaseDate: String?
        var sensorDescription: String?
        var sensorWidthMM: Double = 0
        var sensorHeightMM: Double = 0
        var lensMount: String?
        var baseSensitivity: String?
    }

    struct CineDRecordingMode {
        let sensorModeName: String
        let resolution: String
        let widthPx: Int
        let heightPx: Int
        let aspectRatio: String
        let codec: String
        let frameRate: String
        let maxFPSValue: Double
        let sampling: String
        let bitDepth: String
        let fileFormat: String
    }

    // MARK: - Login

    private func login(email: String, password: String) async throws {
        guard !email.isEmpty, !password.isEmpty else { return }

        let loginURL = URL(string: "https://www.cined.com/wp-login.php")!
        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? password
        let body = "log=\(encodedEmail)&pwd=\(encodedPassword)&wp-submit=Log+In&redirect_to=%2Fcamera-database%2F"
        request.httpBody = body.data(using: .utf8)

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        let session = URLSession(configuration: config)

        let (_, response) = try await session.data(for: request)
        if let httpResp = response as? HTTPURLResponse,
           let headerFields = httpResp.allHeaderFields as? [String: String],
           let url = httpResp.url {
            sessionCookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
        }
    }

    private func fetchPage(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        if !sessionCookies.isEmpty {
            let cookieHeader = sessionCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Sync All

    func syncAll(email: String, password: String, cameraDBStore: CameraDBStore) async {
        isSyncing = true
        lastSyncError = nil
        syncProgress = "Connecting to CineD..."

        do {
            if !email.isEmpty && !password.isEmpty {
                syncProgress = "Logging in to CineD..."
                try await login(email: email, password: password)
            }

            syncProgress = "Fetching camera list..."
            let cameras = try await fetchCameraList()
            syncProgress = "Found \(cameras.count) cameras. Fetching details..."

            var specs: [CameraSpec] = []
            for (index, camera) in cameras.enumerated() {
                if index % 5 == 0 {
                    syncProgress = "Fetching details... (\(index)/\(cameras.count)): \(camera.manufacturer) \(camera.model)"
                }

                do {
                    let detail = try await fetchCameraDetail(slug: camera.slug)
                    let modes = try await fetchRecordingModes(slug: camera.slug)
                    if let spec = mapToCameraSpec(camera: camera, detail: detail, modes: modes) {
                        specs.append(spec)
                    }
                } catch {
                    continue
                }

                if index % 3 == 2 {
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }

            syncProgress = "Merging \(specs.count) cameras..."
            cameraDBStore.mergeFromCineD(specs)

        } catch {
            lastSyncError = error.localizedDescription
            syncProgress = "Sync failed"
        }

        isSyncing = false
    }

    /// Sync a single camera by its CineD slug.
    func syncCamera(slug: String, email: String, password: String, cameraDBStore: CameraDBStore) async throws {
        if !email.isEmpty && !password.isEmpty {
            try await login(email: email, password: password)
        }

        let cameras = try await fetchCameraList()
        guard let camera = cameras.first(where: { $0.slug == slug }) else {
            throw URLError(.resourceUnavailable)
        }

        let detail = try await fetchCameraDetail(slug: slug)
        let modes = try await fetchRecordingModes(slug: slug)
        guard let spec = mapToCameraSpec(camera: camera, detail: detail, modes: modes) else {
            throw URLError(.cannotParseResponse)
        }
        cameraDBStore.mergeFromCineD([spec])
    }

    // MARK: - Parse Camera List

    private func fetchCameraList() async throws -> [CineDCamera] {
        let html = try await fetchPage(url: baseURL)
        return parseCameraList(html: html)
    }

    func parseCameraList(html: String) -> [CineDCamera] {
        var cameras: [CineDCamera] = []

        let sections = html.components(separatedBy: "choose ")
        for section in sections.dropFirst() {
            let headerEnd = section.range(of: " camera:")
            guard let headerEnd else { continue }
            let manufacturer = String(section[section.startIndex..<headerEnd.lowerBound]).trimmingCharacters(in: .whitespaces)

            let sectionStr = String(section)
            let nameAndLinkPattern = #"(?:LAB)?([^<\[\]]+?)(?:NEW)?\]\(https://www\.cined\.com/camera-database/\?camera=([\w\-\[\]/%.]+)\)"#
            let nameRegex = try? NSRegularExpression(pattern: nameAndLinkPattern)

            if let nameRegex {
                let matches = nameRegex.matches(in: sectionStr, range: NSRange(sectionStr.startIndex..., in: sectionStr))
                for match in matches {
                    guard match.numberOfRanges >= 3,
                          let nameRange = Range(match.range(at: 1), in: sectionStr),
                          let slugRange = Range(match.range(at: 2), in: sectionStr) else { continue }
                    let model = String(sectionStr[nameRange]).trimmingCharacters(in: .whitespaces)
                    let slug = String(sectionStr[slugRange])
                    if !model.isEmpty {
                        cameras.append(CineDCamera(manufacturer: manufacturer, model: model, slug: slug))
                    }
                }
            }
        }

        return cameras
    }

    // MARK: - Parse Camera Detail

    private func fetchCameraDetail(slug: String) async throws -> CineDCameraDetail {
        let url = URL(string: "https://www.cined.com/camera-database/?camera=\(slug)")!
        let html = try await fetchPage(url: url)
        return parseCameraDetail(html: html)
    }

    func parseCameraDetail(html: String) -> CineDCameraDetail {
        var detail = CineDCameraDetail()

        if let match = html.range(of: #"Released:\s*([A-Za-z]+ \d{4})"#, options: .regularExpression) {
            let full = String(html[match])
            detail.releaseDate = full.replacingOccurrences(of: "Released:", with: "").trimmingCharacters(in: .whitespaces)
        }

        if let match = html.range(of: #"Sensor:\s*(.+?)(?:Lens|Base|Weight|Dim)"#, options: .regularExpression) {
            let full = String(html[match])
            let sensorStr = full.replacingOccurrences(of: #"Sensor:\s*"#, with: "", options: .regularExpression)
            detail.sensorDescription = sensorStr.trimmingCharacters(in: .whitespaces)

            let mmPattern = #"\((\d+\.?\d*)\s*x\s*(\d+\.?\d*)\s*mm\)"#
            if let mmRegex = try? NSRegularExpression(pattern: mmPattern),
               let mmMatch = mmRegex.firstMatch(in: full, range: NSRange(full.startIndex..., in: full)) {
                if let wRange = Range(mmMatch.range(at: 1), in: full),
                   let hRange = Range(mmMatch.range(at: 2), in: full) {
                    detail.sensorWidthMM = Double(full[wRange]) ?? 0
                    detail.sensorHeightMM = Double(full[hRange]) ?? 0
                }
            }
        }

        if let match = html.range(of: #"Lens Mount:\s*([A-Za-z, /]+?)(?:Base|Weight|Dim|\d)"#, options: .regularExpression) {
            let full = String(html[match])
            detail.lensMount = full.replacingOccurrences(of: #"Lens Mount:\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: .decimalDigits)
                .trimmingCharacters(in: .whitespaces)
        }

        if let match = html.range(of: #"Base Sensitivity:\s*(ISO \d+)"#, options: .regularExpression) {
            detail.baseSensitivity = String(html[match]).replacingOccurrences(of: "Base Sensitivity:", with: "").trimmingCharacters(in: .whitespaces)
        }

        return detail
    }

    // MARK: - Parse Recording Modes

    private func fetchRecordingModes(slug: String) async throws -> [CineDRecordingMode] {
        let url = URL(string: "https://www.cined.com/camera-database/?recording-modes=\(slug)")!
        let html = try await fetchPage(url: url)
        return parseRecordingModes(html: html)
    }

    func parseRecordingModes(html: String) -> [CineDRecordingMode] {
        var modes: [CineDRecordingMode] = []

        let rowPattern =
            #"\|\s*([^|]+?)\s*\|\s*(\w.*?\(\d+\s*x\s*\d+\))\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*(\d+\.?\d*p?)\s*\|"#
            + #"(?:\s*([^|]*?)\s*\|)?\s*([^|]*?)\s*\|\s*(\d+\s*bit)\s*\|\s*([^|]+?)\s*\|"#

        guard let regex = try? NSRegularExpression(pattern: rowPattern) else { return modes }

        let lines = html.components(separatedBy: "\n")
        for line in lines {
            if line.contains("Sensor Mode") && line.contains("Resolution") { continue }
            if line.contains("---") { continue }

            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))

            for match in matches {
                func group(_ i: Int) -> String {
                    guard i < match.numberOfRanges else { return "" }
                    let range = match.range(at: i)
                    guard range.location != NSNotFound else { return "" }
                    return nsLine.substring(with: range).trimmingCharacters(in: .whitespaces)
                }

                let sensorMode = group(1)
                let resolutionFull = group(2)
                let aspectRatio = group(3)
                let codec = group(4)
                let frameRateStr = group(5)
                let sampling = group(6)
                let bitDepth = group(8)
                let fileFormat = group(9)

                let resDimPattern = #"\((\d+)\s*x\s*(\d+)\)"#
                var w = 0, h = 0
                if let resRegex = try? NSRegularExpression(pattern: resDimPattern),
                   let resMatch = resRegex.firstMatch(in: resolutionFull, range: NSRange(resolutionFull.startIndex..., in: resolutionFull)) {
                    if let wRange = Range(resMatch.range(at: 1), in: resolutionFull),
                       let hRange = Range(resMatch.range(at: 2), in: resolutionFull) {
                        w = Int(resolutionFull[wRange]) ?? 0
                        h = Int(resolutionFull[hRange]) ?? 0
                    }
                }

                let fpsNumStr = frameRateStr.replacingOccurrences(of: "p", with: "")
                let fpsVal = Double(fpsNumStr) ?? 0

                guard w > 0 && h > 0 else { continue }

                modes.append(CineDRecordingMode(
                    sensorModeName: sensorMode,
                    resolution: resolutionFull,
                    widthPx: w,
                    heightPx: h,
                    aspectRatio: aspectRatio,
                    codec: codec,
                    frameRate: frameRateStr,
                    maxFPSValue: fpsVal,
                    sampling: sampling,
                    bitDepth: bitDepth,
                    fileFormat: fileFormat
                ))
            }
        }

        return modes
    }

    // MARK: - Mapping to CameraSpec

    private func mapToCameraSpec(camera: CineDCamera, detail: CineDCameraDetail, modes: [CineDRecordingMode]) -> CameraSpec? {
        let grouped = Dictionary(grouping: modes, by: { "\($0.sensorModeName)_\($0.widthPx)x\($0.heightPx)" })

        var recordingModes: [RecordingMode] = []
        for (_, group) in grouped {
            guard let first = group.first else { continue }

            let maxFPS = Int(group.map(\.maxFPSValue).max() ?? 0)
            let codecs = Array(Set(group.map(\.codec))).sorted()
            let samplingValues = Array(Set(group.compactMap { $0.sampling.isEmpty ? nil : $0.sampling }))

            let modeID = "cined-\(camera.slug)-\(first.sensorModeName.replacingOccurrences(of: " ", with: "_"))-\(first.widthPx)x\(first.heightPx)"
                .lowercased()

            let sensorW = detail.sensorWidthMM
            let sensorH = detail.sensorHeightMM

            var mode = RecordingMode(
                id: modeID,
                name: first.sensorModeName.isEmpty ? "\(first.widthPx)x\(first.heightPx)" : first.sensorModeName,
                activePhotosites: Dimensions(width: first.widthPx, height: first.heightPx),
                activeImageAreaMM: PhysicalDimensions(width: sensorW, height: sensorH),
                maxFPS: maxFPS,
                codecOptions: codecs,
                source: .synced,
                syncSources: [Self.sourceName]
            )
            mode.sensorModeName = first.sensorModeName
            mode.aspectRatio = first.aspectRatio
            mode.bitDepth = first.bitDepth
            mode.fileFormat = first.fileFormat
            mode.sampling = samplingValues.first

            recordingModes.append(mode)
        }

        if recordingModes.isEmpty { return nil }

        let maxMode = recordingModes.max(by: {
            $0.activePhotosites.width * $0.activePhotosites.height < $1.activePhotosites.width * $1.activePhotosites.height
        })!

        let pixelPitch: Double
        if detail.sensorWidthMM > 0 && maxMode.activePhotosites.width > 0 {
            pixelPitch = (detail.sensorWidthMM / Double(maxMode.activePhotosites.width)) * 1000.0
        } else {
            pixelPitch = 0
        }

        var spec = CameraSpec(
            id: "cined-\(camera.slug)".lowercased(),
            manufacturer: camera.manufacturer,
            model: camera.model,
            sensor: SensorSpec(
                name: detail.sensorDescription ?? "\(maxMode.activePhotosites.width)x\(maxMode.activePhotosites.height)",
                photositeDimensions: maxMode.activePhotosites,
                physicalDimensionsMM: PhysicalDimensions(width: detail.sensorWidthMM, height: detail.sensorHeightMM),
                pixelPitchUM: pixelPitch
            ),
            recordingModes: recordingModes,
            source: .synced,
            syncSources: [Self.sourceName]
        )
        spec.releaseDate = detail.releaseDate
        spec.lensMount = detail.lensMount
        spec.baseSensitivity = detail.baseSensitivity

        return spec
    }
}
