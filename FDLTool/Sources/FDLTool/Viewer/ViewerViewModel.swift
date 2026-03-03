import Foundation
import SwiftUI
import UniformTypeIdentifiers

private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CancellationError()
        }
        guard let result = try await group.next() else {
            throw CancellationError()
        }
        group.cancelAll()
        return result
    }
}

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
    /// Falls back to reference image size if no FDL is loaded.
    var canvasDimensions: (width: Double, height: Double)? {
        if let canvas = selectedCanvas {
            return (canvas.dimensions.width, canvas.dimensions.height)
        }
        if let image = referenceImage {
            let size = image.size
            if size.width > 0 && size.height > 0 {
                return (Double(size.width), Double(size.height))
            }
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

    var templateIsConfigured: Bool {
        selectedPresetName != nil || templateConfig != CanvasTemplateConfig()
    }

    func applyPreset(_ name: String) {
        guard let preset = TemplatePresets.all.first(where: { $0.name == name }) else { return }
        selectedPresetName = name
        templateConfig = preset.config
    }

    func startCustomTemplate() {
        templateConfig = CanvasTemplateConfig(
            id: UUID().uuidString,
            label: "Custom"
        )
        selectedPresetName = nil
    }

    func loadLibraryTemplate(_ template: CanvasTemplate) {
        guard let data = template.templateJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(
                  with: data
              ) as? [String: Any]
        else {
            errorMessage = "Failed to parse library template JSON"
            return
        }

        var config = CanvasTemplateConfig()
        if let id = dict["id"] as? String { config.id = id }
        if let label = dict["label"] as? String { config.label = label }
        if let target = dict["target_dimensions"] as? [String: Any] {
            if let w = target["width"] as? Int { config.targetWidth = w }
            if let h = target["height"] as? Int { config.targetHeight = h }
        }
        if let fs = dict["fit_source"] as? String { config.fitSource = fs }
        if let fm = dict["fit_method"] as? String { config.fitMethod = fm }
        if let ah = dict["alignment_method_horizontal"] as? String {
            config.alignmentHorizontal = ah
        }
        if let av = dict["alignment_method_vertical"] as? String {
            config.alignmentVertical = av
        }
        if let p = dict["preserve_from_source_canvas"] as? String {
            config.preserveFromSourceCanvas = p
        }
        if let pm = dict["pad_to_maximum"] as? Bool {
            config.padToMaximum = pm
        }
        if let maxDims = dict["maximum_dimensions"] as? [String: Any] {
            config.maximumWidth = maxDims["width"] as? Int
            config.maximumHeight = maxDims["height"] as? Int
        }
        if let rounding = dict["round"] as? [String: Any] {
            if let re = rounding["even"] as? String { config.roundEven = re }
            if let rm = rounding["mode"] as? String { config.roundMode = rm }
        }

        templateConfig = config
        selectedPresetName = template.name
    }

    func saveTemplateToLibrary(
        libraryStore: LibraryStore,
        libraryViewModel: LibraryViewModel
    ) {
        let dict = templateConfig.toDict()
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
        ),
              let jsonStr = String(data: data, encoding: .utf8)
        else {
            errorMessage = "Failed to serialize template"
            return
        }

        let template = CanvasTemplate(
            name: templateConfig.label,
            description: nil,
            templateJSON: jsonStr,
            source: "FDL Viewer"
        )
        do {
            try libraryStore.saveCanvasTemplate(template)
            libraryViewModel.refreshCanvasTemplates()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func assignTemplateToProject(
        projectID: String,
        libraryStore: LibraryStore,
        libraryViewModel: LibraryViewModel
    ) {
        let dict = templateConfig.toDict()
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
        ),
              let jsonStr = String(data: data, encoding: .utf8)
        else {
            errorMessage = "Failed to serialize template"
            return
        }

        let template = CanvasTemplate(
            name: templateConfig.label,
            description: nil,
            templateJSON: jsonStr,
            source: "FDL Viewer"
        )
        do {
            try libraryStore.saveCanvasTemplate(template)
            try libraryStore.assignTemplate(
                templateID: template.id, toProject: projectID
            )
            libraryViewModel.refreshCanvasTemplates()
        } catch {
            errorMessage = "Assign failed: \(error.localizedDescription)"
        }
    }

    func resetTemplateValues() {
        let label = templateConfig.label
        templateConfig = CanvasTemplateConfig()
        templateConfig.label = label
        selectedPresetName = nil
    }

    func resetTemplate() {
        templateConfig = CanvasTemplateConfig()
        selectedPresetName = nil
        outputDocument = nil
        outputGeometry = nil
        outputRawJSON = nil
        transformInfo = nil
    }

    func importTemplateJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .data]
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
        guard loadedDocument != nil else {
            errorMessage = "No source FDL loaded"
            return
        }

        isApplyingTemplate = true
        let ctxIndex = selectedContextIndex
        let canvasIndex = selectedCanvasIndex
        let fdIndex = selectedFramingIndex ?? 0

        Task {
            defer {
                isApplyingTemplate = false
            }

            var usedPython = false

            if let rawJSON,
               let fdlDict = try? JSONSerialization.jsonObject(
                   with: Data(rawJSON.utf8)
               ) as? [String: Any],
               let templateJSON = try? JSONSerialization.data(
                   withJSONObject: templateConfig.toDict()
               ),
               let templateStr = String(data: templateJSON, encoding: .utf8),
               let fdlData = try? JSONSerialization.data(withJSONObject: fdlDict),
               let fdlStr = String(data: fdlData, encoding: .utf8) {
                do {
                    let response = try await withTimeout(seconds: 8) {
                        try await pythonBridge.callForResult(
                            "template.apply_fdl",
                            params: [
                                "fdl_json": fdlStr,
                                "template_json": templateStr,
                                "context_index": ctxIndex,
                                "canvas_index": canvasIndex,
                                "fd_index": fdIndex,
                            ]
                        )
                    }

                    if let resultFdl = response["fdl"] as? [String: Any] {
                        let data = try JSONSerialization.data(
                            withJSONObject: resultFdl,
                            options: .prettyPrinted
                        )
                        outputDocument = try JSONDecoder().decode(
                            FDLDocument.self, from: data
                        )
                        outputRawJSON = String(data: data, encoding: .utf8)

                        let geoResponse = try await withTimeout(seconds: 5) {
                            try await pythonBridge.callForResult(
                                "geometry.compute_rects",
                                params: ["fdl_data": resultFdl]
                            )
                        }
                        let geoData = try JSONSerialization.data(
                            withJSONObject: geoResponse
                        )
                        outputGeometry = try JSONDecoder().decode(
                            ComputedGeometry.self, from: geoData
                        )
                    }
                    usedPython = true
                } catch {
                    print("Python bridge template failed, using local: \(error)")
                }
            }

            if !usedPython {
                applyTemplateLocally(
                    ctxIndex: ctxIndex,
                    canvasIndex: canvasIndex,
                    fdIndex: fdIndex
                )
            }

            buildTransformInfo()
            activeTab = .output
        }
    }

    /// Local Swift-only template application following ASC FDL spec.
    private func applyTemplateLocally(
        ctxIndex: Int, canvasIndex: Int, fdIndex: Int
    ) {
        guard let doc = loadedDocument,
              ctxIndex < doc.contexts.count else { return }
        let ctx = doc.contexts[ctxIndex]
        guard canvasIndex < ctx.canvases.count else { return }
        let canvas = ctx.canvases[canvasIndex]
        guard fdIndex < canvas.framingDecisions.count else { return }
        let fd = canvas.framingDecisions[fdIndex]
        let template = templateConfig

        let sourceDims: (w: Double, h: Double) = {
            switch template.fitSource {
            case "framing_decision.protection_dimensions":
                if let p = fd.protectionDimensions {
                    return (p.width, p.height)
                }
                return (fd.dimensions.width, fd.dimensions.height)
            case "canvas.effective_dimensions":
                if let e = canvas.effectiveDimensions {
                    return (e.width, e.height)
                }
                return (canvas.dimensions.width, canvas.dimensions.height)
            case "canvas.dimensions":
                return (canvas.dimensions.width, canvas.dimensions.height)
            default:
                return (fd.dimensions.width, fd.dimensions.height)
            }
        }()

        let tw = Double(template.targetWidth)
        let th = Double(template.targetHeight)

        let scale: Double = {
            let sx = tw / max(sourceDims.w, 1)
            let sy = th / max(sourceDims.h, 1)
            switch template.fitMethod {
            case "fill": return max(sx, sy)
            case "width": return sx
            case "height": return sy
            default: return min(sx, sy)
            }
        }()

        func applyRound(_ val: Double) -> Double {
            let rounded: Double
            switch template.roundMode {
            case "down": rounded = floor(val)
            case "round": rounded = (val).rounded()
            default: rounded = ceil(val)
            }
            if template.roundEven == "even" {
                let r = Int(rounded)
                return Double(r % 2 == 0 ? r : r + 1)
            }
            return rounded
        }

        let newFW = applyRound(fd.dimensions.width * scale)
        let newFH = applyRound(fd.dimensions.height * scale)
        var newCW = tw
        var newCH = th

        var newProtW: Double?
        var newProtH: Double?
        if let p = fd.protectionDimensions {
            newProtW = applyRound(p.width * scale)
            newProtH = applyRound(p.height * scale)
        }

        var newEffW: Double?
        var newEffH: Double?
        if let e = canvas.effectiveDimensions {
            newEffW = applyRound(e.width * scale)
            newEffH = applyRound(e.height * scale)
        }

        if let mw = template.maximumWidth, let mh = template.maximumHeight {
            newCW = min(newCW, Double(mw))
            newCH = min(newCH, Double(mh))
            if template.padToMaximum {
                newCW = Double(mw)
                newCH = Double(mh)
            }
        }

        func anchor(
            _ objW: Double, _ objH: Double,
            in containerW: Double, _ containerH: Double
        ) -> FDLPoint {
            let x: Double
            switch template.alignmentHorizontal {
            case "left": x = 0
            case "right": x = containerW - objW
            default: x = (containerW - objW) / 2
            }
            let y: Double
            switch template.alignmentVertical {
            case "top": y = 0
            case "bottom": y = containerH - objH
            default: y = (containerH - objH) / 2
            }
            return FDLPoint(x: x, y: y)
        }

        let framingAnchor = anchor(newFW, newFH, in: newCW, newCH)
        let protAnchor: FDLPoint? = {
            guard let pw = newProtW, let ph = newProtH else { return nil }
            return anchor(pw, ph, in: newCW, newCH)
        }()
        let effAnchor: FDLPoint? = {
            guard let ew = newEffW, let eh = newEffH else { return nil }
            return anchor(ew, eh, in: newCW, newCH)
        }()

        var newFD = fd
        newFD.dimensions = FDLDimensions(width: newFW, height: newFH)
        newFD.anchorPoint = framingAnchor
        if let pw = newProtW, let ph = newProtH {
            newFD.protectionDimensions = FDLDimensions(width: pw, height: ph)
            newFD.protectionAnchorPoint = protAnchor
        }

        var newCanvas = canvas
        newCanvas.dimensions = FDLDimensions(width: newCW, height: newCH)
        if let ew = newEffW, let eh = newEffH {
            newCanvas.effectiveDimensions = FDLDimensions(width: ew, height: eh)
            newCanvas.effectiveAnchorPoint = effAnchor
        }
        var fds = newCanvas.framingDecisions
        if fdIndex < fds.count { fds[fdIndex] = newFD }
        newCanvas.framingDecisions = fds

        var newCtx = ctx
        var canvases = newCtx.canvases
        if canvasIndex < canvases.count { canvases[canvasIndex] = newCanvas }
        newCtx.canvases = canvases

        var newDoc = doc
        var contexts = newDoc.contexts
        if ctxIndex < contexts.count { contexts[ctxIndex] = newCtx }
        newDoc.contexts = contexts

        outputDocument = newDoc
        outputGeometry = computeGeometryLocally(from: newDoc)

        if let data = try? JSONEncoder().encode(newDoc),
           let json = String(data: data, encoding: .utf8) {
            outputRawJSON = json
        }
    }

    private func buildTransformInfo() {
        let srcCanvas = selectedCanvas
        let srcFD = selectedFramingDecision
            ?? selectedCanvas?.framingDecisions.first
        var info = TransformInfo(
            sourceCanvas: formatDims(
                srcCanvas?.dimensions.width,
                srcCanvas?.dimensions.height
            ),
            sourceFraming: formatDims(
                srcFD?.dimensions.width, srcFD?.dimensions.height
            )
        )

        if let outDoc = outputDocument,
           let outCtx = outDoc.contexts.first,
           let outCanvas = outCtx.canvases.first
        {
            info.outputCanvas = formatDims(
                outCanvas.dimensions.width,
                outCanvas.dimensions.height
            )
            if let outFD = outCanvas.framingDecisions.first {
                info.outputFraming = formatDims(
                    outFD.dimensions.width, outFD.dimensions.height
                )
            }
        }

        transformInfo = info
    }

    private func formatDims(_ w: Double?, _ h: Double?) -> String {
        "\(Int(w ?? 0))\u{00D7}\(Int(h ?? 0))"
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
        panel.allowedContentTypes = [.json, .data]
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
        activeTab = .source

        referenceImage = nil
        referenceImagePath = nil
        overlayPNGBase64 = nil
        outputDocument = nil
        outputGeometry = nil
        outputRawJSON = nil
        transformInfo = nil

        let data: Data
        do {
            data = try Data(contentsOf: url)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                errorMessage = "File is not valid UTF-8 text"
                return
            }
            rawJSON = jsonString
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
            return
        }

        // Parse locally first so the UI is immediately populated
        do {
            loadedDocument = try JSONDecoder().decode(
                FDLDocument.self, from: data
            )
            computedGeometry = computeGeometryLocally(from: loadedDocument!)
        } catch {
            errorMessage = "Invalid FDL: \(error.localizedDescription)"
            loadedDocument = nil
            return
        }

        // Enhance with Python bridge (validation, normalized parse) in background
        Task {
            await enhanceWithPythonBridge(url: url, pythonBridge: pythonBridge)
        }
    }

    private func enhanceWithPythonBridge(
        url: URL, pythonBridge: PythonBridge
    ) async {
        guard let rawJSON else { return }

        do {
            let parseResponse = try await pythonBridge.callForResult(
                "fdl.parse", params: ["path": url.path]
            )
            if let fdlDict = parseResponse["fdl"] as? [String: Any] {
                let data = try JSONSerialization.data(
                    withJSONObject: fdlDict
                )
                let bridgeDoc = try JSONDecoder().decode(
                    FDLDocument.self, from: data
                )
                loadedDocument = bridgeDoc
            }

            let valResponse = try await pythonBridge.callForResult(
                "fdl.validate", params: ["path": url.path]
            )
            let valData = try JSONSerialization.data(
                withJSONObject: valResponse
            )
            validationResult = try JSONDecoder().decode(
                ValidationResult.self, from: valData
            )

            guard let fdlDict = try? JSONSerialization.jsonObject(
                with: Data(rawJSON.utf8)
            ) as? [String: Any] else { return }

            let geoResponse = try await pythonBridge.callForResult(
                "geometry.compute_rects", params: ["fdl_data": fdlDict]
            )
            let geoData = try JSONSerialization.data(
                withJSONObject: geoResponse
            )
            computedGeometry = try JSONDecoder().decode(
                ComputedGeometry.self, from: geoData
            )
        } catch {
            // Python bridge enhancement is non-critical;
            // local parsing already succeeded
            print("Python bridge enhancement failed: \(error)")
        }
    }

    /// Compute geometry rectangles locally from an FDLDocument.
    /// Used as immediate fallback when Python bridge is unavailable.
    func computeGeometryLocally(
        from doc: FDLDocument
    ) -> ComputedGeometry {
        let contexts = doc.contexts.map { ctx -> ComputedContext in
            let canvases = ctx.canvases.map { canvas -> ComputedCanvas in
                let cw = canvas.dimensions.width
                let ch = canvas.dimensions.height
                let canvasRect = GeometryRect(
                    x: 0, y: 0, width: cw, height: ch
                )

                var effectiveRect: GeometryRect?
                if let eff = canvas.effectiveDimensions {
                    let ex: Double
                    let ey: Double
                    if let anchor = canvas.effectiveAnchorPoint {
                        ex = anchor.x
                        ey = anchor.y
                    } else {
                        ex = (cw - eff.width) / 2
                        ey = (ch - eff.height) / 2
                    }
                    effectiveRect = GeometryRect(
                        x: ex, y: ey,
                        width: eff.width, height: eff.height
                    )
                }

                let fds = canvas.framingDecisions.map { fd
                    -> ComputedFramingDecision in
                    let fw = fd.dimensions.width
                    let fh = fd.dimensions.height
                    let fx: Double
                    let fy: Double
                    if let anchor = fd.anchorPoint {
                        fx = anchor.x
                        fy = anchor.y
                    } else {
                        fx = (cw - fw) / 2
                        fy = (ch - fh) / 2
                    }
                    let framingRect = GeometryRect(
                        x: fx, y: fy, width: fw, height: fh
                    )

                    var protectionRect: GeometryRect?
                    if let prot = fd.protectionDimensions {
                        let px: Double
                        let py: Double
                        if let pa = fd.protectionAnchorPoint {
                            px = pa.x
                            py = pa.y
                        } else {
                            px = (cw - prot.width) / 2
                            py = (ch - prot.height) / 2
                        }
                        protectionRect = GeometryRect(
                            x: px, y: py,
                            width: prot.width, height: prot.height
                        )
                    }

                    var anchorPoint: GeometryPoint?
                    if let ap = fd.anchorPoint {
                        anchorPoint = GeometryPoint(x: ap.x, y: ap.y)
                    }

                    return ComputedFramingDecision(
                        label: fd.label ?? fd.id,
                        framingIntent: fd.framingIntentId ?? "",
                        framingRect: framingRect,
                        protectionRect: protectionRect,
                        anchorPoint: anchorPoint
                    )
                }

                return ComputedCanvas(
                    label: canvas.label,
                    canvasRect: canvasRect,
                    effectiveRect: effectiveRect,
                    framingDecisions: fds
                )
            }

            return ComputedContext(
                label: ctx.label, canvases: canvases
            )
        }

        return ComputedGeometry(contexts: contexts)
    }

    // MARK: - Load from In-Memory Document

    func loadDocument(_ doc: FDLDocument, fileName: String) {
        loadedFileName = fileName
        loadedFilePath = nil
        activeTab = .source

        referenceImage = nil
        referenceImagePath = nil
        overlayPNGBase64 = nil
        outputDocument = nil
        outputGeometry = nil
        outputRawJSON = nil
        transformInfo = nil

        loadedDocument = doc
        computedGeometry = computeGeometryLocally(from: doc)

        if let data = try? JSONEncoder().encode(doc),
           let json = String(data: data, encoding: .utf8) {
            rawJSON = json
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
        activeTab = .source
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
