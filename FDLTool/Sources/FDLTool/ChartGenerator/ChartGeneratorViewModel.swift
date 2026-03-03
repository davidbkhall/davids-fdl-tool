import Foundation
import SwiftUI
import UniformTypeIdentifiers

func roundToEven(_ value: Double) -> Double {
    let rounded = (value / 2.0).rounded() * 2.0
    return max(2, rounded)
}

struct FramingIntent: Identifiable {
    let id = UUID()
    var label: String
    var aspectWidth: Double
    var aspectHeight: Double
    var protectionPercent: Double = 0

    var aspectRatio: Double {
        guard aspectHeight > 0 else { return 0 }
        return aspectWidth / aspectHeight
    }

    var aspectRatioDescription: String {
        guard aspectHeight > 0 else { return "N/A" }
        let ratio = aspectWidth / aspectHeight
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

enum FDLHorizontalAlignment: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
}

enum FDLVerticalAlignment: String, CaseIterable, Identifiable {
    case top, center, bottom
    var id: String { rawValue }
}

/// A single frameline entry in the chart configuration (represents a Framing Decision).
struct Frameline: Identifiable {
    let id = UUID()
    var label: String
    var width: Double
    var height: Double
    var color: String
    var framingIntent: String = ""
    var linkedIntentID: UUID?
    var aspectLocked: Bool = true

    // Anchor / alignment
    var hAlign: FDLHorizontalAlignment = .center
    var vAlign: FDLVerticalAlignment = .center
    var anchorX: Double?
    var anchorY: Double?

    // Protection
    var protectionWidth: Double?
    var protectionHeight: Double?
    var protectionAnchorX: Double?
    var protectionAnchorY: Double?

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

    // Framing Intents
    @Published var framingIntents: [FramingIntent] = []

    // Framelines (Framing Decisions)
    @Published var framelines: [Frameline] = []

    // Canvas effective dimensions
    @Published var showEffectiveDimensions: Bool = false
    @Published var canvasEffectiveWidth: Double?
    @Published var canvasEffectiveHeight: Double?
    @Published var canvasEffectiveAnchorX: Double = 0
    @Published var canvasEffectiveAnchorY: Double = 0
    @Published var anamorphicSqueeze: Double = 1.0

    // Chart options
    @Published var chartTitle: String = "Framing Chart"
    @Published var showLabels: Bool = true

    // Layer visibility
    @Published var showCanvasLayer = true
    @Published var showEffectiveLayer = true
    @Published var showProtectionLayer = true
    @Published var showFramingLayer = true
    @Published var showDimensionLabels = true
    @Published var showCrosshairs = false
    @Published var showSqueezeCircle = false
    @Published var showGridOverlay = false
    @Published var gridSpacing: Double = 500

    // Metadata
    @Published var metadataShowName: String = ""
    @Published var metadataDOP: String = ""
    @Published var metadataOverlayShow = false

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

    // MARK: - Framing Intent Management

    func addFramingIntent(label: String, aspectWidth: Double, aspectHeight: Double, protectionPercent: Double = 0) {
        let intent = FramingIntent(label: label, aspectWidth: aspectWidth, aspectHeight: aspectHeight, protectionPercent: protectionPercent)
        framingIntents.append(intent)
    }

    func removeFramingIntent(_ intent: FramingIntent) {
        framingIntents.removeAll { $0.id == intent.id }
    }

    func framingIntent(byID id: UUID) -> FramingIntent? {
        framingIntents.first { $0.id == id }
    }

    // MARK: - Frameline Management

    func addFrameline(label: String = "", width: Double = 0, height: Double = 0) {
        let w = min(width > 0 ? width : framingBoundsWidth, framingBoundsWidth)
        let h = min(height > 0 ? height : framingBoundsHeight, framingBoundsHeight)
        let color = framlineColors[framelines.count % framlineColors.count]
        let fl = Frameline(label: label, width: w, height: h, color: color)
        framelines.append(fl)
    }

    /// Create a Framing Decision linked to a Framing Intent, auto-populating dimensions.
    /// Per ASC FDL Spec 7.2.4 and fdl_framing.cpp:
    ///   1. Fit intent aspect ratio into working area (letterbox or pillarbox)
    ///   2. If protection > 0: protection_dims = fit rectangle, framing = protection × (1 - fraction)
    ///   3. Both centered within the full canvas
    func addFramelineFromIntent(_ intent: FramingIntent) {
        let color = framlineColors[framelines.count % framlineColors.count]
        guard intent.aspectRatio > 0 else { return }

        let (fitW, fitH) = fitAspectIntoWorkingArea(intent.aspectRatio)
        let protectionFraction = intent.protectionPercent / 100.0

        var fl: Frameline
        if protectionFraction > 0 {
            let protW = roundToEven(fitW)
            let protH = roundToEven(fitH)
            let framW = roundToEven(protW * (1.0 - protectionFraction))
            let framH = roundToEven(protH * (1.0 - protectionFraction))
            fl = Frameline(label: intent.label, width: framW, height: framH, color: color)
            fl.protectionWidth = protW
            fl.protectionHeight = protH
            fl.protectionAnchorX = (canvasWidth - protW) / 2.0
            fl.protectionAnchorY = (canvasHeight - protH) / 2.0
        } else {
            fl = Frameline(label: intent.label, width: roundToEven(fitW), height: roundToEven(fitH), color: color)
        }

        fl.linkedIntentID = intent.id
        fl.aspectLocked = true
        framelines.append(fl)
    }

    func addPreset(_ preset: FramelinePreset) {
        let dims = preset.dimensions(forCanvasWidth: framingBoundsWidth)
        let cw = min(roundToEven(dims.width), framingBoundsWidth)
        let ch = min(roundToEven(dims.height), framingBoundsHeight)
        let color = framlineColors[framelines.count % framlineColors.count]
        framelines.append(Frameline(label: preset.label, width: cw, height: ch, color: color))
    }

    /// Recalculate all framelines linked to a given intent after aspect ratio or protection changes.
    /// Recomputes the full fit-to-working-area algorithm per ASC FDL Spec 7.2.4.
    func recalculateFramelinesForIntent(_ intentID: UUID) {
        guard let intent = framingIntent(byID: intentID), intent.aspectRatio > 0 else { return }

        let (fitW, fitH) = fitAspectIntoWorkingArea(intent.aspectRatio)
        let protectionFraction = intent.protectionPercent / 100.0

        for i in framelines.indices where framelines[i].linkedIntentID == intentID && framelines[i].aspectLocked {
            if protectionFraction > 0 {
                let protW = roundToEven(fitW)
                let protH = roundToEven(fitH)
                framelines[i].width = roundToEven(protW * (1.0 - protectionFraction))
                framelines[i].height = roundToEven(protH * (1.0 - protectionFraction))
                framelines[i].protectionWidth = protW
                framelines[i].protectionHeight = protH
                framelines[i].protectionAnchorX = (canvasWidth - protW) / 2.0
                framelines[i].protectionAnchorY = (canvasHeight - protH) / 2.0
            } else {
                framelines[i].width = roundToEven(fitW)
                framelines[i].height = roundToEven(fitH)
                framelines[i].protectionWidth = nil
                framelines[i].protectionHeight = nil
                framelines[i].protectionAnchorX = nil
                framelines[i].protectionAnchorY = nil
            }
        }
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

    /// Effective protection dimensions for a frameline.
    /// Per ASC FDL Spec 7.2.4: protection is the fit rectangle (outer),
    /// framing is the inner safe area. Hierarchy: canvas >= effective >= protection >= framing.
    func effectiveProtection(for fl: Frameline) -> (width: Double, height: Double)? {
        let maxW = canvasWidth
        let maxH = canvasHeight

        if let pw = fl.protectionWidth, let ph = fl.protectionHeight {
            return (min(pw, maxW), min(ph, maxH))
        }

        guard let linkedID = fl.linkedIntentID,
              let intent = framingIntent(byID: linkedID),
              intent.protectionPercent > 0,
              intent.aspectRatio > 0 else { return nil }

        let (fitW, fitH) = fitAspectIntoWorkingArea(intent.aspectRatio)
        let pw = roundToEven(fitW)
        let ph = roundToEven(fitH)
        return (min(pw, maxW), min(ph, maxH))
    }

    /// Fit an intent aspect ratio into the working area (effective or canvas).
    /// Matches the algorithm from fdl_framing.cpp: letterbox or pillarbox.
    private func fitAspectIntoWorkingArea(_ intentAspect: Double) -> (width: Double, height: Double) {
        let workingW = framingBoundsWidth
        let workingH = framingBoundsHeight
        guard workingH > 0 else { return (0, 0) }

        let workingAspect = workingW / workingH
        let squeeze = anamorphicSqueeze

        if intentAspect >= workingAspect {
            let w = workingW
            let h = (w * squeeze) / intentAspect
            return (w, h)
        } else {
            let h = workingH
            let w = h * intentAspect
            return (w, h)
        }
    }

    /// Maximum bounds for framing decisions: effective area if enabled, otherwise canvas.
    var framingBoundsWidth: Double {
        if showEffectiveDimensions, let ew = canvasEffectiveWidth { return ew }
        return canvasWidth
    }

    var framingBoundsHeight: Double {
        if showEffectiveDimensions, let eh = canvasEffectiveHeight { return eh }
        return canvasHeight
    }

    // MARK: - Preview Generation

    func generatePreview() {
        previewSVG = nil
        objectWillChange.send()

        isGenerating = true
        let params = chartParams()

        Task {
            do {
                let response = try await pythonBridge.callForResult("chart.generate_svg", params: params)
                previewSVG = response["svg"] as? String
            } catch {
                // SVG generation not available; native preview will be used
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

    // MARK: - Open in FDL Viewer

    func buildLocalFDLDocument(creator: String = "FDL Tool") -> FDLDocument {
        let cw = canvasWidth
        let ch = canvasHeight

        let fds = framelines.map { fl -> FDLFramingDecision in
            let fw = fl.width
            let fh = fl.height
            let ax: Double
            let ay: Double
            if let cx = fl.anchorX, let cy = fl.anchorY {
                ax = cx; ay = cy
            } else {
                switch fl.hAlign {
                case .left: ax = 0
                case .right: ax = cw - fw
                default: ax = (cw - fw) / 2
                }
                switch fl.vAlign {
                case .top: ay = 0
                case .bottom: ay = ch - fh
                default: ay = (ch - fh) / 2
                }
            }

            var protDims: FDLDimensions?
            var protAnchor: FDLPoint?
            if let prot = effectiveProtection(for: fl) {
                protDims = FDLDimensions(width: prot.width, height: prot.height)
                let px = fl.protectionAnchorX ?? (cw - prot.width) / 2
                let py = fl.protectionAnchorY ?? (ch - prot.height) / 2
                protAnchor = FDLPoint(x: px, y: py)
            }

            return FDLFramingDecision(
                id: UUID().uuidString,
                label: fl.label,
                framingIntentId: fl.framingIntent.isEmpty ? nil : fl.framingIntent,
                dimensions: FDLDimensions(width: fw, height: fh),
                anchorPoint: FDLPoint(x: ax, y: ay),
                protectionDimensions: protDims,
                protectionAnchorPoint: protAnchor
            )
        }

        var effDims: FDLDimensions?
        var effAnchor: FDLPoint?
        if showEffectiveDimensions,
           let ew = canvasEffectiveWidth, let eh = canvasEffectiveHeight {
            effDims = FDLDimensions(width: ew, height: eh)
            effAnchor = FDLPoint(x: canvasEffectiveAnchorX, y: canvasEffectiveAnchorY)
        }

        let canvas = FDLCanvas(
            id: UUID().uuidString,
            label: chartTitle,
            dimensions: FDLDimensions(width: cw, height: ch),
            effectiveDimensions: effDims,
            effectiveAnchorPoint: effAnchor,
            anamorphicSqueeze: anamorphicSqueeze != 1.0 ? anamorphicSqueeze : nil,
            framingDecisions: fds
        )

        let context = FDLContext(
            label: selectedCamera.map { "\($0.manufacturer) \($0.model)" } ?? "Chart Generator",
            contextCreator: creator,
            canvases: [canvas]
        )

        return FDLDocument(
            id: UUID().uuidString,
            version: FDLVersion(major: 2, minor: 0),
            fdlCreator: creator,
            defaultFramingIntent: nil,
            contexts: [context]
        )
    }

    // MARK: - Param Builders

    private func chartParams() -> [String: Any] {
        var params: [String: Any] = [
            "canvas_width": Int(canvasWidth),
            "canvas_height": Int(canvasHeight),
            "framelines": framelines.map { fl -> [String: Any] in
                let intentLabel: String
                if let linkedID = fl.linkedIntentID, let intent = framingIntent(byID: linkedID) {
                    intentLabel = intent.label
                } else {
                    intentLabel = fl.framingIntent
                }
                var d: [String: Any] = [
                    "label": fl.label,
                    "width": Int(fl.width),
                    "height": Int(fl.height),
                    "color": fl.color,
                    "h_align": fl.hAlign.rawValue,
                    "v_align": fl.vAlign.rawValue,
                    "framing_intent": intentLabel,
                ]
                if let ax = fl.anchorX, let ay = fl.anchorY {
                    d["anchor_x"] = ax
                    d["anchor_y"] = ay
                }
                if let prot = self.effectiveProtection(for: fl) {
                    d["protection_width"] = prot.width
                    d["protection_height"] = prot.height
                    if let pax = fl.protectionAnchorX { d["protection_anchor_x"] = pax }
                    if let pay = fl.protectionAnchorY { d["protection_anchor_y"] = pay }
                }
                return d
            },
            "title": chartTitle,
            "show_labels": showLabels,
            "show_crosshairs": showCrosshairs,
            "show_grid": showGridOverlay,
            "grid_spacing": Int(gridSpacing),
            "anamorphic_squeeze": anamorphicSqueeze,
            "show_squeeze_circle": showSqueezeCircle,
            "layers": [
                "canvas": showCanvasLayer,
                "effective": showEffectiveLayer,
                "protection": showProtectionLayer,
                "framing": showFramingLayer,
            ] as [String: Any],
        ]

        if showEffectiveDimensions, let ew = canvasEffectiveWidth, let eh = canvasEffectiveHeight {
            params["effective_width"] = Int(ew)
            params["effective_height"] = Int(eh)
        }

        if metadataOverlayShow {
            params["metadata"] = [
                "show_name": metadataShowName,
                "dop": metadataDOP,
            ] as [String: Any]
        }

        return params
    }

    private func fdlParams() -> [String: Any] {
        var params = chartParams()
        if let camera = selectedCamera {
            params["camera_model"] = "\(camera.manufacturer) \(camera.model)"
        }
        params["description"] = "Generated by FDL Tool Chart Generator"
        params["anamorphic_squeeze"] = anamorphicSqueeze
        if showEffectiveDimensions, let ew = canvasEffectiveWidth, let eh = canvasEffectiveHeight {
            params["effective_width"] = Int(ew)
            params["effective_height"] = Int(eh)
        }
        return params
    }
}
