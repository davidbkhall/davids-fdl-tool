import Foundation
import OSLog
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class ViewerViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.fdltool.app", category: "template-apply")
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
    @Published var showReferenceImage = true

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

    // Source provenance tracking (for Workspace -> Library linking)
    private var loadedLibraryEntryID: String?
    private var loadedLibraryProjectID: String?
    @Published var framelineStatus = FramelineInteropStatus()
    @Published var framelineReport: FramelineConversionReport?
    @Published var arriCameras: [FramelineCameraOption] = []
    @Published var sonyCameras: [FramelineCameraOption] = []
    @Published var selectedArriCameraType = ""
    @Published var selectedArriSensorMode = ""
    @Published var selectedSonyCameraType = ""
    @Published var selectedSonyImagerMode = ""

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

    func applyScenarioPresetAndTransform(
        _ name: String,
        pythonBridge: PythonBridge,
        defaultCreator: String
    ) {
        applyPreset(name)
        applyTemplate(pythonBridge: pythonBridge, defaultCreator: defaultCreator)
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
        guard let jsonStr = currentTemplateJSONString()
        else {
            errorMessage = "Failed to serialize template"
            return
        }

        let template = CanvasTemplate(
            name: templateConfig.label,
            description: nil,
            templateJSON: jsonStr,
            source: "Framing Workspace"
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
        guard let jsonStr = currentTemplateJSONString()
        else {
            errorMessage = "Failed to serialize template"
            return
        }

        let template = CanvasTemplate(
            name: templateConfig.label,
            description: nil,
            templateJSON: jsonStr,
            source: "Framing Workspace"
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

    func saveOutputToProject(
        projectID: String,
        libraryStore: LibraryStore,
        libraryViewModel: LibraryViewModel,
        sourceEntryID: String? = nil,
        sourceProjectID: String? = nil
    ) {
        guard let outputDoc = outputDocument else {
            errorMessage = "No output document to save"
            return
        }
        guard let outputJSON = outputRawJSON ?? FDLJSONSerializer.string(from: outputDoc),
              let jsonData = outputJSON.data(using: .utf8)
        else {
            errorMessage = "Failed to serialize output document"
            return
        }

        let templateJSON = currentTemplateJSONString()
        let templateID = templateConfig.id.isEmpty ? UUID().uuidString : templateConfig.id
        let templateName = templateConfig.label.isEmpty ? "Template" : templateConfig.label

        let baseName: String = {
            if let loadedFileName, !loadedFileName.isEmpty {
                return loadedFileName.replacingOccurrences(of: ".fdl.json", with: "")
            }
            return "FDL Output"
        }()
        let entryName = "\(baseName) - \(templateName)"
        let entryID = UUID().uuidString
        let outputPath = LibraryStore.projectDirectoryURL(projectID: projectID)
            .appendingPathComponent("\(entryID).fdl.json")
            .path

        let entry = FDLEntry(
            id: entryID,
            projectID: projectID,
            fdlUUID: outputDoc.id,
            name: entryName,
            filePath: outputPath,
            sourceTool: "viewer_output",
            cameraModel: nil,
            tags: ["viewer", "output", "template_applied"],
            createdAt: Date(),
            updatedAt: Date()
        )

        do {
            try libraryStore.addFDLEntry(entry, jsonData: jsonData)

            if let templateJSON {
                let template = CanvasTemplate(
                    id: templateID,
                    name: templateName,
                    description: nil,
                    templateJSON: templateJSON,
                    source: "Framing Workspace",
                    createdAt: Date(),
                    updatedAt: Date()
                )
                try libraryStore.saveCanvasTemplate(template)
                try libraryStore.assignTemplate(templateID: template.id, toProject: projectID)
                let link = ProjectAssetLink(
                    projectID: projectID,
                    fromAssetID: "asset-fdl-\(entry.id)",
                    toAssetID: "asset-template-\(projectID)-\(template.id)",
                    linkType: .usesTemplate
                )
                try libraryStore.linkAssets(link)
            }

            let resolvedSourceEntryID = sourceEntryID ?? loadedLibraryEntryID
            let resolvedSourceProjectID = sourceProjectID ?? loadedLibraryProjectID
            if let resolvedSourceEntryID,
               let resolvedSourceProjectID,
               resolvedSourceProjectID == projectID,
               resolvedSourceEntryID != entry.id {
                let sourceAssetID = "asset-fdl-\(resolvedSourceEntryID)"
                let derived = ProjectAssetLink(
                    projectID: projectID,
                    fromAssetID: "asset-fdl-\(entry.id)",
                    toAssetID: sourceAssetID,
                    linkType: .derivedFrom
                )
                try libraryStore.linkAssets(derived)
            }

            if libraryViewModel.selectedProject?.id == projectID {
                libraryViewModel.loadEntries()
                libraryViewModel.refreshCanvasTemplates()
            }
        } catch {
            errorMessage = "Save output failed: \(error.localizedDescription)"
        }
    }

    private func currentTemplateJSONString() -> String? {
        let dict = templateConfig.toDict()
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
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

    func applyTemplate(pythonBridge: PythonBridge, defaultCreator: String = "") {
        guard loadedDocument != nil else {
            errorMessage = "No source FDL loaded"
            return
        }

        isApplyingTemplate = true
        Task {
            do {
                try await applyTemplateWithBackend(
                    pythonBridge: pythonBridge,
                    defaultCreator: defaultCreator
                )
            } catch {
                // Backend-first path failed, fall back to the local
                // implementation so users can keep working offline.
                logger.error("Backend template apply failed; using local fallback: \(error.localizedDescription)")
                applyTemplateLocally(
                    ctxIndex: selectedContextIndex,
                    canvasIndex: selectedCanvasIndex,
                    fdIndex: selectedFramingIndex ?? 0,
                    defaultCreator: defaultCreator
                )
                errorMessage = "Backend template apply failed; used local fallback. \(error.localizedDescription)"
            }
            buildTransformInfo()
            activeTab = .output
            isApplyingTemplate = false
        }
    }

    private func applyTemplateWithBackend(
        pythonBridge: PythonBridge,
        defaultCreator: String
    ) async throws {
        let doc = try await applyTemplateWithBackendDocument(
            pythonBridge: pythonBridge,
            defaultCreator: defaultCreator,
            template: templateConfig
        )
        outputDocument = doc
        outputGeometry = computeGeometryLocally(from: doc)
        outputRawJSON = FDLJSONSerializer.string(from: doc)
    }

    private func applyTemplateWithBackendDocument(
        pythonBridge: PythonBridge,
        defaultCreator: String,
        template: CanvasTemplateConfig
    ) async throws -> FDLDocument {
        guard let sourceDoc = loadedDocument,
              let fdlJSON = FDLJSONSerializer.string(from: sourceDoc)
        else {
            throw NSError(
                domain: "FDLTool",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No source document for template apply"]
            )
        }

        let templateDict = template.toDict()
        let templateData = try JSONSerialization.data(withJSONObject: templateDict)
        guard let templateJSON = String(data: templateData, encoding: .utf8) else {
            throw NSError(
                domain: "FDLTool",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to serialize template JSON"]
            )
        }

        let response = try await pythonBridge.callForResult(
            "template.apply_fdl",
            params: [
                "fdl_json": fdlJSON,
                "template_json": templateJSON,
                "context_index": selectedContextIndex,
                "canvas_index": selectedCanvasIndex,
                "fd_index": selectedFramingIndex ?? 0,
            ]
        )

        guard let outputFDL = response["fdl"] as? [String: Any] else {
            throw NSError(
                domain: "FDLTool",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Backend did not return an FDL result"]
            )
        }

        let outputData = try JSONSerialization.data(withJSONObject: outputFDL)
        var doc = try JSONDecoder().decode(FDLDocument.self, from: outputData)

        // Ensure output context creator follows app attribution convention.
        let creatorString = outputContextCreator(defaultCreator: defaultCreator)
        if !doc.contexts.isEmpty {
            doc.contexts[doc.contexts.count - 1].contextCreator = creatorString
        }

        return doc
    }

    func exportScenarioPack(
        presetNames: [String],
        pythonBridge: PythonBridge,
        defaultCreator: String,
        includeZip: Bool = true,
        projectID: String? = nil,
        libraryStore: LibraryStore? = nil
    ) {
        guard let sourceDoc = loadedDocument else {
            errorMessage = "Load a Source FDL before exporting a scenario pack."
            return
        }
        guard !presetNames.isEmpty else {
            errorMessage = "Select at least one scenario preset."
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.title = "Export Scenario Pack"

        guard panel.runModal() == .OK, let parentURL = panel.url else { return }

        Task {
            do {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-")
                let packName = "scenario-pack-\(timestamp)"
                let packURL = parentURL.appendingPathComponent(packName, isDirectory: true)
                try FileManager.default.createDirectory(at: packURL, withIntermediateDirectories: true)

                var manifest: [[String: Any]] = []

                if let sourceJSON = FDLJSONSerializer.string(from: sourceDoc) {
                    let sourceJSONURL = packURL.appendingPathComponent("source.fdl.json")
                    try sourceJSON.write(to: sourceJSONURL, atomically: true, encoding: .utf8)
                }

                var sourceFDLAssetID: String?
                var sourceChartAssetID: String?
                if let sourceChartData = try await renderSourceChartPNGData(pythonBridge: pythonBridge) {
                    let sourceChartURL = packURL.appendingPathComponent("source_chart.png")
                    try sourceChartData.write(to: sourceChartURL)
                }

                if let projectID, let libraryStore {
                    let sourceFDLPath = packURL.appendingPathComponent("source.fdl.json").path
                    let sourceChartPath = packURL.appendingPathComponent("source_chart.png").path

                    let sourceFDLAsset = ProjectAsset(
                        projectID: projectID,
                        assetType: .fdl,
                        name: "Scenario Pack Source FDL",
                        sourceTool: "viewer_scenario_pack",
                        referenceID: nil,
                        filePath: sourceFDLPath,
                        payloadJSON: nil
                    )
                    try libraryStore.saveProjectAsset(sourceFDLAsset)
                    sourceFDLAssetID = sourceFDLAsset.id

                    let sourceChartAsset = ProjectAsset(
                        projectID: projectID,
                        assetType: .chart,
                        name: "Scenario Pack Source Chart",
                        sourceTool: "viewer_scenario_pack",
                        referenceID: nil,
                        filePath: sourceChartPath,
                        payloadJSON: nil
                    )
                    try libraryStore.saveProjectAsset(sourceChartAsset)
                    sourceChartAssetID = sourceChartAsset.id
                }

                for (index, presetName) in presetNames.enumerated() {
                    guard let preset = TemplatePresets.scenarioContexts.first(where: { $0.name == presetName }) else {
                        continue
                    }
                    let resultDoc = try await applyTemplateWithBackendDocument(
                        pythonBridge: pythonBridge,
                        defaultCreator: defaultCreator,
                        template: preset.config
                    )

                    let scenarioDirName = String(format: "%02d_%@", index + 1, sanitizeFileName(presetName))
                    let scenarioURL = packURL.appendingPathComponent(scenarioDirName, isDirectory: true)
                    try FileManager.default.createDirectory(at: scenarioURL, withIntermediateDirectories: true)

                    if let outputJSON = FDLJSONSerializer.string(from: resultDoc) {
                        try outputJSON.write(
                            to: scenarioURL.appendingPathComponent("output.fdl.json"),
                            atomically: true,
                            encoding: .utf8
                        )
                    }

                    let templateDict = preset.config.toDict()
                    let templateData = try JSONSerialization.data(withJSONObject: templateDict, options: [.prettyPrinted, .sortedKeys])
                    let templateURL = scenarioURL.appendingPathComponent("template.json")
                    try templateData.write(to: templateURL)

                    if let chartData = try await renderOutputChartPNGData(resultDoc: resultDoc, pythonBridge: pythonBridge) {
                        try chartData.write(to: scenarioURL.appendingPathComponent("output_chart.png"))
                    }

                    if let projectID, let libraryStore {
                        let outputFDLURL = scenarioURL.appendingPathComponent("output.fdl.json")
                        let outputChartURL = scenarioURL.appendingPathComponent("output_chart.png")

                        let templateAsset = ProjectAsset(
                            projectID: projectID,
                            assetType: .template,
                            name: preset.config.label,
                            sourceTool: "viewer_scenario_pack",
                            referenceID: preset.config.id,
                            filePath: templateURL.path,
                            payloadJSON: String(data: templateData, encoding: .utf8)
                        )
                        try libraryStore.saveProjectAsset(templateAsset)

                        let outputFDLAsset = ProjectAsset(
                            projectID: projectID,
                            assetType: .fdl,
                            name: "\(preset.config.label) Output FDL",
                            sourceTool: "viewer_scenario_pack",
                            referenceID: nil,
                            filePath: outputFDLURL.path,
                            payloadJSON: nil
                        )
                        try libraryStore.saveProjectAsset(outputFDLAsset)

                        let outputChartAsset = ProjectAsset(
                            projectID: projectID,
                            assetType: .chart,
                            name: "\(preset.config.label) Output Chart",
                            sourceTool: "viewer_scenario_pack",
                            referenceID: nil,
                            filePath: outputChartURL.path,
                            payloadJSON: nil
                        )
                        try libraryStore.saveProjectAsset(outputChartAsset)

                        if let sourceFDLAssetID {
                            try libraryStore.linkAssets(ProjectAssetLink(
                                projectID: projectID,
                                fromAssetID: outputFDLAsset.id,
                                toAssetID: sourceFDLAssetID,
                                linkType: .derivedFrom
                            ))
                        }
                        try libraryStore.linkAssets(ProjectAssetLink(
                            projectID: projectID,
                            fromAssetID: outputFDLAsset.id,
                            toAssetID: templateAsset.id,
                            linkType: .usesTemplate
                        ))
                        try libraryStore.linkAssets(ProjectAssetLink(
                            projectID: projectID,
                            fromAssetID: outputChartAsset.id,
                            toAssetID: outputFDLAsset.id,
                            linkType: .inputOf
                        ))
                        if let sourceFDLAssetID, let sourceChartAssetID {
                            try libraryStore.linkAssets(ProjectAssetLink(
                                projectID: projectID,
                                fromAssetID: sourceChartAssetID,
                                toAssetID: sourceFDLAssetID,
                                linkType: .inputOf
                            ))
                        }
                    }

                    manifest.append([
                        "preset_name": presetName,
                        "template_id": preset.config.id,
                        "template_label": preset.config.label,
                        "directory": scenarioDirName,
                    ])
                }

                let manifestData = try JSONSerialization.data(
                    withJSONObject: [
                        "source_file": loadedFileName ?? "Source FDL",
                        "exported_at": Date().ISO8601Format(),
                        "scenarios": manifest,
                    ],
                    options: [.prettyPrinted, .sortedKeys]
                )
                try manifestData.write(to: packURL.appendingPathComponent("manifest.json"))

                if includeZip {
                    let zipURL = parentURL.appendingPathComponent("\(packName).zip")
                    try zipDirectory(packURL, to: zipURL)
                }
            } catch {
                errorMessage = "Scenario pack export failed: \(error.localizedDescription)"
            }
        }
    }

    private func renderSourceChartPNGData(pythonBridge: PythonBridge) async throws -> Data? {
        guard let sourceCanvas = selectedCanvas,
              let sourceFD = selectedFramingDecision ?? sourceCanvas.framingDecisions.first else {
            return nil
        }
        let title = loadedFileName ?? "Source"
        return try await renderChartPNGData(
            canvas: sourceCanvas,
            framingDecision: sourceFD,
            title: "Source - \(title)",
            pythonBridge: pythonBridge
        )
    }

    private func renderOutputChartPNGData(
        resultDoc: FDLDocument,
        pythonBridge: PythonBridge
    ) async throws -> Data? {
        guard let outContext = resultDoc.contexts.last,
              let outCanvas = outContext.canvases.first,
              let outFD = outCanvas.framingDecisions.first else {
            return nil
        }
        return try await renderChartPNGData(
            canvas: outCanvas,
            framingDecision: outFD,
            title: outCanvas.label ?? "Output",
            pythonBridge: pythonBridge
        )
    }

    private func renderChartPNGData(
        canvas: FDLCanvas,
        framingDecision: FDLFramingDecision,
        title: String,
        pythonBridge: PythonBridge
    ) async throws -> Data? {
        var frameline: [String: Any] = [
            "label": framingDecision.label ?? "Framing Decision",
            "width": Int(framingDecision.dimensions.width.rounded()),
            "height": Int(framingDecision.dimensions.height.rounded()),
            "h_align": "center",
            "v_align": "center",
            "style": "full_box",
        ]
        if let anchor = framingDecision.anchorPoint {
            frameline["anchor_x"] = anchor.x
            frameline["anchor_y"] = anchor.y
        }
        if let prot = framingDecision.protectionDimensions {
            frameline["protection_width"] = Int(prot.width.rounded())
            frameline["protection_height"] = Int(prot.height.rounded())
            if let protAnchor = framingDecision.protectionAnchorPoint {
                frameline["protection_anchor_x"] = protAnchor.x
                frameline["protection_anchor_y"] = protAnchor.y
            }
        }

        var params: [String: Any] = [
            "canvas_width": Int(canvas.dimensions.width.rounded()),
            "canvas_height": Int(canvas.dimensions.height.rounded()),
            "framelines": [frameline],
            "title": title,
            "show_labels": true,
            "layers": [
                "canvas": true,
                "effective": true,
                "protection": true,
                "framing": true,
            ],
        ]
        if let eff = canvas.effectiveDimensions {
            params["effective_width"] = Int(eff.width.rounded())
            params["effective_height"] = Int(eff.height.rounded())
        }
        params["anamorphic_squeeze"] = canvas.anamorphicSqueeze ?? 1.0

        let response = try await pythonBridge.callForResult("chart.generate_png", params: params)
        guard let b64 = response["png_base64"] as? String else { return nil }
        return Data(base64Encoded: b64)
    }

    private func sanitizeFileName(_ value: String) -> String {
        value
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func zipDirectory(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(
                domain: "FDLTool",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create zip archive"]
            )
        }
    }

    func outputContextCreator(defaultCreator: String) -> String {
        let base = "FDL Tool v1.0"
        if defaultCreator.isEmpty { return base }
        return "\(base) - \(defaultCreator)"
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
        ctxIndex: Int, canvasIndex: Int, fdIndex: Int,
        defaultCreator: String = ""
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

        let creatorString: String = {
            let base = "FDL Tool v1.0"
            if defaultCreator.isEmpty { return base }
            return "\(base) - \(defaultCreator)"
        }()

        let newCtx = FDLContext(
            id: UUID(),
            label: tmpl.label,
            contextCreator: creatorString,
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
        transformInfo = makeTransformInfo(
            sourceCanvas: srcCanvas,
            sourceFramingDecision: srcFD,
            outputDocument: outputDocument
        )
    }

    func makeTransformInfo(
        sourceCanvas: FDLCanvas?,
        sourceFramingDecision: FDLFramingDecision?,
        outputDocument: FDLDocument?
    ) -> TransformInfo {
        var info = TransformInfo(
            sourceCanvas: formatDims(
                sourceCanvas?.dimensions.width,
                sourceCanvas?.dimensions.height
            ),
            sourceFraming: formatDims(
                sourceFramingDecision?.dimensions.width,
                sourceFramingDecision?.dimensions.height
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

        return info
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
        loadedLibraryEntryID = nil
        loadedLibraryProjectID = nil

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
            normalizeSelectionForCurrentDocument()
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
                normalizeSelectionForCurrentDocument()
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
        loadedLibraryEntryID = nil
        loadedLibraryProjectID = nil

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
        normalizeSelectionForCurrentDocument()
        computedGeometry = computeGeometryLocally(from: doc)

        if let json = FDLJSONSerializer.string(from: doc) {
            rawJSON = json
        }
    }

    // MARK: - Load from Library Entry

    func loadFromEntry(
        _ entry: FDLEntry,
        pythonBridge: PythonBridge,
        libraryStore: LibraryStore? = nil
    ) {
        let filePath = LibraryStore.projectDirectoryURL(projectID: entry.projectID)
            .appendingPathComponent("\(entry.id).fdl.json")
        loadFromURL(filePath, pythonBridge: pythonBridge)
        loadedLibraryEntryID = entry.id
        loadedLibraryProjectID = entry.projectID

        if let libraryStore {
            loadAssociatedChartReferenceImage(entry: entry, libraryStore: libraryStore)
        }
    }

    private func loadAssociatedChartReferenceImage(entry: FDLEntry, libraryStore: LibraryStore) {
        let assets = (try? libraryStore.projectAssets(forProject: entry.projectID)) ?? []

        let referenceAsset = assets.first(where: {
            $0.assetType == .referenceImage && $0.referenceID == entry.id
        })
        let chartAsset = assets.first(where: {
            $0.assetType == .chart && $0.referenceID == entry.id
        })

        let preferredPath = referenceAsset?.filePath ?? chartAsset?.filePath
        guard let preferredPath, !preferredPath.isEmpty else { return }

        let url = URL(fileURLWithPath: preferredPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        loadReferenceImage(from: url)
    }

    private func normalizeSelectionForCurrentDocument() {
        guard let doc = loadedDocument else {
            selectedContextIndex = 0
            selectedCanvasIndex = 0
            selectedFramingIndex = nil
            return
        }
        guard !doc.contexts.isEmpty else {
            selectedContextIndex = 0
            selectedCanvasIndex = 0
            selectedFramingIndex = nil
            return
        }

        selectedContextIndex = min(max(selectedContextIndex, 0), doc.contexts.count - 1)
        let canvases = doc.contexts[selectedContextIndex].canvases
        guard !canvases.isEmpty else {
            selectedCanvasIndex = 0
            selectedFramingIndex = nil
            return
        }

        selectedCanvasIndex = min(max(selectedCanvasIndex, 0), canvases.count - 1)
        let framingDecisions = canvases[selectedCanvasIndex].framingDecisions
        guard !framingDecisions.isEmpty else {
            selectedFramingIndex = nil
            return
        }

        if let idx = selectedFramingIndex {
            selectedFramingIndex = min(max(idx, 0), framingDecisions.count - 1)
        } else {
            selectedFramingIndex = 0
        }
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
        loadedLibraryEntryID = nil
        loadedLibraryProjectID = nil

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

    // MARK: - Frameline Interop

    func refreshFramelineInterop(pythonBridge: PythonBridge) async {
        do {
            let statusResult = try await pythonBridge.callForResult("frameline.status")
            framelineStatus = mapFramelineStatus(from: statusResult)
            if framelineStatus.arriAvailable {
                try await refreshArriCatalog(pythonBridge: pythonBridge)
            }
            if framelineStatus.sonyAvailable {
                try await refreshSonyCatalog(pythonBridge: pythonBridge)
            }
        } catch {
            if error.localizedDescription.localizedCaseInsensitiveContains("python bridge not started") {
                // Startup race: view can appear before backend bridge is ready.
                return
            }
            errorMessage = "Failed to load frameline converter status: \(error.localizedDescription)"
        }
    }

    func exportCurrentFDLToArriXML(pythonBridge: PythonBridge) {
        guard !selectedArriCameraType.isEmpty, !selectedArriSensorMode.isEmpty else {
            errorMessage = "Choose ARRI camera and sensor mode."
            return
        }
        guard let sourceJSON = rawJSON else {
            errorMessage = "Load a source FDL before exporting XML."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "\(loadedFileName ?? "viewer").arri.xml"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        Task {
            do {
                let response = try await pythonBridge.callForResult("frameline.arri.to_xml", params: [
                    "fdl_json": sourceJSON,
                    "camera_type": selectedArriCameraType,
                    "sensor_mode": selectedArriSensorMode,
                    "output_path": destination.path,
                ])
                let validation = try await validateFDLJSONString(sourceJSON, pythonBridge: pythonBridge)
                framelineReport = buildConversionReport(
                    from: response,
                    title: "FDL -> ARRI XML",
                    summary: "Exported XML for \(selectedArriCameraType) / \(selectedArriSensorMode)",
                    validation: validation
                )
            } catch {
                errorMessage = "ARRI export failed: \(error.localizedDescription)"
            }
        }
    }

    func exportCurrentFDLToSonyXML(pythonBridge: PythonBridge) {
        guard !selectedSonyCameraType.isEmpty, !selectedSonyImagerMode.isEmpty else {
            errorMessage = "Choose Sony camera and imager mode."
            return
        }
        guard let sourceJSON = rawJSON else {
            errorMessage = "Load a source FDL before exporting XML."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "\(loadedFileName ?? "viewer").sony.xml"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        Task {
            do {
                let response = try await pythonBridge.callForResult("frameline.sony.to_xml", params: [
                    "fdl_json": sourceJSON,
                    "camera_type": selectedSonyCameraType,
                    "imager_mode": selectedSonyImagerMode,
                    "output_path": destination.path,
                ])
                let generated = (response["frame_lines_generated"] as? Int) ?? 1
                let validation = try await validateFDLJSONString(sourceJSON, pythonBridge: pythonBridge)
                framelineReport = buildConversionReport(
                    from: response,
                    title: "FDL -> Sony XML",
                    summary: "Exported \(generated) Sony frameline XML file(s) for \(selectedSonyCameraType) / \(selectedSonyImagerMode)",
                    validation: validation
                )
            } catch {
                errorMessage = "Sony export failed: \(error.localizedDescription)"
            }
        }
    }

    func importArriXMLAsSourceFDL(pythonBridge: PythonBridge) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }

        Task {
            do {
                let response = try await pythonBridge.callForResult("frameline.arri.to_fdl", params: [
                    "xml_path": source.path,
                    "context_label": "ARRI Frameline",
                ])
                try loadFramelineFDLResultAsSource(response, fileName: source.deletingPathExtension().lastPathComponent + ".fdl.json")
                let validation = try await validateCurrentLoadedDocument(pythonBridge: pythonBridge)
                framelineReport = buildConversionReport(
                    from: response,
                    title: "ARRI XML -> FDL",
                    summary: "Imported \(source.lastPathComponent) as source FDL.",
                    validation: validation
                )
            } catch {
                errorMessage = "ARRI import failed: \(error.localizedDescription)"
            }
        }
    }

    func importSonyXMLAsSourceFDL(pythonBridge: PythonBridge) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }

        Task {
            do {
                let response = try await pythonBridge.callForResult("frameline.sony.to_fdl", params: [
                    "xml_path": source.path,
                    "context_label": "Sony Frameline",
                ])
                try loadFramelineFDLResultAsSource(response, fileName: source.deletingPathExtension().lastPathComponent + ".fdl.json")
                let validation = try await validateCurrentLoadedDocument(pythonBridge: pythonBridge)
                framelineReport = buildConversionReport(
                    from: response,
                    title: "Sony XML -> FDL",
                    summary: "Imported \(source.lastPathComponent) as source FDL.",
                    validation: validation
                )
            } catch {
                errorMessage = "Sony import failed: \(error.localizedDescription)"
            }
        }
    }

    private func refreshArriCatalog(pythonBridge: PythonBridge) async throws {
        let result = try await pythonBridge.callForResult("frameline.arri.list_cameras")
        arriCameras = parseFramelineCameras(result["cameras"])
        if selectedArriCameraType.isEmpty, let first = arriCameras.first {
            selectedArriCameraType = first.cameraType
            selectedArriSensorMode = first.modes.first?.name ?? ""
        }
        if !selectedArriCameraType.isEmpty, selectedArriSensorMode.isEmpty {
            selectedArriSensorMode = arriCameras.first(where: { $0.cameraType == selectedArriCameraType })?.modes.first?.name ?? ""
        }
    }

    private func refreshSonyCatalog(pythonBridge: PythonBridge) async throws {
        let result = try await pythonBridge.callForResult("frameline.sony.list_cameras")
        sonyCameras = parseFramelineCameras(result["cameras"])
        if selectedSonyCameraType.isEmpty, let first = sonyCameras.first {
            selectedSonyCameraType = first.cameraType
            selectedSonyImagerMode = first.modes.first?.name ?? ""
        }
        if !selectedSonyCameraType.isEmpty, selectedSonyImagerMode.isEmpty {
            selectedSonyImagerMode = sonyCameras.first(where: { $0.cameraType == selectedSonyCameraType })?.modes.first?.name ?? ""
        }
    }

    private func mapFramelineStatus(from dict: [String: Any]) -> FramelineInteropStatus {
        var status = FramelineInteropStatus()
        if let arri = dict["arri"] as? [String: Any] {
            status.arriAvailable = (arri["available"] as? Bool) ?? false
            status.arriSource = arri["source"] as? String
        }
        if let sony = dict["sony"] as? [String: Any] {
            status.sonyAvailable = (sony["available"] as? Bool) ?? false
            status.sonySource = sony["source"] as? String
        }
        return status
    }

    private func parseFramelineCameras(_ raw: Any?) -> [FramelineCameraOption] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let cameraType = row["camera_type"] as? String else { return nil }
            let modesRaw = row["sensor_modes"] as? [[String: Any]] ?? []
            let modes = modesRaw.compactMap { mode -> FramelineModeOption? in
                guard let name = mode["name"] as? String else { return nil }
                return FramelineModeOption(
                    name: name,
                    hres: mode["hres"] as? Int,
                    vres: mode["vres"] as? Int,
                    aspect: mode["aspect"] as? String
                )
            }
            return FramelineCameraOption(cameraType: cameraType, modes: modes)
        }
    }

    private func loadFramelineFDLResultAsSource(_ response: [String: Any], fileName: String) throws {
        guard let fdlDict = response["fdl"] as? [String: Any] else {
            throw NSError(
                domain: "FDLTool",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey: "Frameline conversion did not return FDL JSON."]
            )
        }
        let data = try JSONSerialization.data(withJSONObject: fdlDict)
        let doc = try JSONDecoder().decode(FDLDocument.self, from: data)
        loadDocument(doc, fileName: fileName)
    }

    private func validateCurrentLoadedDocument(pythonBridge: PythonBridge) async throws -> ValidationResult {
        guard let json = rawJSON else {
            return ValidationResult(valid: true, errors: [], warnings: [])
        }
        return try await validateFDLJSONString(json, pythonBridge: pythonBridge)
    }

    private func validateFDLJSONString(_ json: String, pythonBridge: PythonBridge) async throws -> ValidationResult {
        let response = try await pythonBridge.callForResult("fdl.validate", params: [
            "json_string": json,
        ])
        let data = try JSONSerialization.data(withJSONObject: response)
        return try JSONDecoder().decode(ValidationResult.self, from: data)
    }

    func exportFramelineReportJSON() {
        guard let report = framelineReport else {
            errorMessage = "No conversion report available to export."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "frameline-conversion-report.json"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let data = try JSONEncoder().encode(report)
            try data.write(to: destination)
        } catch {
            errorMessage = "Failed to export report: \(error.localizedDescription)"
        }
    }

    func saveFramelineReportToProject(projectID: String, libraryStore: LibraryStore) {
        guard let report = framelineReport else {
            errorMessage = "No conversion report available to save."
            return
        }
        do {
            let reportData = try JSONEncoder().encode(report)
            let payload = String(data: reportData, encoding: .utf8)
            let reportAsset = ProjectAsset(
                projectID: projectID,
                assetType: .report,
                name: report.title,
                sourceTool: "frameline_interop",
                referenceID: loadedFileName,
                filePath: nil,
                payloadJSON: payload
            )
            try libraryStore.saveProjectAsset(reportAsset)
            if let loadedFileName {
                let assets = try libraryStore.projectAssets(forProject: projectID, ofType: .fdl)
                if let sourceAsset = assets.first(where: { $0.name == loadedFileName || $0.referenceID == loadedFileName }) {
                    try libraryStore.linkAssets(ProjectAssetLink(
                        projectID: projectID,
                        fromAssetID: reportAsset.id,
                        toAssetID: sourceAsset.id,
                        linkType: .inputOf
                    ))
                }
            }
        } catch {
            errorMessage = "Failed to save report to project: \(error.localizedDescription)"
        }
    }

    private func buildConversionReport(
        from response: [String: Any],
        title: String,
        summary: String,
        validation: ValidationResult
    ) -> FramelineConversionReport {
        let report = response["report"] as? [String: Any]
        let mappedFields = report?["mapped_fields"] as? [String] ?? [
            "canvas.dimensions",
            "framing_decision.dimensions",
            "framing_decision.anchor_point",
        ]
        let warnings = report?["warnings"] as? [String] ?? []
        let droppedFields = report?["dropped_fields"] as? [String] ?? []
        let lossy = (report?["lossy"] as? Bool) ?? (!warnings.isEmpty || !droppedFields.isEmpty)
        let detailsRaw = report?["mapping_details"] as? [[String: Any]] ?? []
        let details = detailsRaw.map { row in
            FramelineMappingDetail(
                sourceField: row["source_field"] as? String ?? "unknown",
                sourceValue: row["source_value"] as? String,
                targetField: row["target_field"] as? String ?? "unknown",
                targetValue: row["target_value"] as? String,
                note: row["note"] as? String,
                status: row["status"] as? String
            )
        }
        .sorted {
            ($0.status ?? "mapped", $0.sourceField, $0.targetField) <
            ($1.status ?? "mapped", $1.sourceField, $1.targetField)
        }
        return FramelineConversionReport(
            title: title,
            summary: summary,
            mappedFields: mappedFields,
            mappingDetails: details,
            droppedFields: droppedFields,
            warnings: warnings,
            lossy: lossy,
            validationErrorCount: validation.errors.count,
            validationWarningCount: validation.warnings.count
        )
    }
}
