import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Validation result for a single clip against an FDL.
struct ClipCanvasComparison: Identifiable {
    let id = UUID()
    var clipFileName: String
    var canvasLabel: String
    var canvasWidth: Int
    var canvasHeight: Int
    var actualWidth: Int
    var actualHeight: Int
    var match: Bool
}

/// Tracks a generated FDL for a clip.
struct GeneratedClipFDL: Identifiable {
    let id = UUID()
    var clipInfo: ClipInfo
    var fdlJSON: String
    var fdlUUID: String
}

@MainActor
class ClipIDViewModel: ObservableObject {
    // Directory state
    @Published var selectedDirectory: URL?
    @Published var isScanning = false
    @Published var scanRecursive = false

    // Clip results
    @Published var clips: [ClipInfo] = []
    @Published var scanErrors: [(filePath: String, error: String)] = []
    @Published var selectedClip: ClipInfo?

    // Batch FDL generation
    @Published var isGenerating = false
    @Published var generationProgress: Double = 0
    @Published var generatedFDLs: [GeneratedClipFDL] = []
    @Published var templateFDLJSON: String?
    @Published var showTemplateSelector = false

    // Validation
    @Published var validationResults: [ClipCanvasComparison] = []
    @Published var isValidating = false

    // Save to library
    @Published var showSaveToLibrary = false

    // Error
    @Published var errorMessage: String?

    private let pythonBridge: PythonBridge
    private let libraryStore: LibraryStore

    init(pythonBridge: PythonBridge, libraryStore: LibraryStore) {
        self.pythonBridge = pythonBridge
        self.libraryStore = libraryStore
    }

    // MARK: - Directory Selection

    func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory containing video files"

        if panel.runModal() == .OK, let url = panel.url {
            selectedDirectory = url
            clips = []
            scanErrors = []
            generatedFDLs = []
            validationResults = []
        }
    }

    // MARK: - Batch Probe

    func scanDirectory() {
        guard let dir = selectedDirectory else { return }

        isScanning = true
        clips = []
        scanErrors = []
        selectedClip = nil

        Task {
            do {
                let response = try await pythonBridge.callForResult("clip.batch_probe", params: [
                    "dir_path": dir.path,
                    "recursive": scanRecursive,
                ])

                if let clipDicts = response["clips"] as? [[String: Any]] {
                    clips = clipDicts.compactMap { dict in
                        guard let data = try? JSONSerialization.data(withJSONObject: dict),
                              let clip = try? JSONDecoder().decode(ClipInfo.self, from: data) else {
                            return nil
                        }
                        return clip
                    }
                }

                if let errorDicts = response["errors"] as? [[String: Any]] {
                    scanErrors = errorDicts.compactMap { dict in
                        guard let path = dict["file_path"] as? String,
                              let err = dict["error"] as? String else { return nil }
                        return (filePath: path, error: err)
                    }
                }
            } catch {
                errorMessage = "Scan failed: \(error.localizedDescription)"
            }
            isScanning = false
        }
    }

    // MARK: - Probe Single File

    func probeSingleFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select video files to probe"

        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                for url in urls {
                    do {
                        let response = try await pythonBridge.callForResult("clip.probe", params: [
                            "file_path": url.path,
                        ])
                        let data = try JSONSerialization.data(withJSONObject: response)
                        let clip = try JSONDecoder().decode(ClipInfo.self, from: data)
                        clips.append(clip)
                    } catch {
                        scanErrors.append((filePath: url.path, error: error.localizedDescription))
                    }
                }
            }
        }
    }

    // MARK: - Batch FDL Generation

    func generateFDLsForAllClips() {
        guard !clips.isEmpty else { return }

        isGenerating = true
        generationProgress = 0
        generatedFDLs = []

        let templateDict: [String: Any]?
        if let json = templateFDLJSON, let data = json.data(using: .utf8) {
            templateDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        } else {
            templateDict = nil
        }

        Task {
            for (index, clip) in clips.enumerated() {
                do {
                    var params: [String: Any] = [
                        "clip_info": [
                            "file_name": clip.fileName,
                            "width": clip.width,
                            "height": clip.height,
                            "codec": clip.codec,
                            "fps": clip.fps,
                            "duration": clip.duration,
                        ],
                    ]
                    if let template = templateDict {
                        params["template_fdl"] = template
                    }

                    let response = try await pythonBridge.callForResult("clip.generate_fdl", params: params)
                    if let fdlDict = response["fdl"] as? [String: Any] {
                        let fdlUUID = fdlDict["uuid"] as? String ?? UUID().uuidString
                        let jsonData = try JSONSerialization.data(
                            withJSONObject: fdlDict,
                            options: [.prettyPrinted, .sortedKeys]
                        )
                        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                        generatedFDLs.append(GeneratedClipFDL(
                            clipInfo: clip,
                            fdlJSON: jsonString,
                            fdlUUID: fdlUUID
                        ))
                    }
                } catch {
                    scanErrors.append((filePath: clip.filePath, error: "FDL generation: \(error.localizedDescription)"))
                }

                generationProgress = Double(index + 1) / Double(clips.count)
            }
            isGenerating = false
        }
    }

    // MARK: - Validation

    func validateAllClips() {
        guard !generatedFDLs.isEmpty else { return }

        isValidating = true
        validationResults = []

        Task {
            for generated in generatedFDLs {
                let clip = generated.clipInfo

                // Parse the FDL to extract canvas dimensions
                if let data = generated.fdlJSON.data(using: .utf8),
                   let fdl = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let contexts = fdl["fdl_contexts"] as? [[String: Any]] {
                    for ctx in contexts {
                        for canvas in (ctx["canvases"] as? [[String: Any]]) ?? [] {
                            let dims = canvas["dimensions"] as? [String: Any] ?? [:]
                            let cw = dims["width"] as? Int ?? Int(dims["width"] as? Double ?? 0)
                            let ch = dims["height"] as? Int ?? Int(dims["height"] as? Double ?? 0)

                            validationResults.append(ClipCanvasComparison(
                                clipFileName: clip.fileName,
                                canvasLabel: canvas["label"] as? String ?? "",
                                canvasWidth: cw,
                                canvasHeight: ch,
                                actualWidth: clip.width,
                                actualHeight: clip.height,
                                match: cw == clip.width && ch == clip.height
                            ))
                        }
                    }
                }
            }
            isValidating = false
        }
    }

    // MARK: - Save to Library

    func saveToLibrary(projectID: String) {
        guard !generatedFDLs.isEmpty else { return }

        Task {
            var savedCount = 0
            for generated in generatedFDLs {
                guard let jsonData = generated.fdlJSON.data(using: .utf8) else { continue }
                do {
                    let entry = FDLEntry(
                        projectID: projectID,
                        fdlUUID: generated.fdlUUID,
                        name: generated.clipInfo.fileName,
                        filePath: "",
                        sourceTool: "clip_id",
                        tags: ["clip", generated.clipInfo.codec]
                    )
                    try libraryStore.addFDLEntry(entry, jsonData: jsonData)
                    savedCount += 1
                } catch {
                    scanErrors.append((
                        filePath: generated.clipInfo.filePath,
                        error: "Save failed: \(error.localizedDescription)"
                    ))
                }
            }
            showSaveToLibrary = false
            if savedCount > 0 {
                // Trigger library refresh if someone is watching
                errorMessage = nil  // Clear any previous error
            }
        }
    }

    // MARK: - Export All FDLs

    func exportAllFDLs() {
        guard !generatedFDLs.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select a directory to export FDL files"

        guard panel.runModal() == .OK, let dir = panel.url else { return }

        var exported = 0
        for generated in generatedFDLs {
            let baseName = URL(fileURLWithPath: generated.clipInfo.filePath)
                .deletingPathExtension().lastPathComponent
            let dest = dir.appendingPathComponent("\(baseName).fdl.json")
            do {
                try generated.fdlJSON.data(using: .utf8)?.write(to: dest)
                exported += 1
            } catch {
                scanErrors.append((filePath: dest.path, error: "Export failed: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Helpers

    var totalClipDuration: Double {
        clips.reduce(0) { $0 + $1.duration }
    }

    var totalFileSize: Int64 {
        clips.reduce(0) { $0 + ($1.fileSize ?? 0) }
    }

    func formattedDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    func formattedFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
