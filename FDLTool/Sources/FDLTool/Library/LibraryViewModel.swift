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

    private let libraryStore: LibraryStore
    private let pythonBridge: PythonBridge

    init(libraryStore: LibraryStore, pythonBridge: PythonBridge) {
        self.libraryStore = libraryStore
        self.pythonBridge = pythonBridge
        self.projects = libraryStore.projects
    }

    // MARK: - Project Operations

    func refreshProjects() {
        projects = libraryStore.projects
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
    }

    // MARK: - FDL Entry Operations

    func loadEntries() {
        guard let project = selectedProject else {
            fdlEntries = []
            return
        }
        do {
            fdlEntries = try libraryStore.fdlEntries(forProject: project.id)
        } catch {
            errorMessage = "Failed to load entries: \(error.localizedDescription)"
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
}
