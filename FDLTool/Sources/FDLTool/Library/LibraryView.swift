import SwiftUI

/// Main Library view with three-column layout:
/// Left: Project list + Canvas Templates
/// Center: FDL entries for selected project
/// Right: FDL detail/viewer (when entry selected)
struct LibraryView: View {
    @EnvironmentObject var appState: AppState

    /// Sections in the left sidebar
    enum LibrarySection: String, CaseIterable {
        case projects = "Projects"
        case templates = "Canvas Templates"
    }

    @State private var selectedSection: LibrarySection = .projects

    var body: some View {
        HSplitView {
            // Left pane: Projects or Templates
            leftPane
                .frame(minWidth: 200, idealWidth: 250, maxWidth: 300)

            // Center pane: FDL entries or template list
            centerPane
                .frame(minWidth: 300, idealWidth: 400)

            // Right pane: Detail view
            rightPane
                .frame(minWidth: 300, idealWidth: 400)
        }
        .navigationTitle("FDL Library")
        .alert("Error", isPresented: Binding(
            get: { appState.libraryViewModel.errorMessage != nil },
            set: { if !$0 { appState.libraryViewModel.errorMessage = nil } }
        )) {
            Button("OK") { appState.libraryViewModel.errorMessage = nil }
        } message: {
            Text(appState.libraryViewModel.errorMessage ?? "")
        }
    }

    // MARK: - Left Pane

    @ViewBuilder
    private var leftPane: some View {
        VStack(spacing: 0) {
            // Section picker
            Picker("Section", selection: $selectedSection) {
                ForEach(LibrarySection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            switch selectedSection {
            case .projects:
                ProjectListView(viewModel: appState.libraryViewModel)
            case .templates:
                CanvasTemplateListView(viewModel: appState.canvasTemplateViewModel)
            }
        }
    }

    // MARK: - Center Pane

    @ViewBuilder
    private var centerPane: some View {
        if selectedSection == .projects {
            fdlEntriesPane
        } else {
            templateDetailPane
        }
    }

    @ViewBuilder
    private var fdlEntriesPane: some View {
        let vm = appState.libraryViewModel

        VStack(spacing: 0) {
            if let project = vm.selectedProject {
                // Header with project name and actions
                HStack {
                    VStack(alignment: .leading) {
                        Text(project.name)
                            .font(.headline)
                        if let desc = project.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(action: { vm.showImportSheet = true }) {
                        Label("Add FDL", systemImage: "plus")
                    }

                    Button(action: { vm.exportProject() }) {
                        Label("Export All", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vm.fdlEntries.isEmpty)
                }
                .padding()

                Divider()

                if vm.fdlEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No FDLs in this project")
                            .foregroundStyle(.secondary)
                        Button("Add FDL...") { vm.showImportSheet = true }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: Binding(
                        get: { vm.selectedEntry?.id },
                        set: { newID in
                            if let id = newID, let entry = vm.fdlEntries.first(where: { $0.id == id }) {
                                vm.selectEntry(entry)
                            }
                        }
                    )) {
                        ForEach(vm.fdlEntries) { entry in
                            FDLEntryRow(entry: entry)
                                .tag(entry.id)
                                .contextMenu {
                                    Button("Export") {
                                        vm.selectedEntry = entry
                                        vm.exportSelectedFDL()
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        vm.deleteEntry(entry)
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Project Selected")
                        .font(.title2)
                    Text("Create or select a project to get started.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $appState.libraryViewModel.showImportSheet) {
            FDLImportSheet(viewModel: appState.libraryViewModel)
        }
    }

    @ViewBuilder
    private var templateDetailPane: some View {
        let tvm = appState.canvasTemplateViewModel
        if let template = tvm.selectedTemplate {
            TemplateDetailView(
                template: template,
                viewModel: tvm,
                libraryViewModel: appState.libraryViewModel
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Select a template to view details")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Right Pane

    @ViewBuilder
    private var rightPane: some View {
        let vm = appState.libraryViewModel
        if selectedSection == .projects {
            if let entry = vm.selectedEntry {
                FDLDetailView(
                    entry: entry,
                    document: vm.parsedDocument,
                    validationResult: vm.validationResult,
                    onExport: { vm.exportSelectedFDL() },
                    onDelete: { vm.deleteEntry(entry) }
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Select an FDL to view details")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // Template preview section
            let tvm = appState.canvasTemplateViewModel
            if tvm.showPreview, let template = tvm.selectedTemplate {
                CanvasTemplatePreviewView(template: template, steps: tvm.previewSteps)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "eye")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Select a template and preview it against an FDL")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - FDL Entry Row

struct FDLEntryRow: View {
    let entry: FDLEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.name)
                .font(.body)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let source = entry.sourceTool {
                    Text(source)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.1), in: Capsule())
                }

                if let camera = entry.cameraModel {
                    Text(camera)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !entry.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(entry.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.1), in: Capsule())
                    }
                    if entry.tags.count > 3 {
                        Text("+\(entry.tags.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Template Detail View

struct TemplateDetailView: View {
    let template: CanvasTemplate
    @ObservedObject var viewModel: CanvasTemplateViewModel
    @ObservedObject var libraryViewModel: LibraryViewModel
    @State private var previewFDLJSON = ""
    @State private var showAssignSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.title2)
                            .fontWeight(.semibold)
                        if let desc = template.description {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    HStack(spacing: 8) {
                        Button("Edit") {
                            viewModel.beginEditing(template)
                        }
                        Button("Export") {
                            viewModel.exportTemplate(template)
                        }
                        Button(role: .destructive) {
                            viewModel.deleteTemplate(template)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                // Pipeline summary
                GroupBox("Pipeline") {
                    pipelineView
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Preview with FDL
                GroupBox("Preview") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Paste FDL JSON to preview template application:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $previewFDLJSON)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 100)
                            .border(Color.secondary.opacity(0.3))
                        Button("Run Preview") {
                            viewModel.previewTemplate(template, withFDLJSON: previewFDLJSON)
                        }
                        .disabled(previewFDLJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Assign to project
                GroupBox("Project Assignment") {
                    VStack(alignment: .leading, spacing: 8) {
                        if libraryViewModel.projects.isEmpty {
                            Text("No projects available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(libraryViewModel.projects) { project in
                                HStack {
                                    Text(project.name)
                                        .font(.caption)
                                    Spacer()
                                    Button("Assign") {
                                        viewModel.assignToProject(template, projectID: project.id, role: "deliverable")
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Raw JSON
                GroupBox("Template JSON") {
                    ScrollView(.horizontal) {
                        Text(formattedJSON)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var pipelineView: some View {
        let steps = parsePipelineSteps()
        if steps.isEmpty {
            Text("No pipeline steps defined")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        if let type = PipelineStepType(rawValue: step) {
                            Label(type.label, systemImage: type.systemImage)
                                .font(.caption)
                        } else {
                            Text(step)
                                .font(.caption)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func parsePipelineSteps() -> [String] {
        guard let data = template.templateJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pipeline = dict["pipeline"] as? [[String: Any]] else {
            return []
        }
        return pipeline.compactMap { $0["type"] as? String }
    }

    private var formattedJSON: String {
        guard let data = template.templateJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return template.templateJSON
        }
        return str
    }
}
