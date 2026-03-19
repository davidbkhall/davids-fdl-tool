import Foundation

/// JSON-RPC 2.0 request/response types
struct JSONRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: [String: AnyCodable]
}

struct JSONRPCResponse: Decodable {
    let jsonrpc: String
    let id: Int?
    let result: AnyCodable?
    let error: JSONRPCError?
}

struct JSONRPCError: Decodable, Error, LocalizedError {
    let code: Int
    let message: String
    let data: AnyCodable?

    var errorDescription: String? { message }
}

/// Type-erased Codable wrapper for arbitrary JSON values
struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Unsupported type"))
        }
    }

    // Convenience accessors
    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
    var dictValue: [String: Any]? { value as? [String: Any] }
    var arrayValue: [Any]? { value as? [Any] }
}

enum PythonBridgeError: Error, LocalizedError {
    case notStarted
    case processExited(Int32)
    case encodingError
    case decodingError(String)
    case rpcError(JSONRPCError)
    case timeout

    var errorDescription: String? {
        switch self {
        case .notStarted: return "Python bridge not started"
        case .processExited(let code): return "Python process exited with code \(code)"
        case .encodingError: return "Failed to encode JSON-RPC request"
        case .decodingError(let msg): return "Failed to decode response: \(msg)"
        case .rpcError(let err): return "RPC error \(err.code): \(err.message)"
        case .timeout: return "Request timed out"
        }
    }
}

/// Actor managing the Python subprocess and JSON-RPC communication.
actor PythonBridge {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var nextID = 1
    private var pendingRequests: [Int: CheckedContinuation<JSONRPCResponse, Error>] = [:]
    private var buffer = Data()
    private var isRunning = false

    /// Resolve the path to the Python backend directory.
    /// Checks: environment variable, app bundle resource, paths relative to executable, fallback.
    private func pythonServerPath() -> String? {
        let fm = FileManager.default

        // 1. Explicit environment variable
        if let envPath = ProcessInfo.processInfo.environment["FDL_PYTHON_BACKEND"],
           fm.fileExists(atPath: envPath + "/fdl_backend/server.py") {
            return envPath
        }

        // 2. App bundle resource
        if let bundlePath = Bundle.main.path(forResource: "fdl_backend", ofType: nil) {
            let parent = (bundlePath as NSString).deletingLastPathComponent
            if fm.fileExists(atPath: parent + "/fdl_backend/server.py") {
                return parent
            }
        }

        // 3. Paths relative to the executable (development builds)
        if let execURL = Bundle.main.executableURL?.deletingLastPathComponent() {
            // Try increasingly deep parent traversals to find python_backend as sibling of FDLTool/
            let relatives = [
                "../../python_backend",                // .build/debug/FDLTool → FDLTool/.build → FDLTool → project
                "../../../python_backend",             // one deeper
                "../../../../python_backend",          // .build/X.app/Contents/MacOS → .build → FDLTool → project
                "../../../../../python_backend",       // .build/FDLTool.app/Contents/MacOS → project root
                "../../../../../../python_backend",    // extra depth safety
                "../Resources/python_backend",         // bundled inside .app
            ]
            for relative in relatives {
                let candidate = execURL.appendingPathComponent(relative).standardized
                if fm.fileExists(atPath: candidate.path + "/fdl_backend/server.py") {
                    return candidate.path
                }
            }
        }

        // 3b. Paths relative to the bundle URL (may differ from executable)
        if let bundleURL = Bundle.main.bundleURL.deletingLastPathComponent() as URL? {
            let relatives = [
                "../python_backend",
                "../../python_backend",
                "python_backend",
            ]
            for relative in relatives {
                let candidate = bundleURL.appendingPathComponent(relative).standardized
                if fm.fileExists(atPath: candidate.path + "/fdl_backend/server.py") {
                    return candidate.path
                }
            }
        }

        // 4. Current working directory
        let cwd = fm.currentDirectoryPath + "/python_backend"
        if fm.fileExists(atPath: cwd + "/fdl_backend/server.py") {
            return cwd
        }

        return nil
    }

    func start() throws {
        guard !isRunning else { return }

        guard let backendPath = pythonServerPath() else {
            throw PythonBridgeError.notStarted
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "fdl_backend.server"]
        process.currentDirectoryURL = URL(fileURLWithPath: backendPath)
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Propagate PATH for finding python3, add PYTHONPATH so fdl_backend is importable
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONPATH"] = backendPath
        process.environment = env

        process.terminationHandler = { [weak self] proc in
            Task { [weak self] in
                await self?.handleTermination(exitCode: proc.terminationStatus)
            }
        }

        try process.run()

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.isRunning = true

        // Non-blocking stdout reader. Avoid actor-blocking loops that can stall RPC calls.
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { [weak self] in
                await self?.handleStdoutChunk(data)
            }
        }

        // Stream stderr for live backend trace visibility.
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { [weak self] in
                await self?.handleStderrChunk(data)
            }
        }
    }

    func shutdown() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        stdinPipe?.fileHandleForWriting.closeFile()
        process?.terminate()

        // Fail all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: PythonBridgeError.notStarted)
        }
        pendingRequests.removeAll()

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        isRunning = false
    }

    /// Send a JSON-RPC call and await the response.
    func call(_ method: String, params: [String: Any] = [:]) async throws -> JSONRPCResponse {
        guard isRunning, let stdinPipe = stdinPipe else {
            throw PythonBridgeError.notStarted
        }

        let id = nextID
        nextID += 1

        let request = JSONRPCRequest(
            id: id,
            method: method,
            params: params.mapValues { AnyCodable($0) }
        )

        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(request) else {
            throw PythonBridgeError.encodingError
        }
        data.append(0x0A) // newline delimiter

        let response: JSONRPCResponse = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            stdinPipe.fileHandleForWriting.write(data)
        }

        if let error = response.error {
            throw PythonBridgeError.rpcError(error)
        }

        return response
    }

    /// Convenience: call and extract the result dictionary
    func callForResult(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        let response = try await call(method, params: params)
        return response.result?.dictValue ?? [:]
    }

    // MARK: - Private

    private func handleStdoutChunk(_ data: Data) {
        if data.isEmpty {
            // EOF; process termination handler will clean up.
            return
        }
        buffer.append(data)
        processBuffer()
    }

    private func processBuffer() {
        // Split on newlines — each line is a complete JSON-RPC response
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])

            guard !lineData.isEmpty else { continue }

            do {
                let response = try decodeResponseLine(Data(lineData))
                if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
                    continuation.resume(returning: response)
                }
            } catch {
                print("[PythonBridge] Failed to decode response: \(error)")
                let raw = String(data: Data(lineData), encoding: .utf8) ?? "<non-utf8 response>"
                print("[PythonBridge] Raw: \(raw)")
                appendBackendTrace("[bridge_decode_ignored] \(raw)")
                // Ignore malformed/non-JSON stdout lines and keep waiting for
                // the real JSON-RPC response so unrelated calls are not failed.
            }
        }
    }

    private func decodeResponseLine(_ lineData: Data) throws -> JSONRPCResponse {
        do {
            return try JSONDecoder().decode(JSONRPCResponse.self, from: lineData)
        } catch {
            guard let raw = String(data: lineData, encoding: .utf8),
                  let response = recoverEmbeddedResponse(from: raw) else {
                throw error
            }
            return response
        }
    }

    private func recoverEmbeddedResponse(from raw: String) -> JSONRPCResponse? {
        // Defensive recovery for cases where third-party output leaks to stdout.
        // If a valid JSON-RPC object is embedded in the line, extract and decode it.
        guard let start = raw.range(of: "{\"jsonrpc\""),
              let end = raw.lastIndex(of: "}") else { return nil }
        guard start.lowerBound <= end else { return nil }

        let jsonSlice = raw[start.lowerBound...end]
        guard let data = String(jsonSlice).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONRPCResponse.self, from: data)
    }

    private func backendTraceLogURL() -> URL? {
        let logsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FDLTool", isDirectory: true)
        if let dir = logsDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return logsDir?.appendingPathComponent("backend_trace.log")
    }

    private func appendBackendTrace(_ message: String) {
        guard let fileURL = backendTraceLogURL() else { return }
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        } else {
            try? data.write(to: fileURL)
        }
    }

    private func handleStderrChunk(_ data: Data) {
        if data.isEmpty {
            return
        }
        if let str = String(data: data, encoding: .utf8), !str.isEmpty {
            print("[Python stderr] \(str)")
            appendBackendTrace(str.trimmingCharacters(in: .newlines))
        }
    }

    private func handleTermination(exitCode: Int32) {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        isRunning = false
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: PythonBridgeError.processExited(exitCode))
        }
        pendingRequests.removeAll()
    }
}
