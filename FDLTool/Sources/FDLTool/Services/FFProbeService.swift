import Foundation

/// Wrapper for ffprobe subprocess calls.
/// Used by the Clip ID tool to probe video file metadata.
actor FFProbeService {
    /// Check if ffprobe is available on the system.
    func isAvailable() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ffprobe", "-version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Probe a single video file and return clip info.
    func probe(filePath: String) async throws -> ClipInfo {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "ffprobe",
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            filePath
        ]
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw FFProbeError.probeFailure(filePath)
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        return parseProbeResult(json: json, filePath: filePath)
    }

    private func parseProbeResult(json: [String: Any], filePath: String) -> ClipInfo {
        let streams = json["streams"] as? [[String: Any]] ?? []
        let videoStream = streams.first { ($0["codec_type"] as? String) == "video" } ?? [:]
        let format = json["format"] as? [String: Any] ?? [:]

        let width = videoStream["width"] as? Int ?? 0
        let height = videoStream["height"] as? Int ?? 0
        let codec = videoStream["codec_name"] as? String ?? "unknown"

        // Parse frame rate from r_frame_rate (e.g., "24000/1001")
        var fps: Double = 0
        if let rFrameRate = videoStream["r_frame_rate"] as? String {
            let parts = rFrameRate.split(separator: "/")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den != 0 {
                fps = num / den
            }
        }

        let duration = Double(format["duration"] as? String ?? "0") ?? 0
        let fileSize = Int64(format["size"] as? String ?? "0") ?? 0
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent

        return ClipInfo(
            filePath: filePath,
            fileName: fileName,
            width: width,
            height: height,
            codec: codec,
            fps: fps,
            duration: duration,
            fileSize: fileSize
        )
    }
}

enum FFProbeError: Error, LocalizedError {
    case notInstalled
    case probeFailure(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "ffprobe is not installed"
        case .probeFailure(let path): return "Failed to probe: \(path)"
        }
    }
}
