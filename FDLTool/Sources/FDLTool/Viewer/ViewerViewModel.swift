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
        if let tas = dict["target_anamorphic_squeeze"] as? Double { config.targetAnamorphicSqueeze = tas }
        else if let tas = dict["target_anamorphic_squeeze"] as? Int { config.targetAnamorphicSqueeze = Double(tas) }
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

            // Support both bare template objects and FDL-wrapped canvas_templates arrays
            let templateDict: [String: Any]
            if let templates = dict["canvas_templates"] as? [[String: Any]], let first = templates.first {
                templateDict = first
            } else {
                templateDict = dict
            }

            var config = CanvasTemplateConfig()

            if let id = templateDict["id"] as? String { config.id = id }
            if let label = templateDict["label"] as? String { config.label = label }

            if let target = templateDict["target_dimensions"] as? [String: Any] {
                if let w = target["width"] as? Int { config.targetWidth = w }
                if let h = target["height"] as? Int { config.targetHeight = h }
            }
            if let tas = templateDict["target_anamorphic_squeeze"] as? Double { config.targetAnamorphicSqueeze = tas }
            else if let tas = templateDict["target_anamorphic_squeeze"] as? Int { config.targetAnamorphicSqueeze = Double(tas) }
            if let fitSrc = templateDict["fit_source"] as? String { config.fitSource = fitSrc }
            if let fitMeth = templateDict["fit_method"] as? String { config.fitMethod = fitMeth }
            if let ah = templateDict["alignment_method_horizontal"] as? String { config.alignmentHorizontal = ah }
            if let av = templateDict["alignment_method_vertical"] as? String { config.alignmentVertical = av }
            if let preserve = templateDict["preserve_from_source_canvas"] as? String { config.preserveFromSourceCanvas = preserve }
            if let padMax = templateDict["pad_to_maximum"] as? Bool { config.padToMaximum = padMax }

            if let maxDims = templateDict["maximum_dimensions"] as? [String: Any] {
                config.maximumWidth = maxDims["width"] as? Int
                config.maximumHeight = maxDims["height"] as? Int
            }

            if let rounding = templateDict["round"] as? [String: Any] {
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

        applyTemplateLocally(
            ctxIndex: selectedContextIndex,
            canvasIndex: selectedCanvasIndex,
            fdIndex: selectedFramingIndex ?? 0
        )
        buildTransformInfo()
        activeTab = .output
        isApplyingTemplate = false
    }

    // MARK: - ASC FDL Template Application (10-step pipeline)

    private struct GeoLayer {
        var w: Double = 0, h: Double = 0
        var ax: Double = 0, ay: Double = 0
        var populated: Bool = false
    }

    /// Full ASC FDL spec template application (10-step pipeline).
    /// Reference: https://ascmitc.github.io/fdl/dev/FDL_Apply_Template_Logic/
    private func applyTemplateLocally(
        ctxIndex: Int, canvasIndex: Int, fdIndex: Int
    ) {
        guard let doc = loadedDocument,
              ctxIndex < doc.contexts.count else { return }
        let ctx = doc.contexts[ctxIndex]
        guard canvasIndex < ctx.canvases.count else { return }
        let srcCanvas = ctx.canvases[canvasIndex]
        guard fdIndex < srcCanvas.framingDecisions.count else { return }
        let srcFD = srcCanvas.framingDecisions[fdIndex]
        let tmpl = templateConfig

        // ── Step 1: Derive Configuration ──
        let inputSqueeze = srcCanvas.anamorphicSqueeze ?? 1.0
        let targetSqueeze = tmpl.targetAnamorphicSqueeze
        let targetW = Double(tmpl.targetWidth)
        let targetH = Double(tmpl.targetHeight)
        let preservePath = tmpl.preserveFromSourceCanvas
        let fitSource = tmpl.fitSource
        let hasMax = tmpl.maximumWidth != nil && tmpl.maximumHeight != nil
        let maxW = Double(tmpl.maximumWidth ?? 0)
        let maxH = Double(tmpl.maximumHeight ?? 0)
        let padToMax = tmpl.padToMaximum

        let hAlignFactor: Double = {
            switch tmpl.alignmentHorizontal {
            case "left": return 0.0
            case "right": return 1.0
            default: return 0.5
            }
        }()
        let vAlignFactor: Double = {
            switch tmpl.alignmentVertical {
            case "top": return 0.0
            case "bottom": return 1.0
            default: return 0.5
            }
        }()

        // Rounding helper per spec: round(val / base) * base
        func specRound(_ val: Double) -> Double {
            let base: Double = tmpl.roundEven == "even" ? 2.0 : 1.0
            switch tmpl.roundMode {
            case "down": return floor(val / base) * base
            case "round": return (val / base).rounded() * base
            default: return ceil(val / base) * base
            }
        }

        // ── Step 2: Populate Source Geometry ──
        // Hierarchy: canvas(0) >= effective(1) >= protection(2) >= framing(3)
        func layerLevel(_ path: String) -> Int {
            switch path {
            case "canvas.dimensions": return 0
            case "canvas.effective_dimensions": return 1
            case "framing_decision.protection_dimensions": return 2
            case "framing_decision.dimensions": return 3
            default: return 3
            }
        }

        func sourceLayer(for path: String) -> GeoLayer? {
            switch path {
            case "canvas.dimensions":
                return GeoLayer(w: srcCanvas.dimensions.width, h: srcCanvas.dimensions.height,
                                ax: 0, ay: 0, populated: true)
            case "canvas.effective_dimensions":
                if let e = srcCanvas.effectiveDimensions {
                    let a = srcCanvas.effectiveAnchorPoint ?? FDLPoint(x: 0, y: 0)
                    return GeoLayer(w: e.width, h: e.height, ax: a.x, ay: a.y, populated: true)
                }
                return nil
            case "framing_decision.protection_dimensions":
                if let p = srcFD.protectionDimensions {
                    let a = srcFD.protectionAnchorPoint ?? FDLPoint(x: 0, y: 0)
                    return GeoLayer(w: p.width, h: p.height, ax: a.x, ay: a.y, populated: true)
                }
                return nil
            case "framing_decision.dimensions":
                let a = srcFD.anchorPoint ?? FDLPoint(x: 0, y: 0)
                return GeoLayer(w: srcFD.dimensions.width, h: srcFD.dimensions.height,
                                ax: a.x, ay: a.y, populated: true)
            default:
                return nil
            }
        }

        // Build geometry: 4 layers [canvas, effective, protection, framing]
        var geo: [GeoLayer] = Array(repeating: GeoLayer(), count: 4)

        // Populate from preserve path downward (if specified)
        if let pp = preservePath {
            let startLevel = layerLevel(pp)
            let paths = ["canvas.dimensions", "canvas.effective_dimensions",
                         "framing_decision.protection_dimensions", "framing_decision.dimensions"]
            for level in startLevel...3 {
                if let layer = sourceLayer(for: paths[level]) {
                    geo[level] = layer
                }
            }
        }

        // Populate from fit_source downward (overwrites overlap)
        let fitLevel = layerLevel(fitSource)
        let paths = ["canvas.dimensions", "canvas.effective_dimensions",
                     "framing_decision.protection_dimensions", "framing_decision.dimensions"]
        for level in fitLevel...3 {
            if let layer = sourceLayer(for: paths[level]) {
                geo[level] = layer
            }
        }

        // ── Step 3: Fill Hierarchy Gaps ──
        // Reference: fdl_geometry.cpp geometry_fill_hierarchy_gaps()
        let outermostPop = geo.firstIndex(where: { $0.populated }) ?? 3

        // Fill canvas(0) and effective(1) from outermost populated layer
        if !geo[0].populated {
            geo[0] = GeoLayer(w: geo[outermostPop].w, h: geo[outermostPop].h,
                              ax: 0, ay: 0, populated: true)
        }
        if !geo[1].populated {
            geo[1] = GeoLayer(w: geo[outermostPop].w, h: geo[outermostPop].h,
                              ax: geo[outermostPop].ax, ay: geo[outermostPop].ay, populated: true)
        }
        // Protection(2) is NEVER filled from framing - stays absent unless explicitly populated

        // Anchor offset: from preserve anchor if set, else fit_source anchor
        let refLevel = preservePath != nil ? layerLevel(preservePath!) : fitLevel
        let anchorOffsetX = geo[refLevel].ax
        let anchorOffsetY = geo[refLevel].ay

        // Subtract anchor offset from effective, protection, framing anchors (not canvas)
        // Then clamp to >= 0 per reference
        for i in 1...3 {
            geo[i].ax = max(geo[i].ax - anchorOffsetX, 0)
            geo[i].ay = max(geo[i].ay - anchorOffsetY, 0)
        }

        let fitDims = geo[fitLevel]

        // ── Step 4: Compute Scale Factor ──
        let fitNormW = fitDims.w * inputSqueeze
        let fitNormH = fitDims.h
        let targetNormW = targetW * targetSqueeze
        let targetNormH = targetH

        let wRatio = targetNormW / max(fitNormW, 0.001)
        let hRatio = targetNormH / max(fitNormH, 0.001)

        let scale: Double = {
            switch tmpl.fitMethod {
            case "fill": return max(wRatio, hRatio)
            case "width": return wRatio
            case "height": return hRatio
            default: return min(wRatio, hRatio)
            }
        }()

        // ── Step 5: Scale and Round ──
        // Widths/x-anchors: (value * inputSqueeze * scale) / targetSqueeze
        // Heights/y-anchors: value * scale
        func scaleW(_ v: Double) -> Double { specRound((v * inputSqueeze * scale) / max(targetSqueeze, 0.001)) }
        func scaleH(_ v: Double) -> Double { specRound(v * scale) }
        func scaleAx(_ v: Double) -> Double { specRound((v * inputSqueeze * scale) / max(targetSqueeze, 0.001)) }
        func scaleAy(_ v: Double) -> Double { specRound(v * scale) }

        for i in 0...3 where geo[i].populated {
            geo[i].w = scaleW(geo[i].w)
            geo[i].h = scaleH(geo[i].h)
            geo[i].ax = scaleAx(geo[i].ax)
            geo[i].ay = scaleAy(geo[i].ay)
        }

        let scaledFitW = geo[fitLevel].w
        let scaledFitH = geo[fitLevel].h
        let scaledFitAx = geo[fitLevel].ax
        let scaledFitAy = geo[fitLevel].ay
        let scaledCanvasW = geo[0].w
        let scaledCanvasH = geo[0].h

        // ── Step 6: Determine Output Size (per axis) ──
        func outputSize(canvasSize: Double, maxSize: Double) -> Double {
            if hasMax && padToMax { return maxSize }
            if hasMax && canvasSize > maxSize { return maxSize }
            return canvasSize
        }

        let outputW = outputSize(canvasSize: scaledCanvasW, maxSize: maxW)
        let outputH = outputSize(canvasSize: scaledCanvasH, maxSize: maxH)

        // ── Step 7: Calculate Alignment Shift (per axis) ──
        func alignmentShift(
            outputSize: Double, canvasSize: Double, targetSize: Double,
            fitSize: Double, fitAnchor: Double, alignFactor: Double
        ) -> Double {
            let overflow = canvasSize - outputSize
            if overflow == 0 && !padToMax { return 0 }

            let isCenter = alignFactor == 0.5
            let centerTarget = padToMax || isCenter
            let targetOffset = centerTarget ? (outputSize - targetSize) * 0.5 : 0
            let gap = targetSize - fitSize
            let alignment = gap * alignFactor
            var shift = targetOffset + alignment - fitAnchor

            if !padToMax && overflow > 0 {
                shift = max(min(shift, 0), -overflow)
            }
            return shift
        }

        let shiftX = alignmentShift(
            outputSize: outputW, canvasSize: scaledCanvasW, targetSize: targetW,
            fitSize: scaledFitW, fitAnchor: scaledFitAx, alignFactor: hAlignFactor)
        let shiftY = alignmentShift(
            outputSize: outputH, canvasSize: scaledCanvasH, targetSize: targetH,
            fitSize: scaledFitH, fitAnchor: scaledFitAy, alignFactor: vAlignFactor)

        // ── Step 8: Apply Offsets to Anchors ──
        // Theoretical (unclamped) and clamped anchors
        struct AnchorPair { var clamped: (x: Double, y: Double); var theoretical: (x: Double, y: Double) }
        var anchors: [AnchorPair] = []
        for i in 0...3 {
            let tx = geo[i].ax + shiftX
            let ty = geo[i].ay + shiftY
            anchors.append(AnchorPair(
                clamped: (max(tx, 0), max(ty, 0)),
                theoretical: (tx, ty)
            ))
        }

        // ── Step 9: Crop to Visible ──
        for i in 0...3 where geo[i].populated {
            let clipLeft = max(0, -anchors[i].theoretical.x)
            let clipTop = max(0, -anchors[i].theoretical.y)
            var visW = geo[i].w - clipLeft
            var visH = geo[i].h - clipTop
            visW = min(visW, outputW - anchors[i].clamped.x)
            visH = min(visH, outputH - anchors[i].clamped.y)
            geo[i].w = max(visW, 0)
            geo[i].h = max(visH, 0)
        }

        // Enforce hierarchy: effective <= canvas, protection <= effective, framing <= protection/effective
        geo[1].w = min(geo[1].w, geo[0].w); geo[1].h = min(geo[1].h, geo[0].h)
        if geo[2].populated {
            geo[2].w = min(geo[2].w, geo[1].w); geo[2].h = min(geo[2].h, geo[1].h)
            geo[3].w = min(geo[3].w, geo[2].w); geo[3].h = min(geo[3].h, geo[2].h)
        } else {
            geo[3].w = min(geo[3].w, geo[1].w); geo[3].h = min(geo[3].h, geo[1].h)
        }

        // ── Step 10: Create Output FDL ──
        let canvasId = String((0..<8).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })

        var newFD = FDLFramingDecision(
            id: "\(canvasId)-1",
            label: srcFD.label,
            framingIntentId: srcFD.framingIntentId,
            dimensions: FDLDimensions(width: geo[3].w, height: geo[3].h),
            anchorPoint: FDLPoint(x: anchors[3].clamped.x, y: anchors[3].clamped.y),
            protectionDimensions: nil,
            protectionAnchorPoint: nil
        )

        if geo[2].populated {
            newFD.protectionDimensions = FDLDimensions(width: geo[2].w, height: geo[2].h)
            newFD.protectionAnchorPoint = FDLPoint(x: anchors[2].clamped.x, y: anchors[2].clamped.y)
        }

        let canvasLabel = "\(tmpl.label): \(ctx.label ?? "Context") \(srcCanvas.label ?? srcCanvas.id)"
        let newCanvas = FDLCanvas(
            id: canvasId,
            label: canvasLabel,
            sourceCanvasId: srcCanvas.id,
            dimensions: FDLDimensions(width: outputW, height: outputH),
            effectiveDimensions: FDLDimensions(width: geo[1].w, height: geo[1].h),
            effectiveAnchorPoint: FDLPoint(x: anchors[1].clamped.x, y: anchors[1].clamped.y),
            photositeDimensions: nil,
            physicalDimensions: nil,
            anamorphicSqueeze: targetSqueeze,
            framingDecisions: [newFD]
        )

        let newCtx = FDLContext(
            id: UUID(),
            label: tmpl.label,
            contextCreator: doc.fdlCreator,
            canvases: [newCanvas]
        )

        var canvasTemplateModel = FDLCanvasTemplate(
            id: tmpl.id,
            label: tmpl.label,
            targetDimensions: FDLDimensions(width: targetW, height: targetH),
            targetAnamorphicSqueeze: targetSqueeze,
            fitSource: tmpl.fitSource,
            fitMethod: tmpl.fitMethod,
            alignmentMethodVertical: tmpl.alignmentVertical,
            alignmentMethodHorizontal: tmpl.alignmentHorizontal
        )
        if hasMax {
            canvasTemplateModel.maximumDimensions = FDLDimensions(width: maxW, height: maxH)
        }
        canvasTemplateModel.padToMaximum = padToMax
        canvasTemplateModel.round = FDLRoundConfig(even: tmpl.roundEven, mode: tmpl.roundMode)
        if let preserve = preservePath {
            canvasTemplateModel.preserveFromSourceCanvas = preserve
        }

        var newDoc = doc
        newDoc.contexts.append(newCtx)
        newDoc.canvasTemplates = [canvasTemplateModel]

        outputDocument = newDoc
        outputGeometry = computeGeometryLocally(from: newDoc)

        if let json = FDLJSONSerializer.string(from: newDoc) {
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
           let outCtx = outDoc.contexts.last,
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
              let ctx = geo.contexts.last,
              let canvas = ctx.canvases.first else { return nil }
        return canvas
    }

    var outputCanvasDimensions: (width: Double, height: Double)? {
        if let doc = outputDocument,
           let ctx = doc.contexts.last,
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

        if let json = FDLJSONSerializer.string(from: doc) {
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
