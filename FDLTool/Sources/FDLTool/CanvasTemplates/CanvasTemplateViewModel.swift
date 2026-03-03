import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class CanvasTemplateViewModel: ObservableObject {
    @Published var templates: [CanvasTemplate] = []
    @Published var selectedTemplate: CanvasTemplate?

    // Editor state
    @Published var showEditor = false
    @Published var showImportSheet = false
    @Published var editingTemplate: CanvasTemplate?
    @Published var editorName = ""
    @Published var editorDescription = ""
    @Published var editorPipeline: [PipelineStep] = []

    // ASC Template editor state
    @Published var showASCEditor = false
    @Published var ascEditorConfig = CanvasTemplateConfig()

    // Import state
    @Published var importJSONText = ""
    @Published var importValidation: ValidationResult?
    @Published var isValidating = false

    // Preview state
    @Published var showPreview = false
    @Published var previewFDLJSON = ""
    @Published var previewSteps: [PreviewStep] = []

    // Error state
    @Published var errorMessage: String?

    private let libraryStore: LibraryStore
    private let pythonBridge: PythonBridge

    init(libraryStore: LibraryStore, pythonBridge: PythonBridge) {
        self.libraryStore = libraryStore
        self.pythonBridge = pythonBridge
        loadTemplates()
    }

    // MARK: - CRUD

    func loadTemplates() {
        do {
            templates = try libraryStore.allCanvasTemplates()
        } catch {
            errorMessage = "Failed to load templates: \(error.localizedDescription)"
        }
    }

    func saveTemplate() {
        let pipelineJSON = pipelineToJSON()
        let templateJSON: String
        do {
            let dict: [String: Any] = [
                "name": editorName,
                "description": editorDescription,
                "pipeline": pipelineJSON,
            ]
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            templateJSON = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            errorMessage = "Failed to serialize template: \(error.localizedDescription)"
            return
        }

        do {
            if let existing = editingTemplate {
                let updated = CanvasTemplate(
                    id: existing.id,
                    name: editorName,
                    description: editorDescription.isEmpty ? nil : editorDescription,
                    templateJSON: templateJSON,
                    source: existing.source,
                    createdAt: existing.createdAt,
                    updatedAt: Date()
                )
                try libraryStore.saveCanvasTemplate(updated)
            } else {
                let template = CanvasTemplate(
                    name: editorName,
                    description: editorDescription.isEmpty ? nil : editorDescription,
                    templateJSON: templateJSON,
                    source: "manual"
                )
                try libraryStore.saveCanvasTemplate(template)
            }
            loadTemplates()
            showEditor = false
            resetEditor()
        } catch {
            errorMessage = "Failed to save template: \(error.localizedDescription)"
        }
    }

    func deleteTemplate(_ template: CanvasTemplate) {
        do {
            try libraryStore.deleteCanvasTemplate(id: template.id)
            loadTemplates()
            if selectedTemplate?.id == template.id {
                selectedTemplate = nil
            }
        } catch {
            errorMessage = "Failed to delete template: \(error.localizedDescription)"
        }
    }

    func beginEditing(_ template: CanvasTemplate) {
        editingTemplate = template
        editorName = template.name
        editorDescription = template.description ?? ""
        editorPipeline = parseTemplateJSON(template.templateJSON)
        showEditor = true
    }

    func beginNewTemplate() {
        editingTemplate = nil
        resetEditor()
        showEditor = true
    }

    func beginNewASCTemplate(config: CanvasTemplateConfig) {
        editingTemplate = nil
        ascEditorConfig = config
        showASCEditor = true
    }

    func beginEditingASC(_ template: CanvasTemplate) {
        editingTemplate = template
        guard let data = template.templateJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(
                  with: data
              ) as? [String: Any]
        else {
            ascEditorConfig = CanvasTemplateConfig(label: template.name)
            showASCEditor = true
            return
        }
        var config = CanvasTemplateConfig()
        if let id = dict["id"] as? String { config.id = id }
        if let label = dict["label"] as? String {
            config.label = label
        } else {
            config.label = template.name
        }
        if let t = dict["target_dimensions"] as? [String: Any] {
            if let w = t["width"] as? Int { config.targetWidth = w }
            if let h = t["height"] as? Int { config.targetHeight = h }
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
        if let mx = dict["maximum_dimensions"] as? [String: Any] {
            config.maximumWidth = mx["width"] as? Int
            config.maximumHeight = mx["height"] as? Int
        }
        if let r = dict["round"] as? [String: Any] {
            if let re = r["even"] as? String { config.roundEven = re }
            if let rm = r["mode"] as? String { config.roundMode = rm }
        }
        ascEditorConfig = config
        showASCEditor = true
    }

    func saveASCTemplate() {
        let dict = ascEditorConfig.toDict()
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
        ),
              let jsonStr = String(data: data, encoding: .utf8)
        else {
            errorMessage = "Failed to serialize template"
            return
        }
        let template: CanvasTemplate
        if let existing = editingTemplate {
            template = CanvasTemplate(
                id: existing.id,
                name: ascEditorConfig.label,
                description: existing.description,
                templateJSON: jsonStr,
                source: existing.source,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
        } else {
            template = CanvasTemplate(
                name: ascEditorConfig.label,
                description: nil,
                templateJSON: jsonStr,
                source: "manual"
            )
        }
        do {
            try libraryStore.saveCanvasTemplate(template)
            loadTemplates()
            showASCEditor = false
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func resetEditor() {
        editorName = ""
        editorDescription = ""
        editorPipeline = []
        editingTemplate = nil
    }

    // MARK: - Import

    func validateImportJSON() {
        guard !importJSONText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isValidating = true
        Task {
            do {
                let response = try await pythonBridge.callForResult("template.validate", params: [
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

    func importTemplate() {
        guard !importJSONText.isEmpty else { return }
        do {
            // Extract name/description from the JSON if present
            if let data = importJSONText.data(using: .utf8),
               let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let name = dict["name"] as? String ?? "Imported Template"
                let desc = dict["description"] as? String

                let template = CanvasTemplate(
                    name: name,
                    description: desc,
                    templateJSON: importJSONText,
                    source: "import"
                )
                try libraryStore.saveCanvasTemplate(template)
                loadTemplates()
                showImportSheet = false
                importJSONText = ""
                importValidation = nil
            }
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Preview

    func previewTemplate(_ template: CanvasTemplate, withFDLJSON fdlJSON: String) {
        Task {
            do {
                let response = try await pythonBridge.callForResult("template.preview", params: [
                    "template_json": template.templateJSON,
                    "fdl_json": fdlJSON,
                ])

                if let steps = response["steps"] as? [[String: Any]] {
                    previewSteps = steps.map { step in
                        PreviewStep(
                            stepName: step["step"] as? String ?? "unknown",
                            stepType: step["type"] as? String ?? "unknown",
                            inputWidth: step["input_width"] as? Double,
                            inputHeight: step["input_height"] as? Double,
                            outputWidth: step["output_width"] as? Double ?? step["width"] as? Double ?? 0,
                            outputHeight: step["output_height"] as? Double ?? step["height"] as? Double ?? 0
                        )
                    }
                }
                showPreview = true
            } catch {
                errorMessage = "Preview failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Export

    func exportTemplate(_ template: CanvasTemplate) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(template.name).json"

        if panel.runModal() == .OK, let dest = panel.url {
            do {
                try template.templateJSON.data(using: .utf8)?.write(to: dest)
            } catch {
                errorMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Project Association

    func assignToProject(_ template: CanvasTemplate, projectID: String, role: String? = nil) {
        do {
            try libraryStore.assignTemplate(templateID: template.id, toProject: projectID, role: role)
        } catch {
            errorMessage = "Failed to assign template: \(error.localizedDescription)"
        }
    }

    // MARK: - Pipeline Helpers

    func addPipelineStep(_ type: PipelineStepType) {
        editorPipeline.append(PipelineStep(type: type))
    }

    func removePipelineStep(at index: Int) {
        guard editorPipeline.indices.contains(index) else { return }
        editorPipeline.remove(at: index)
    }

    func movePipelineStep(from source: IndexSet, to destination: Int) {
        editorPipeline.move(fromOffsets: source, toOffset: destination)
    }

    private func pipelineToJSON() -> [[String: Any]] {
        editorPipeline.map { step in
            var dict: [String: Any] = ["type": step.type.rawValue]
            switch step.type {
            case .normalize:
                break
            case .scale:
                dict["scale_x"] = step.scaleX
                dict["scale_y"] = step.scaleY
            case .round:
                dict["strategy"] = step.roundStrategy
            case .offset:
                dict["offset_x"] = step.offsetX
                dict["offset_y"] = step.offsetY
            case .crop:
                dict["width"] = step.cropWidth
                dict["height"] = step.cropHeight
            }
            return dict
        }
    }

    private func parseTemplateJSON(_ json: String) -> [PipelineStep] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pipeline = dict["pipeline"] as? [[String: Any]] else {
            return []
        }

        return pipeline.compactMap { stepDict in
            guard let typeStr = stepDict["type"] as? String,
                  let type = PipelineStepType(rawValue: typeStr) else {
                return nil
            }
            var step = PipelineStep(type: type)
            switch type {
            case .normalize:
                break
            case .scale:
                step.scaleX = stepDict["scale_x"] as? Double ?? stepDict["scale"] as? Double ?? 1.0
                step.scaleY = stepDict["scale_y"] as? Double ?? stepDict["scale"] as? Double ?? 1.0
            case .round:
                step.roundStrategy = stepDict["strategy"] as? String ?? "nearest"
            case .offset:
                step.offsetX = stepDict["offset_x"] as? Double ?? 0
                step.offsetY = stepDict["offset_y"] as? Double ?? 0
            case .crop:
                step.cropWidth = stepDict["width"] as? Double ?? 0
                step.cropHeight = stepDict["height"] as? Double ?? 0
            }
            return step
        }
    }
}

// MARK: - Pipeline Step Model

enum PipelineStepType: String, CaseIterable, Identifiable {
    case normalize
    case scale
    case round
    case offset
    case crop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normalize: return "Normalize"
        case .scale: return "Scale"
        case .round: return "Round"
        case .offset: return "Offset"
        case .crop: return "Crop"
        }
    }

    var systemImage: String {
        switch self {
        case .normalize: return "arrow.up.arrow.down"
        case .scale: return "arrow.up.left.and.arrow.down.right"
        case .round: return "number"
        case .offset: return "arrow.right.and.line.vertical.and.arrow.left"
        case .crop: return "crop"
        }
    }
}

struct PipelineStep: Identifiable {
    let id = UUID()
    var type: PipelineStepType

    // Scale params
    var scaleX: Double = 1.0
    var scaleY: Double = 1.0

    // Round params
    var roundStrategy: String = "nearest"  // nearest, floor, ceil, even

    // Offset params
    var offsetX: Double = 0
    var offsetY: Double = 0

    // Crop params
    var cropWidth: Double = 0
    var cropHeight: Double = 0
}

// MARK: - Preview Step Model

struct PreviewStep: Identifiable {
    let id = UUID()
    var stepName: String
    var stepType: String
    var inputWidth: Double?
    var inputHeight: Double?
    var outputWidth: Double
    var outputHeight: Double
}
