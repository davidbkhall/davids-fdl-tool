import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    @Published var fdlEntries: [FDLEntry] = []
    @Published var selectedEntry: FDLEntry?
    @Published var parsedDocument: FDLDocument?
    @Published var validationResult: ValidationResult?
    @Published var canvasTemplates: [CanvasTemplate] = []
    @Published var projectAssets: [ProjectAsset] = []
    @Published var projectAssetLinks: [ProjectAssetLink] = []
    @Published var projectCameraModeAssignments: [ProjectCameraModeAssignment] = []

    // Import state
    @Published var showImportSheet = false
    @Published var showProjectCreation = false
    @Published var showExportSheet = false
    @Published var importJSONText = ""
    @Published var importValidation: ValidationResult?
    @Published var importMode: InputMode = .importJSON
    @Published var isValidating = false
    @Published var isImporting = false

    // Manual entry state
    @Published var manualName = ""
    @Published var manualDescription = ""
    @Published var manualCanvasWidth: Double = 3840
    @Published var manualCanvasHeight: Double = 2160
    @Published var manualEffectiveWidth: Double = 3840
    @Published var manualEffectiveHeight: Double = 2160
    @Published var manualEffectiveAnchorX: Double = 0
    @Published var manualEffectiveAnchorY: Double = 0
    @Published var manualPhotositeWidth: Double = 0
    @Published var manualPhotositeHeight: Double = 0
    @Published var manualPhotositeAnchorX: Double = 0
    @Published var manualPhotositeAnchorY: Double = 0

    // Error state
    @Published var errorMessage: String?
    @Published var framelineStatus = FramelineInteropStatus()
    @Published var framelineReport: FramelineConversionReport?
    @Published var arriCameras: [FramelineCameraOption] = []
    @Published var sonyCameras: [FramelineCameraOption] = []
    @Published var selectedArriCameraType = ""
    @Published var selectedArriSensorMode = ""
    @Published var selectedSonyCameraType = ""
    @Published var selectedSonyImagerMode = ""

    let libraryStore: LibraryStore
    private let pythonBridge: PythonBridge

    init(libraryStore: LibraryStore, pythonBridge: PythonBridge) {
        self.libraryStore = libraryStore
        self.pythonBridge = pythonBridge
        self.projects = libraryStore.projects
        refreshCanvasTemplates()
        Task { await refreshFramelineInterop() }
    }

    // MARK: - Project Operations

    func refreshProjects() {
        projects = libraryStore.projects
    }

    func refreshCanvasTemplates() {
        canvasTemplates = (try? libraryStore.allCanvasTemplates()) ?? []
    }

    func createProject(name: String, description: String?) {
        do {
            let project = try libraryStore.createProject(name: name, description: description)
            projects = libraryStore.projects
            selectedProject = project
            loadEntries()
        } catch {
            errorMessage = "Failed to create project: \(error.localizedDescription)"
        }
    }

    func deleteProject(_ project: Project) {
        do {
            try libraryStore.deleteProject(id: project.id)
            projects = libraryStore.projects
            if selectedProject?.id == project.id {
                selectedProject = nil
                fdlEntries = []
                selectedEntry = nil
                parsedDocument = nil
                validationResult = nil
            }
        } catch {
            errorMessage = "Failed to delete project: \(error.localizedDescription)"
        }
    }

    func selectProject(_ project: Project) {
        selectedProject = project
        selectedEntry = nil
        parsedDocument = nil
        validationResult = nil
        loadEntries()
        loadProjectGraph()
    }

    // MARK: - FDL Entry Operations

    func loadEntries() {
        guard let project = selectedProject else {
            fdlEntries = []
            projectAssets = []
            projectAssetLinks = []
            projectCameraModeAssignments = []
            return
        }
        do {
            fdlEntries = try libraryStore.fdlEntries(forProject: project.id)
            loadProjectGraph()
        } catch {
            errorMessage = "Failed to load entries: \(error.localizedDescription)"
        }
    }

    func loadProjectGraph() {
        guard let project = selectedProject else {
            projectAssets = []
            projectAssetLinks = []
            projectCameraModeAssignments = []
            return
        }
        do {
            projectAssets = try libraryStore.projectAssets(forProject: project.id)
            projectAssetLinks = try libraryStore.assetLinks(forProject: project.id)
            projectCameraModeAssignments = try libraryStore.cameraModeAssignments(forProject: project.id)
        } catch {
            errorMessage = "Failed to load project graph: \(error.localizedDescription)"
        }
    }

    func selectEntry(_ entry: FDLEntry) {
        selectedEntry = entry
        parsedDocument = nil
        validationResult = nil
        Task {
            await loadAndValidateEntry(entry)
        }
    }

    func deleteEntry(_ entry: FDLEntry) {
        do {
            try libraryStore.deleteFDLEntry(id: entry.id, projectID: entry.projectID)
            loadEntries()
            if selectedEntry?.id == entry.id {
                selectedEntry = nil
                parsedDocument = nil
                validationResult = nil
            }
        } catch {
            errorMessage = "Failed to delete entry: \(error.localizedDescription)"
        }
    }

    // MARK: - FDL Import (JSON)

    func validateImportJSON() {
        guard !importJSONText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isValidating = true
        Task {
            do {
                let response = try await pythonBridge.callForResult("fdl.validate", params: [
                    "json_string": importJSONText,
                ])
                let data = try JSONSerialization.data(withJSONObject: response)
                importValidation = try JSONDecoder().decode(ValidationResult.self, from: data)
            } catch {
                importValidation = ValidationResult(
                    valid: false,
                    errors: [ValidationMessage(path: "", message: error.localizedDescription, severity: .error)],
                    warnings: []
                )
            }
            isValidating = false
        }
    }

    func importFDLFromJSON() {
        guard let project = selectedProject else {
            errorMessage = "Select a project first"
            return
        }
        guard let jsonData = importJSONText.data(using: .utf8) else { return }

        isImporting = true
        Task {
            do {
                // Parse to get UUID and structure
                let response = try await pythonBridge.callForResult("fdl.parse", params: [
                    "json_string": importJSONText,
                ])

                let fdlDict = response["fdl"] as? [String: Any] ?? [:]
                let fdlUUID = fdlDict["uuid"] as? String
                    ?? (fdlDict["header"] as? [String: Any])?["uuid"] as? String
                    ?? UUID().uuidString

                let header = fdlDict["header"] as? [String: Any] ?? [:]
                let entryName = header["description"] as? String ?? "Imported FDL"

                let entry = FDLEntry(
                    projectID: project.id,
                    fdlUUID: fdlUUID,
                    name: entryName,
                    filePath: "", // Will be set by LibraryStore
                    sourceTool: "import",
                    tags: ["imported"]
                )

                try libraryStore.addFDLEntry(entry, jsonData: jsonData)
                loadEntries()

                // Reset import state
                importJSONText = ""
                importValidation = nil
                showImportSheet = false
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }
            isImporting = false
        }
    }

    // MARK: - FDL Manual Entry

    func importFDLFromManualEntry() {
        guard let project = selectedProject else {
            errorMessage = "Select a project first"
            return
        }

        isImporting = true
        Task {
            do {
                var canvasDef: [String: Any] = [
                    "label": "\(Int(manualCanvasWidth))x\(Int(manualCanvasHeight))",
                    "dimensions": ["width": manualCanvasWidth, "height": manualCanvasHeight],
                ]

                if manualEffectiveWidth > 0 && manualEffectiveHeight > 0 {
                    canvasDef["effective_dimensions"] = [
                        "width": manualEffectiveWidth,
                        "height": manualEffectiveHeight,
                    ]
                    canvasDef["effective_anchor"] = [
                        "x": manualEffectiveAnchorX,
                        "y": manualEffectiveAnchorY,
                    ]
                }

                if manualPhotositeWidth > 0 && manualPhotositeHeight > 0 {
                    canvasDef["photosite"] = [
                        "width": manualPhotositeWidth,
                        "height": manualPhotositeHeight,
                    ]
                    canvasDef["photosite_anchor"] = [
                        "x": manualPhotositeAnchorX,
                        "y": manualPhotositeAnchorY,
                    ]
                }

                let params: [String: Any] = [
                    "header": [
                        "fdl_creator": "FDL Tool",
                        "description": manualDescription.isEmpty ? manualName : manualDescription,
                    ],
                    "contexts": [[
                        "label": manualName.isEmpty ? "Manual Entry" : manualName,
                        "canvases": [canvasDef],
                    ]],
                ]

                let response = try await pythonBridge.callForResult("fdl.create", params: params)
                let fdlDict = response["fdl"] as? [String: Any] ?? [:]
                let fdlUUID = fdlDict["uuid"] as? String ?? UUID().uuidString

                let jsonData = try JSONSerialization.data(
                    withJSONObject: fdlDict,
                    options: [.prettyPrinted, .sortedKeys]
                )

                let entry = FDLEntry(
                    projectID: project.id,
                    fdlUUID: fdlUUID,
                    name: manualName.isEmpty ? "Manual FDL" : manualName,
                    filePath: "",
                    sourceTool: "manual",
                    tags: ["manual"]
                )

                try libraryStore.addFDLEntry(entry, jsonData: jsonData)
                loadEntries()

                // Reset
                resetManualEntry()
                showImportSheet = false
            } catch {
                errorMessage = "Manual entry failed: \(error.localizedDescription)"
            }
            isImporting = false
        }
    }

    func resetManualEntry() {
        manualName = ""
        manualDescription = ""
        manualCanvasWidth = 3840
        manualCanvasHeight = 2160
        manualEffectiveWidth = 3840
        manualEffectiveHeight = 2160
        manualEffectiveAnchorX = 0
        manualEffectiveAnchorY = 0
        manualPhotositeWidth = 0
        manualPhotositeHeight = 0
        manualPhotositeAnchorX = 0
        manualPhotositeAnchorY = 0
    }

    // MARK: - Load & Validate Entry

    func loadAndValidateEntry(_ entry: FDLEntry) async {
        let filePath = LibraryStore.projectDirectoryURL(projectID: entry.projectID)
            .appendingPathComponent("\(entry.id).fdl.json").path

        do {
            // Parse
            let parseResponse = try await pythonBridge.callForResult("fdl.parse", params: [
                "path": filePath,
            ])
            if let fdlDict = parseResponse["fdl"] as? [String: Any] {
                let data = try JSONSerialization.data(withJSONObject: fdlDict)
                parsedDocument = try JSONDecoder().decode(FDLDocument.self, from: data)
            }

            // Validate
            let valResponse = try await pythonBridge.callForResult("fdl.validate", params: [
                "path": filePath,
            ])
            let valData = try JSONSerialization.data(withJSONObject: valResponse)
            validationResult = try JSONDecoder().decode(ValidationResult.self, from: valData)
        } catch {
            errorMessage = "Failed to load FDL: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    func exportSelectedFDL() {
        guard let entry = selectedEntry, let project = selectedProject else { return }

        let filePath = LibraryStore.projectDirectoryURL(projectID: project.id)
            .appendingPathComponent("\(entry.id).fdl.json")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(entry.name).fdl.json"

        if panel.runModal() == .OK, let dest = panel.url {
            do {
                try FileManager.default.copyItem(at: filePath, to: dest)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    func exportProject() {
        guard let project = selectedProject else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .data]
        panel.nameFieldStringValue = "\(project.name).zip"

        if panel.runModal() == .OK, let dest = panel.url {
            do {
                let projectDir = LibraryStore.projectDirectoryURL(projectID: project.id)
                try zipDirectory(projectDir, to: dest)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func zipDirectory(_ source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "FDLTool", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "zip failed with exit code \(process.terminationStatus)",
            ])
        }
    }

    // MARK: - Frameline Interop

    func refreshFramelineInterop() async {
        do {
            let statusResult = try await pythonBridge.callForResult("frameline.status")
            framelineStatus = mapFramelineStatus(from: statusResult)
            if framelineStatus.arriAvailable { try await refreshArriCatalog() }
            if framelineStatus.sonyAvailable { try await refreshSonyCatalog() }
        } catch {
            if error.localizedDescription.localizedCaseInsensitiveContains("python bridge not started") {
                // Startup race: library can initialize before backend bridge is ready.
                return
            }
            errorMessage = "Failed to load frameline converter status: \(error.localizedDescription)"
        }
    }

    func exportSelectedEntryToArriXML() {
        guard !selectedArriCameraType.isEmpty, !selectedArriSensorMode.isEmpty else {
            errorMessage = "Choose ARRI camera and sensor mode."
            return
        }
        guard let entry = selectedEntry, let project = selectedProject else {
            errorMessage = "Select an FDL entry first."
            return
        }
        let sourceURL = LibraryStore.projectDirectoryURL(projectID: project.id)
            .appendingPathComponent("\(entry.id).fdl.json")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "\(entry.name).arri.xml"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        Task {
            do {
                let response = try await pythonBridge.callForResult("frameline.arri.to_xml", params: [
                    "fdl_path": sourceURL.path,
                    "camera_type": selectedArriCameraType,
                    "sensor_mode": selectedArriSensorMode,
                    "output_path": destination.path,
                ])
                let validation = try await validateEntryFile(sourceURL.path)
                framelineReport = buildConversionReport(
                    from: response,
                    title: "FDL -> ARRI XML",
                    summary: "Exported \(entry.name) for \(selectedArriCameraType) / \(selectedArriSensorMode).",
                    validation: validation
                )
            } catch {
                errorMessage = "ARRI export failed: \(error.localizedDescription)"
            }
        }
    }

    func exportSelectedEntryToSonyXML() {
        guard !selectedSonyCameraType.isEmpty, !selectedSonyImagerMode.isEmpty else {
            errorMessage = "Choose Sony camera and imager mode."
            return
        }
        guard let entry = selectedEntry, let project = selectedProject else {
            errorMessage = "Select an FDL entry first."
            return
        }
        let sourceURL = LibraryStore.projectDirectoryURL(projectID: project.id)
            .appendingPathComponent("\(entry.id).fdl.json")

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "\(entry.name).sony.xml"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        Task {
            do {
                let response = try await pythonBridge.callForResult("frameline.sony.to_xml", params: [
                    "fdl_path": sourceURL.path,
                    "camera_type": selectedSonyCameraType,
                    "imager_mode": selectedSonyImagerMode,
                    "output_path": destination.path,
                ])
                let generated = (response["frame_lines_generated"] as? Int) ?? 1
                let validation = try await validateEntryFile(sourceURL.path)
                framelineReport = buildConversionReport(
                    from: response,
                    title: "FDL -> Sony XML",
                    summary: "Exported \(generated) XML file(s) for \(selectedSonyCameraType) / \(selectedSonyImagerMode).",
                    validation: validation
                )
            } catch {
                errorMessage = "Sony export failed: \(error.localizedDescription)"
            }
        }
    }

    func importArriXMLToSelectedProject() {
        guard let project = selectedProject else {
            errorMessage = "Select a project first."
            return
        }
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
                try await saveConvertedFDLToProject(response: response, project: project, sourceURL: source, sourceTool: "frameline_arri")
            } catch {
                errorMessage = "ARRI import failed: \(error.localizedDescription)"
            }
        }
    }

    func importSonyXMLToSelectedProject() {
        guard let project = selectedProject else {
            errorMessage = "Select a project first."
            return
        }
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
                try await saveConvertedFDLToProject(response: response, project: project, sourceURL: source, sourceTool: "frameline_sony")
            } catch {
                errorMessage = "Sony import failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveConvertedFDLToProject(
        response: [String: Any],
        project: Project,
        sourceURL: URL,
        sourceTool: String
    ) async throws {
        guard let fdlDict = response["fdl"] as? [String: Any] else {
            throw NSError(
                domain: "FDLTool",
                code: 200,
                userInfo: [NSLocalizedDescriptionKey: "Frameline conversion did not return FDL JSON."]
            )
        }

        let data = try JSONSerialization.data(withJSONObject: fdlDict, options: [.prettyPrinted, .sortedKeys])
        let fdlUUID = fdlDict["uuid"] as? String
            ?? (fdlDict["header"] as? [String: Any])?["uuid"] as? String
            ?? UUID().uuidString
        let entryName = sourceURL.deletingPathExtension().lastPathComponent + " (Converted)"
        let entry = FDLEntry(
            projectID: project.id,
            fdlUUID: fdlUUID,
            name: entryName,
            filePath: "",
            sourceTool: sourceTool,
            tags: ["converted", "frameline"]
        )
        try libraryStore.addFDLEntry(entry, jsonData: data)
        loadEntries()
        selectEntry(entry)
        let savedPath = LibraryStore.projectDirectoryURL(projectID: project.id)
            .appendingPathComponent("\(entry.id).fdl.json").path
        let validation = try await validateEntryFile(savedPath)
        framelineReport = buildConversionReport(
            from: response,
            title: sourceTool == "frameline_arri" ? "ARRI XML -> FDL" : "Sony XML -> FDL",
            summary: "Imported \(sourceURL.lastPathComponent) into project \(project.name).",
            validation: validation
        )
    }

    private func refreshArriCatalog() async throws {
        let result = try await pythonBridge.callForResult("frameline.arri.list_cameras")
        arriCameras = parseFramelineCameras(result["cameras"])
        if selectedArriCameraType.isEmpty, let first = arriCameras.first {
            selectedArriCameraType = first.cameraType
            selectedArriSensorMode = first.modes.first?.name ?? ""
        }
    }

    private func refreshSonyCatalog() async throws {
        let result = try await pythonBridge.callForResult("frameline.sony.list_cameras")
        sonyCameras = parseFramelineCameras(result["cameras"])
        if selectedSonyCameraType.isEmpty, let first = sonyCameras.first {
            selectedSonyCameraType = first.cameraType
            selectedSonyImagerMode = first.modes.first?.name ?? ""
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

    private func validateEntryFile(_ path: String) async throws -> ValidationResult {
        let response = try await pythonBridge.callForResult("fdl.validate", params: [
            "path": path,
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

    func saveFramelineReportToSelectedProject() {
        guard let report = framelineReport, let project = selectedProject else {
            errorMessage = "Select a project and generate a report first."
            return
        }
        do {
            let reportData = try JSONEncoder().encode(report)
            let payload = String(data: reportData, encoding: .utf8)
            let reportAsset = ProjectAsset(
                projectID: project.id,
                assetType: .report,
                name: report.title,
                sourceTool: "frameline_interop",
                referenceID: selectedEntry?.id,
                filePath: nil,
                payloadJSON: payload
            )
            try libraryStore.saveProjectAsset(reportAsset)
            if let entryID = selectedEntry?.id {
                let sourceAssetID = "asset-fdl-\(entryID)"
                try libraryStore.linkAssets(ProjectAssetLink(
                    projectID: project.id,
                    fromAssetID: reportAsset.id,
                    toAssetID: sourceAssetID,
                    linkType: .inputOf
                ))
            }
            loadProjectGraph()
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
