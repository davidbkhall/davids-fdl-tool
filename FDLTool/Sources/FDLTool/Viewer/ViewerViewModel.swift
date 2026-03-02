import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class ViewerViewModel: ObservableObject {
    // Document state
    @Published var loadedDocument: FDLDocument?
    @Published var validationResult: ValidationResult?
    @Published var loadedFileName: String?
    @Published var loadedFilePath: String?
    @Published var rawJSON: String?

    // Selection state (cascading: context -> canvas -> framing)
    @Published var selectedContextIndex: Int = 0
    @Published var selectedCanvasIndex: Int = 0
    @Published var selectedFramingIndex: Int?

    // Tab state
    @Published var activeTab: ViewerTab = .source
    enum ViewerTab: String, CaseIterable, Identifiable {
        case source = "Source"
        case output = "Output"
        case comparison = "Comparison"
        case details = "Details"
        var id: String { rawValue }
    }

    // Image overlay state
    @Published var referenceImage: NSImage?
    @Published var referenceImagePath: String?
    @Published var overlayPNGBase64: String?
    @Published var showLabels = true
    @Published var imageOpacity: Double = 1.0
    @Published var isGeneratingOverlay = false

    // Layer visibility toggles
    @Published var showCanvasLayer = true
    @Published var showEffectiveLayer = true
    @Published var showProtectionLayer = true
    @Published var showFramingLayer = true
    @Published var showDimensionLabels = true
    @Published var showAnchorPoints = false
    @Published var showCrosshairs = true
    @Published var showHUD = true
    @Published var showGridOverlay = false
    @Published var gridSpacing: Double = 100

    // Zoom state
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    // Computed geometry from Python backend
    @Published var computedGeometry: ComputedGeometry?

    // Template state
    @Published var templateConfig = CanvasTemplateConfig()
    @Published var selectedPresetName: String?
    @Published var isApplyingTemplate = false
    @Published var outputDocument: FDLDocument?
    @Published var outputGeometry: ComputedGeometry?
    @Published var outputRawJSON: String?
    @Published var transformInfo: TransformInfo?

    struct TransformInfo {
        var sourceCanvas: String
        var sourceFraming: String
        var outputCanvas: String?
        var outputFraming: String?
        var scaleFactor: String?
    }

    // UI state
    @Published var errorMessage: String?

    // MARK: - Selection Helpers

    var contextLabels: [String] {
        guard let doc = loadedDocument else { return [] }
        return doc.contexts.enumerated().map { i, ctx in
            ctx.label ?? "Context \(i)"
        }
    }

    var selectedContext: FDLContext? {
        guard let doc = loadedDocument, selectedContextIndex < doc.contexts.count else { return nil }
        return doc.contexts[selectedContextIndex]
    }

    var canvasLabels: [String] {
        guard let ctx = selectedContext else { return [] }
        return ctx.canvases.enumerated().map { i, canvas in
            let label = canvas.label ?? "Canvas \(i)"
            return "\(label) (\(Int(canvas.dimensions.width))\u{00D7}\(Int(canvas.dimensions.height)))"
        }
    }

    var selectedCanvas: FDLCanvas? {
        guard let ctx = selectedContext, selectedCanvasIndex < ctx.canvases.count else { return nil }
        return ctx.canvases[selectedCanvasIndex]
    }

    var framingLabels: [String] {
        guard let canvas = selectedCanvas else { return [] }
        return canvas.framingDecisions.enumerated().map { i, fd in
            let label = fd.label ?? "FD \(i)"
            return "\(label) (\(Int(fd.dimensions.width))\u{00D7}\(Int(fd.dimensions.height)))"
        }
    }

    var selectedFramingDecision: FDLFramingDecision? {
        guard let canvas = selectedCanvas, let idx = selectedFramingIndex,
              idx < canvas.framingDecisions.count else { return nil }
        return canvas.framingDecisions[idx]
    }

    /// The computed geometry for the currently selected context/canvas.
    var selectedComputedCanvas: ComputedCanvas? {
        guard let geo = computedGeometry,
              selectedContextIndex < geo.contexts.count else { return nil }
        let ctx = geo.contexts[selectedContextIndex]
        guard selectedCanvasIndex < ctx.canvases.count else { return nil }
        return ctx.canvases[selectedCanvasIndex]
    }

    /// Canvas dimensions for the current selection.
    var canvasDimensions: (width: Double, height: Double)? {
        if let canvas = selectedCanvas {
            return (canvas.dimensions.width, canvas.dimensions.height)
        }
        return nil
    }

    func selectContext(_ index: Int) {
        selectedContextIndex = index
        selectedCanvasIndex = 0
        selectedFramingIndex = nil
    }

    func selectCanvas(_ index: Int) {
        selectedCanvasIndex = index
        selectedFramingIndex = nil
    }

    // MARK: - Zoom

    func zoomIn() { zoomScale = min(zoomScale * 1.25, 10.0) }
    func zoomOut() { zoomScale = max(zoomScale / 1.25, 0.1) }
    func zoomToFit() { zoomScale = 1.0; panOffset = .zero }
    func resetZoom() { zoomScale = 1.0; panOffset = .zero }

    // MARK: - Template

    func applyPreset(_ name: String) {
        guard let preset = TemplatePresets.all.first(where: { $0.name == name }) else { return }
        selectedPresetName = name
        templateConfig = preset.config
    }

    func importTemplateJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.fdl, .json]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a Canvas Template file (.fdl or .json)"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errorMessage = "Invalid JSON: expected a dictionary"
                return
            }

            var config = CanvasTemplateConfig()

            if let id = dict["id"] as? String { config.id = id }
            if let label = dict["label"] as? String { config.label = label }

            if let target = dict["target_dimensions"] as? [String: Any] {
                if let w = target["width"] as? Int { config.targetWidth = w }
                if let h = target["height"] as? Int { config.targetHeight = h }
            }
            if let fitSrc = dict["fit_source"] as? String { config.fitSource = fitSrc }
            if let fitMeth = dict["fit_method"] as? String { config.fitMethod = fitMeth }
            if let ah = dict["alignment_method_horizontal"] as? String { config.alignmentHorizontal = ah }
            if let av = dict["alignment_method_vertical"] as? String { config.alignmentVertical = av }
            if let preserve = dict["preserve_from_source_canvas"] as? String { config.preserveFromSourceCanvas = preserve }
            if let padMax = dict["pad_to_maximum"] as? Bool { config.padToMaximum = padMax }

            if let maxDims = dict["maximum_dimensions"] as? [String: Any] {
                config.maximumWidth = maxDims["width"] as? Int
                config.maximumHeight = maxDims["height"] as? Int
            }

            if let rounding = dict["round"] as? [String: Any] {
                if let re = rounding["even"] as? String { config.roundEven = re }
                if let rm = rounding["mode"] as? String { config.roundMode = rm }
            }

            templateConfig = config
            selectedPresetName = nil
        } catch {
            errorMessage = "Failed to read template: \(error.localizedDescription)"
        }
    }

    func exportTemplateJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(templateConfig.label).json"

        guard panel.runModal() == .OK, let dest = panel.url else { return }

        do {
            let dict = templateConfig.toDict()
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: dest)
        } catch {
            errorMessage = "Failed to export template: \(error.localizedDescription)"
        }
    }

    func applyTemplate(pythonBridge: PythonBridge) {
        guard let rawJSON else { return }
        guard let fdlDict = try? JSONSerialization.jsonObject(with: Data(rawJSON.utf8)) as? [String: Any] else { return }

        let templateDict = templateConfig.toDict()
        guard let templateJSON = try? JSONSerialization.data(withJSONObject: templateDict),
              let templateStr = String(data: templateJSON, encoding: .utf8) else { return }
        guard let fdlJSON = try? JSONSerialization.data(withJSONObject: fdlDict),
              let fdlStr = String(data: fdlJSON, encoding: .utf8) else { return }

        isApplyingTemplate = true
        let ctxIndex = selectedContextIndex
        let canvasIndex = selectedCanvasIndex
        let fdIndex = selectedFramingIndex ?? 0

        Task {
            do {
                let response = try await pythonBridge.callForResult("template.apply_fdl", params: [
                    "fdl_json": fdlStr,
                    "template_json": templateStr,
                    "context_index": ctxIndex,
                    "canvas_index": canvasIndex,
                    "fd_index": fdIndex,
                ])

                if let fdlDict = response["fdl"] as? [String: Any] {
                    let data = try JSONSerialization.data(withJSONObject: fdlDict, options: .prettyPrinted)
                    outputDocument = try JSONDecoder().decode(FDLDocument.self, from: data)
                    outputRawJSON = String(data: data, encoding: .utf8)

                    // Compute output geometry
                    let geoResponse = try await pythonBridge.callForResult("geometry.compute_rects", params: [
                        "fdl_data": fdlDict,
                    ])
                    let geoData = try JSONSerialization.data(withJSONObject: geoResponse)
                    outputGeometry = try JSONDecoder().decode(ComputedGeometry.self, from: geoData)
                }

                // Build transform info
                let srcCanvas = selectedCanvas
                let srcFD = selectedFramingDecision ?? selectedCanvas?.framingDecisions.first
                transformInfo = TransformInfo(
                    sourceCanvas: "\(Int(srcCanvas?.dimensions.width ?? 0))\u{00D7}\(Int(srcCanvas?.dimensions.height ?? 0))",
                    sourceFraming: "\(Int(srcFD?.dimensions.width ?? 0))\u{00D7}\(Int(srcFD?.dimensions.height ?? 0))",
                    outputCanvas: nil,
                    outputFraming: nil
                )

                if let outDoc = outputDocument, let outCtx = outDoc.contexts.first {
                    if let outCanvas = outCtx.canvases.first {
                        transformInfo?.outputCanvas = "\(Int(outCanvas.dimensions.width))\u{00D7}\(Int(outCanvas.dimensions.height))"
                        if let outFD = outCanvas.framingDecisions.first {
                            transformInfo?.outputFraming = "\(Int(outFD.dimensions.width))\u{00D7}\(Int(outFD.dimensions.height))"
                        }
                    }
                }

                activeTab = .output
            } catch {
                errorMessage = "Template application failed: \(error.localizedDescription)"
            }
            isApplyingTemplate = false
        }
    }

    /// The first computed canvas from the output geometry.
    var outputComputedCanvas: ComputedCanvas? {
        guard let geo = outputGeometry,
              let ctx = geo.contexts.first,
              let canvas = ctx.canvases.first else { return nil }
        return canvas
    }

    var outputCanvasDimensions: (width: Double, height: Double)? {
        if let doc = outputDocument,
           let ctx = doc.contexts.first,
           let canvas = ctx.canvases.first {
            return (canvas.dimensions.width, canvas.dimensions.height)
        }
        return nil
    }

    // MARK: - Open FDL

    func openFile(pythonBridge: PythonBridge) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.fdl, .json]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an FDL file (.fdl or .json)"

        if panel.runModal() == .OK, let url = panel.url {
            loadFromURL(url, pythonBridge: pythonBridge)
        }
    }

    func loadFromURL(_ url: URL, pythonBridge: PythonBridge) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        loadedFileName = url.lastPathComponent
        loadedFilePath = url.path

        referenceImage = nil
        referenceImagePath = nil
        overlayPNGBase64 = nil
        outputDocument = nil
        outputGeometry = nil
        outputRawJSON = nil
        transformInfo = nil

        do {
            let data = try Data(contentsOf: url)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                errorMessage = "File is not valid UTF-8 text"
                return
            }
            rawJSON = jsonString

            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                errorMessage = "Invalid FDL: expected a JSON object"
                loadedDocument = nil
                return
            }

            guard dict["uuid"] != nil || dict["contexts"] != nil else {
                errorMessage = "Invalid FDL: missing required 'uuid' or 'contexts' fields"
                loadedDocument = nil
                return
            }
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
            return
        }

        Task {
            do {
                let parseResponse = try await pythonBridge.callForResult("fdl.parse", params: [
                    "path": url.path,
                ])
                if let fdlDict = parseResponse["fdl"] as? [String: Any] {
                    let data = try JSONSerialization.data(withJSONObject: fdlDict)
                    loadedDocument = try JSONDecoder().decode(FDLDocument.self, from: data)
                }

                let valResponse = try await pythonBridge.callForResult("fdl.validate", params: [
                    "path": url.path,
                ])
                let valData = try JSONSerialization.data(withJSONObject: valResponse)
                validationResult = try JSONDecoder().decode(ValidationResult.self, from: valData)

                await computeGeometry(pythonBridge: pythonBridge)
            } catch {
                errorMessage = "Failed to process FDL: \(error.localizedDescription)"
            }
        }
    }

    func computeGeometry(pythonBridge: PythonBridge) async {
        guard let rawJSON else { return }
        guard let fdlDict = try? JSONSerialization.jsonObject(with: Data(rawJSON.utf8)) as? [String: Any] else { return }

        do {
            let response = try await pythonBridge.callForResult("geometry.compute_rects", params: [
                "fdl_data": fdlDict,
            ])
            let data = try JSONSerialization.data(withJSONObject: response)
            computedGeometry = try JSONDecoder().decode(ComputedGeometry.self, from: data)
        } catch {
            // Geometry computation is non-critical; just log and continue
            print("Geometry computation failed: \(error)")
        }
    }

    // MARK: - Load from Library Entry

    func loadFromEntry(_ entry: FDLEntry, pythonBridge: PythonBridge) {
        let filePath = LibraryStore.projectDirectoryURL(projectID: entry.projectID)
            .appendingPathComponent("\(entry.id).fdl.json")
        loadFromURL(filePath, pythonBridge: pythonBridge)
    }

    // MARK: - Reference Image

    func openReferenceImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a reference image"

        if panel.runModal() == .OK, let url = panel.url {
            loadReferenceImage(from: url)
        }
    }

    func loadReferenceImage(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "Failed to load image: \(url.lastPathComponent)"
            return
        }
        referenceImage = image
        referenceImagePath = url.path
        overlayPNGBase64 = nil
    }

    func clearReferenceImage() {
        referenceImage = nil
        referenceImagePath = nil
        overlayPNGBase64 = nil
    }

    // MARK: - Python Overlay Generation

    func generatePythonOverlay(pythonBridge: PythonBridge) {
        guard let imagePath = referenceImagePath, let rawJSON = rawJSON else { return }
        guard let fdlDict = try? JSONSerialization.jsonObject(with: Data(rawJSON.utf8)) as? [String: Any] else { return }

        isGeneratingOverlay = true
        Task {
            do {
                let response = try await pythonBridge.callForResult("image.load_and_overlay", params: [
                    "image_path": imagePath,
                    "fdl_data": fdlDict,
                ])
                overlayPNGBase64 = response["png_base64"] as? String
            } catch {
                errorMessage = "Overlay generation failed: \(error.localizedDescription)"
            }
            isGeneratingOverlay = false
        }
    }

    // MARK: - Export Overlay

    func exportOverlay(pythonBridge: PythonBridge) {
        guard referenceImagePath != nil else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "overlay_\(loadedFileName ?? "fdl").png"

        guard panel.runModal() == .OK, let dest = panel.url else { return }

        // If we have a Python-generated overlay, use it; otherwise generate one
        if let b64 = overlayPNGBase64, let data = Data(base64Encoded: b64) {
            do {
                try data.write(to: dest)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        } else {
            guard let imagePath = referenceImagePath, let rawJSON = rawJSON else { return }
            guard let fdlDict = try? JSONSerialization.jsonObject(with: Data(rawJSON.utf8)) as? [String: Any] else { return }

            Task {
                do {
                    let response = try await pythonBridge.callForResult("image.load_and_overlay", params: [
                        "image_path": imagePath,
                        "fdl_data": fdlDict,
                    ])
                    if let b64 = response["png_base64"] as? String, let data = Data(base64Encoded: b64) {
                        try data.write(to: dest)
                    }
                } catch {
                    errorMessage = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Close

    func closeDocument() {
        loadedDocument = nil
        validationResult = nil
        computedGeometry = nil
        outputDocument = nil
        outputGeometry = nil
        loadedFileName = nil
        loadedFilePath = nil
        rawJSON = nil
        referenceImage = nil
        referenceImagePath = nil
        overlayPNGBase64 = nil
        selectedContextIndex = 0
        selectedCanvasIndex = 0
        selectedFramingIndex = nil
        zoomScale = 1.0
        panOffset = .zero
        activeTab = .source
    }
}
