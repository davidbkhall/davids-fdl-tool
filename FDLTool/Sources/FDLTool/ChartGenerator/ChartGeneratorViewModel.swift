import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A single frameline entry in the chart configuration.
struct Frameline: Identifiable {
    let id = UUID()
    var label: String
    var width: Double
    var height: Double
    var color: String

    var aspectRatioDescription: String {
        guard height > 0 else { return "N/A" }
        let ratio = width / height
        let known: [(Double, String)] = [
            (16.0/9.0, "16:9"), (1.85, "1.85:1"), (2.39, "2.39:1"),
            (2.35, "2.35:1"), (4.0/3.0, "4:3"), (1.0, "1:1"),
            (3.0/2.0, "3:2"), (2.0, "2:1"), (1.9, "1.9:1"),
        ]
        for (value, name) in known where abs(ratio - value) < 0.02 {
            return name
        }
        return String(format: "%.2f:1", ratio)
    }
}

/// Common deliverable presets for quick frameline addition.
struct FramelinePreset: Identifiable {
    let id = UUID()
    let label: String
    let aspectWidth: Double
    let aspectHeight: Double

    /// Compute actual pixel dimensions given a canvas width.
    func dimensions(forCanvasWidth canvasW: Double) -> (width: Double, height: Double) {
        let ratio = aspectWidth / aspectHeight
        let h = canvasW / ratio
        return (canvasW, h.rounded())
    }
}

let commonPresets: [FramelinePreset] = [
    FramelinePreset(label: "2.39:1 Scope", aspectWidth: 2.39, aspectHeight: 1),
    FramelinePreset(label: "2.35:1 Scope", aspectWidth: 2.35, aspectHeight: 1),
    FramelinePreset(label: "1.85:1 Flat", aspectWidth: 1.85, aspectHeight: 1),
    FramelinePreset(label: "16:9 (1.78:1)", aspectWidth: 16, aspectHeight: 9),
    FramelinePreset(label: "4:3 (1.33:1)", aspectWidth: 4, aspectHeight: 3),
    FramelinePreset(label: "1:1 Square", aspectWidth: 1, aspectHeight: 1),
    FramelinePreset(label: "9:16 Vertical", aspectWidth: 9, aspectHeight: 16),
]

let framlineColors = [
    "#FF3B30", "#007AFF", "#34C759", "#FF9500",
    "#AF52DE", "#FFD60A", "#5AC8FA", "#FF2D55",
]

@MainActor
class ChartGeneratorViewModel: ObservableObject {
    // Camera selection
    @Published var selectedCameraID: String?
    @Published var selectedModeID: String?

    // Custom canvas (when no camera selected)
    @Published var customCanvasWidth: Double = 3840
    @Published var customCanvasHeight: Double = 2160
    @Published var useCustomCanvas = false

    // Framelines
    @Published var framelines: [Frameline] = []

    // Chart options
    @Published var chartTitle: String = "Framing Chart"
    @Published var showLabels: Bool = true

    // Preview state
    @Published var previewSVG: String?
    @Published var previewPNGData: Data?
    @Published var isGenerating = false

    // Export
    @Published var showExportSheet = false
    @Published var showSaveToLibrary = false

    // Error
    @Published var errorMessage: String?

    private let pythonBridge: PythonBridge
    private let cameraDBStore: CameraDBStore
    private let libraryStore: LibraryStore

    init(pythonBridge: PythonBridge, cameraDBStore: CameraDBStore, libraryStore: LibraryStore) {
        self.pythonBridge = pythonBridge
        self.cameraDBStore = cameraDBStore
        self.libraryStore = libraryStore
    }

    // MARK: - Canvas Dimensions

    /// The effective canvas width based on camera selection or custom entry.
    var canvasWidth: Double {
        if let mode = selectedRecordingMode {
            return Double(mode.activePhotosites.width)
        }
        return customCanvasWidth
    }

    /// The effective canvas height based on camera selection or custom entry.
    var canvasHeight: Double {
        if let mode = selectedRecordingMode {
            return Double(mode.activePhotosites.height)
        }
        return customCanvasHeight
    }

    var selectedCamera: CameraSpec? {
        guard let id = selectedCameraID else { return nil }
        return cameraDBStore.camera(byID: id)
    }

    var selectedRecordingMode: RecordingMode? {
        guard let camera = selectedCamera, let modeID = selectedModeID else { return nil }
        return camera.recordingModes.first { $0.id == modeID }
    }

    // MARK: - Frameline Management

    func addFrameline(label: String = "", width: Double = 0, height: Double = 0) {
        let w = width > 0 ? width : canvasWidth
        let h = height > 0 ? height : canvasHeight
        let color = framlineColors[framelines.count % framlineColors.count]
        let fl = Frameline(label: label, width: w, height: h, color: color)
        framelines.append(fl)
    }

    func addPreset(_ preset: FramelinePreset) {
        let dims = preset.dimensions(forCanvasWidth: canvasWidth)
        let color = framlineColors[framelines.count % framlineColors.count]
        framelines.append(Frameline(label: preset.label, width: dims.width, height: dims.height, color: color))
    }

    func removeFrameline(at offsets: IndexSet) {
        framelines.remove(atOffsets: offsets)
    }

    func removeFrameline(_ frameline: Frameline) {
        framelines.removeAll { $0.id == frameline.id }
    }

    func moveFrameline(from source: IndexSet, to destination: Int) {
        framelines.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Preview Generation

    func generatePreview() {
        isGenerating = true
        let params = chartParams()

        Task {
            do {
                let response = try await pythonBridge.callForResult("chart.generate_svg", params: params)
                previewSVG = response["svg"] as? String
            } catch {
                errorMessage = "Preview generation failed: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }

    // MARK: - Export

    func exportSVG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .data]
        panel.nameFieldStringValue = "\(chartTitle).svg"

        guard panel.runModal() == .OK, let dest = panel.url else { return }

        Task {
            do {
                let response = try await pythonBridge.callForResult("chart.generate_svg", params: chartParams())
                if let svg = response["svg"] as? String {
                    try svg.data(using: .utf8)?.write(to: dest)
                }
            } catch {
                errorMessage = "SVG export failed: \(error.localizedDescription)"
            }
        }
    }

    func exportPNG(dpi: Int = 150) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(chartTitle).png"

        guard panel.runModal() == .OK, let dest = panel.url else { return }

        var params = chartParams()
        params["dpi"] = dpi

        Task {
            do {
                let response = try await pythonBridge.callForResult("chart.generate_png", params: params)
                if let b64 = response["png_base64"] as? String,
                   let data = Data(base64Encoded: b64) {
                    try data.write(to: dest)
                }
            } catch {
                errorMessage = "PNG export failed: \(error.localizedDescription)"
            }
        }
    }

    func exportFDL() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(chartTitle).fdl.json"

        guard panel.runModal() == .OK, let dest = panel.url else { return }

        Task {
            do {
                let response = try await pythonBridge.callForResult("chart.generate_fdl", params: fdlParams())
                if let fdl = response["fdl"] as? [String: Any] {
                    let data = try JSONSerialization.data(withJSONObject: fdl, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: dest)
                }
            } catch {
                errorMessage = "FDL export failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Save to Library

    func saveToLibrary(projectID: String) {
        Task {
            do {
                let response = try await pythonBridge.callForResult("chart.generate_fdl", params: fdlParams())
                guard let fdlDict = response["fdl"] as? [String: Any] else {
                    errorMessage = "Failed to generate FDL"
                    return
                }

                let fdlUUID = fdlDict["uuid"] as? String ?? UUID().uuidString
                let jsonData = try JSONSerialization.data(
                    withJSONObject: fdlDict,
                    options: [.prettyPrinted, .sortedKeys]
                )

                let entry = FDLEntry(
                    projectID: projectID,
                    fdlUUID: fdlUUID,
                    name: chartTitle,
                    filePath: "",
                    sourceTool: "chart_generator",
                    cameraModel: selectedCamera.map { "\($0.manufacturer) \($0.model)" },
                    tags: ["chart"]
                )

                try libraryStore.addFDLEntry(entry, jsonData: jsonData)
                showSaveToLibrary = false
            } catch {
                errorMessage = "Save to library failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Param Builders

    private func chartParams() -> [String: Any] {
        [
            "canvas_width": Int(canvasWidth),
            "canvas_height": Int(canvasHeight),
            "framelines": framelines.map { fl -> [String: Any] in
                [
                    "label": fl.label,
                    "width": Int(fl.width),
                    "height": Int(fl.height),
                    "color": fl.color,
                ]
            },
            "title": chartTitle,
            "show_labels": showLabels,
        ]
    }

    private func fdlParams() -> [String: Any] {
        var params = chartParams()
        if let camera = selectedCamera {
            params["camera_model"] = "\(camera.manufacturer) \(camera.model)"
        }
        params["description"] = "Generated by FDL Tool Chart Generator"
        return params
    }
}
