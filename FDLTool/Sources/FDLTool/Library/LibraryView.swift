import SwiftUI
import UniformTypeIdentifiers

/// Main Library view with three-column layout:
/// Left: Project list + Canvas Templates
/// Center: FDL entries for selected project
/// Right: FDL detail/viewer (when entry selected)
struct LibraryView: View {
    @EnvironmentObject var appState: AppState

    private var selectedSection: AppState.LibrarySection {
        get { appState.librarySelectedSection }
        nonmutating set { appState.librarySelectedSection = newValue }
    }

    private enum ProjectContentFilter: String, CaseIterable {
        case cameraFormats = "Camera Formats"
        case framingCharts = "Framing Charts"
        case canvasTemplates = "Canvas Templates"
    }

    @State private var projectContentFilter: ProjectContentFilter = .framingCharts
    @State private var selectedCameraAssignmentID: String?
    @State private var selectedProjectTemplateID: String?
    @State private var blockedCameraFormatDeleteMessage: String?
    @State private var pendingCameraFormatDelete: ProjectCameraModeAssignment?
    @State private var pendingChartDelete: FDLEntry?
    @State private var orphanedCameraFormatsForPendingChartDelete: [ProjectCameraModeAssignment] = []
    @State private var editingCameraFormat: ProjectCameraModeAssignment?
    @State private var editingCameraNotesDraft: String = ""
    @State private var editingChartEntry: FDLEntry?
    @State private var showEditChartTitleSheet = false
    @State private var editingChartTitleDraft: String = ""

    var body: some View {
        HSplitView {
            // Left pane: Projects or Templates
            leftPane
                .frame(minWidth: 230, idealWidth: 270, maxWidth: 320)

            // Center pane: FDL entries or template list
            centerPane
                .frame(minWidth: 320, idealWidth: 420)

            // Right pane: Detail view
            rightPane
                .frame(minWidth: 360, idealWidth: 460)
        }
        .navigationTitle("FDL Library")
        .onChange(of: appState.libraryViewModel.selectedProject?.id) { _, _ in
            projectContentFilter = .framingCharts
            selectedCameraAssignmentID = nil
            selectedProjectTemplateID = nil
        }
        .alert("Error", isPresented: Binding(
            get: { appState.libraryViewModel.errorMessage != nil },
            set: { if !$0 { appState.libraryViewModel.errorMessage = nil } }
        )) {
            Button("OK") { appState.libraryViewModel.errorMessage = nil }
        } message: {
            Text(appState.libraryViewModel.errorMessage ?? "")
        }
        .alert("Cannot Remove Camera Format", isPresented: Binding(
            get: { blockedCameraFormatDeleteMessage != nil },
            set: { if !$0 { blockedCameraFormatDeleteMessage = nil } }
        )) {
            Button("OK") { blockedCameraFormatDeleteMessage = nil }
        } message: {
            Text(blockedCameraFormatDeleteMessage ?? "")
        }
        .confirmationDialog(
            "Remove Camera Format?",
            isPresented: Binding(
                get: { pendingCameraFormatDelete != nil },
                set: { if !$0 { pendingCameraFormatDelete = nil } }
            ),
            presenting: pendingCameraFormatDelete
        ) { assignment in
            Button("Remove", role: .destructive) {
                appState.libraryViewModel.removeCameraFormatFromProject(assignment)
                if selectedCameraAssignmentID == assignment.id {
                    selectedCameraAssignmentID = nil
                }
                pendingCameraFormatDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCameraFormatDelete = nil
            }
        } message: { assignment in
            Text("Remove \(assignment.cameraModelName) / \(assignment.recordingModeName) from this project?")
        }
        .confirmationDialog(
            "Delete Framing Chart?",
            isPresented: Binding(
                get: { pendingChartDelete != nil },
                set: { if !$0 { pendingChartDelete = nil } }
            ),
            presenting: pendingChartDelete
        ) { entry in
            if orphanedCameraFormatsForPendingChartDelete.isEmpty {
                Button("Delete Chart", role: .destructive) {
                    appState.libraryViewModel.deleteChartEntry(entry, removeOrphanedFormats: false)
                    pendingChartDelete = nil
                }
            } else {
                Button("Delete Chart Only", role: .destructive) {
                    appState.libraryViewModel.deleteChartEntry(entry, removeOrphanedFormats: false)
                    pendingChartDelete = nil
                }
                Button("Delete Chart + Remove Orphaned Camera Formats", role: .destructive) {
                    appState.libraryViewModel.deleteChartEntry(entry, removeOrphanedFormats: true)
                    pendingChartDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingChartDelete = nil
            }
        } message: { entry in
            if orphanedCameraFormatsForPendingChartDelete.isEmpty {
                Text("Delete '\(entry.name)' from this project?")
            } else {
                let formats = orphanedCameraFormatsForPendingChartDelete
                    .map { "\($0.cameraModelName) / \($0.recordingModeName)" }
                    .joined(separator: "\n")
                Text("Deleting '\(entry.name)' leaves these camera formats unused.\n\n\(formats)\n\nRemove them too?")
            }
        }
        .sheet(item: $editingCameraFormat) { assignment in
            cameraFormatNotesSheet(for: assignment)
        }
        .sheet(isPresented: $showEditChartTitleSheet) {
            chartTitleRenameSheet
        }
        .onChange(of: appState.pythonBridgeStatus) { _, status in
            guard status == .running else { return }
            Task {
                await appState.libraryViewModel.refreshFramelineInterop()
            }
        }
    }

    // MARK: - Left Pane

    @ViewBuilder
    private var leftPane: some View {
        VStack(spacing: 0) {
            // Section picker
            Picker("", selection: $appState.librarySelectedSection) {
                ForEach(AppState.LibrarySection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
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

                    Menu {
                        Button("Camera Format") {
                            routeToToolForProjectCreation(.cameraDB, project: project)
                        }
                        Button("Framing Chart") {
                            routeToToolForProjectCreation(.chartGenerator, project: project)
                        }
                        Button("Canvas Template") {
                            routeToToolForProjectCreation(.viewer, project: project)
                        }
                        Divider()
                        Button("Import Existing FDL...") {
                            vm.showImportSheet = true
                        }
                    } label: {
                        Label("Add to Project", systemImage: "plus")
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)

                    Button(action: { vm.exportProject() }) {
                        Label("Export All", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(vm.fdlEntries.isEmpty)
                }
                .padding()

                if !vm.projectAssets.isEmpty || !vm.projectCameraModeAssignments.isEmpty || !vm.projectTemplates.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Graph")
                            .secondarySectionHeader()

                        HStack(spacing: 10) {
                            projectCategoryChip(title: "Camera Formats", count: vm.projectCameraModeAssignments.count)
                            projectCategoryChip(title: "Framing Charts", count: vm.fdlEntries.count)
                            projectCategoryChip(title: "Canvas Templates", count: vm.projectTemplates.count)
                        }

                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                            GridRow {
                                Text("Camera Formats")
                                    .foregroundStyle(.secondary)
                                Text("\(vm.projectCameraModeAssignments.count) linked")
                            }
                            GridRow {
                                Text("Framing Charts")
                                    .foregroundStyle(.secondary)
                                Text("\(vm.fdlEntries.count) saved")
                            }
                            GridRow {
                                Text("Canvas Templates")
                                    .foregroundStyle(.secondary)
                                Text("\(vm.projectTemplates.count) assigned")
                            }
                        }
                        .font(.caption2)

                        if let latestMode = vm.projectCameraModeAssignments.first {
                            Text("Latest camera format: \(latestMode.cameraModelName) - \(latestMode.recordingModeName)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                projectFilterBar(vm: vm)

                Divider()

                projectItemsList(vm: vm, project: project)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("No Project Selected")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Create or select a project to get started.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
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
            .id(template.id)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 32))
                    .foregroundStyle(.quaternary)
                Text("Select a Template")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Choose a canvas template from the list to view its parameters.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Right Pane

    @ViewBuilder
    private var rightPane: some View {
        let vm = appState.libraryViewModel
        if selectedSection == .projects {
            switch projectContentFilter {
            case .framingCharts:
                if let entry = vm.selectedEntry {
                    FDLDetailView(
                        entry: entry,
                        document: vm.parsedDocument,
                        validationResult: vm.validationResult,
                        libraryViewModel: vm,
                        onOpenInViewer: {
                            appState.selectedTool = .viewer
                            appState.viewerViewModel.loadFromEntry(
                                entry,
                                pythonBridge: appState.pythonBridge,
                                libraryStore: appState.libraryStore
                            )
                        },
                        onExport: { vm.exportSelectedFDL() },
                        onEditTitle: {
                            beginChartTitleEdit(entry)
                        },
                        onDelete: { requestChartDeletion(entry) }
                    )
                } else {
                    emptyFilteredSelectionView()
                }
            case .cameraFormats:
                if let selected = vm.projectCameraModeAssignments.first(where: { $0.id == selectedCameraAssignmentID }) {
                    cameraFormatDetailView(selected)
                } else {
                    emptyFilteredSelectionView()
                }
            case .canvasTemplates:
                if let selected = vm.projectTemplates.first(where: { $0.id == selectedProjectTemplateID }) {
                    projectTemplateDetailView(selected)
                } else {
                    emptyFilteredSelectionView()
                }
            }
        } else {
            TemplatePreviewPanel(
                viewModel: appState.canvasTemplateViewModel,
                pythonBridge: appState.pythonBridge
            )
        }
    }

    @ViewBuilder
    private func projectFilterBar(vm: LibraryViewModel) -> some View {
        HStack(spacing: 8) {
            filterButton(title: "Camera Formats", count: vm.projectCameraModeAssignments.count, filter: .cameraFormats)
            filterButton(title: "Framing Charts", count: vm.fdlEntries.count, filter: .framingCharts)
            filterButton(title: "Canvas Templates", count: vm.projectTemplates.count, filter: .canvasTemplates)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func projectItemsList(vm: LibraryViewModel, project: Project) -> some View {
        switch projectContentFilter {
        case .cameraFormats:
            if vm.projectCameraModeAssignments.isEmpty {
                Text("No camera formats assigned")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedCameraAssignmentID) {
                    ForEach(vm.projectCameraModeAssignments) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.cameraModelName)
                                .font(.body)
                            Text(mode.recordingModeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(mode.id)
                        .contextMenu {
                            Button("Edit Notes") {
                                editingCameraNotesDraft = mode.notes ?? ""
                                editingCameraFormat = mode
                            }
                            Divider()
                            Button("Remove from Project", role: .destructive) {
                                requestCameraFormatRemoval(mode)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

        case .framingCharts:
            if vm.fdlEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("No Framing Charts in this project")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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
                        FramingChartRow(
                            entry: entry,
                            metadata: vm.chartRowMetadataByEntryID[entry.id]
                        )
                        .tag(entry.id)
                        .contextMenu {
                            Button("Open in Framing Workspace") {
                                appState.selectedTool = .viewer
                                appState.viewerViewModel.loadFromEntry(
                                    entry,
                                    pythonBridge: appState.pythonBridge,
                                    libraryStore: appState.libraryStore
                                )
                            }
                            Divider()
                            Button("Export") {
                                vm.selectedEntry = entry
                                vm.exportSelectedFDL()
                            }
                            Divider()
                            Button("Edit Chart Title") {
                                beginChartTitleEdit(entry)
                            }
                            Button("Delete", role: .destructive) {
                                requestChartDeletion(entry)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

        case .canvasTemplates:
            if vm.projectTemplates.isEmpty {
                Text("No templates assigned")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedProjectTemplateID) {
                    ForEach(vm.projectTemplates) { template in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.body)
                            Text(template.source ?? "manual")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(template.id)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func routeToToolForProjectCreation(_ tool: Tool, project: Project) {
        appState.currentProject = project
        appState.selectedTool = tool
    }

    private func filterButton(title: String, count: Int, filter: ProjectContentFilter) -> some View {
        Button {
            projectContentFilter = filter
            switch filter {
            case .cameraFormats:
                appState.libraryViewModel.selectedEntry = nil
                selectedProjectTemplateID = nil
            case .framingCharts:
                selectedCameraAssignmentID = nil
                selectedProjectTemplateID = nil
            case .canvasTemplates:
                appState.libraryViewModel.selectedEntry = nil
                selectedCameraAssignmentID = nil
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .fontWeight(.semibold)
            }
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(projectContentFilter == filter ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func emptyFilteredSelectionView() -> some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("Select an item")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Choose an item from the filtered project list.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cameraFormatDetailView(_ assignment: ProjectCameraModeAssignment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Camera Format")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Edit Notes") {
                    editingCameraNotesDraft = assignment.notes ?? ""
                    editingCameraFormat = assignment
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Remove", role: .destructive) {
                    requestCameraFormatRemoval(assignment)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            GroupBox("Details") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("Camera").foregroundStyle(.secondary)
                        Text(assignment.cameraModelName)
                    }
                    GridRow {
                        Text("Capture Mode").foregroundStyle(.secondary)
                        Text(assignment.recordingModeName)
                    }
                    if let source = assignment.source, !source.isEmpty {
                        GridRow {
                            Text("Source").foregroundStyle(.secondary)
                            Text(source)
                        }
                    }
                    GridRow {
                        Text("Notes").foregroundStyle(.secondary)
                        Text((assignment.notes?.isEmpty == false) ? assignment.notes! : "None")
                    }
                }
                .font(.caption)
                .padding(.vertical, 4)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func projectTemplateDetailView(_ template: CanvasTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Canvas Template")
                .font(.title3.weight(.semibold))
            GroupBox("Details") {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("Name").foregroundStyle(.secondary)
                        Text(template.name)
                    }
                    GridRow {
                        Text("Source").foregroundStyle(.secondary)
                        Text(template.source ?? "manual")
                    }
                    GridRow {
                        Text("Template ID").foregroundStyle(.secondary)
                        Text(template.id)
                            .textSelection(.enabled)
                    }
                }
                .font(.caption)
                .padding(.vertical, 4)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func requestCameraFormatRemoval(_ assignment: ProjectCameraModeAssignment) {
        let result = appState.libraryViewModel.canRemoveCameraFormat(assignment)
        if result.allowed {
            pendingCameraFormatDelete = assignment
            return
        }

        let chartList = result.linkedChartNames.joined(separator: "\n")
        blockedCameraFormatDeleteMessage = "This camera format is still linked to framing charts.\n\n\(chartList)\n\nDelete those charts first, or remove the link from each chart."
    }

    private func requestChartDeletion(_ entry: FDLEntry) {
        orphanedCameraFormatsForPendingChartDelete = appState.libraryViewModel.orphanedCameraFormatsIfDeletingChart(entry)
        pendingChartDelete = entry
    }

    @ViewBuilder
    private func cameraFormatNotesSheet(for assignment: ProjectCameraModeAssignment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Camera Format Notes")
                .font(.headline)
            Text("\(assignment.cameraModelName) / \(assignment.recordingModeName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $editingCameraNotesDraft)
                .frame(minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel") {
                    editingCameraFormat = nil
                }
                Button("Save") {
                    appState.libraryViewModel.updateCameraFormatNotes(
                        assignmentID: assignment.id,
                        notes: editingCameraNotesDraft
                    )
                    editingCameraFormat = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 260)
    }

    private func beginChartTitleEdit(_ entry: FDLEntry) {
        editingChartEntry = entry
        editingChartTitleDraft = entry.name
        showEditChartTitleSheet = true
    }

    @ViewBuilder
    private var chartTitleRenameSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Chart Title")
                .font(.headline)
            if let entry = editingChartEntry {
                Text("Current: \(entry.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Chart title", text: $editingChartTitleDraft)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") {
                    showEditChartTitleSheet = false
                }
                Button("Save") {
                    if let entry = editingChartEntry {
                        appState.libraryViewModel.renameChartEntry(entry, to: editingChartTitleDraft)
                    }
                    showEditChartTitleSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(editingChartTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 180)
    }

    @ViewBuilder
    private func projectCategoryChip(title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text("\(count)")
                .fontWeight(.semibold)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func assetTypeCounts(from assets: [ProjectAsset]) -> [(type: ProjectAssetType, count: Int)] {
        let grouped = Dictionary(grouping: assets, by: \.assetType)
        return grouped
            .map { ($0.key, $0.value.count) }
            .sorted { $0.type.rawValue < $1.type.rawValue }
    }

    private func assetTypeLabel(_ type: ProjectAssetType) -> String {
        switch type {
        case .fdl: return "FDL"
        case .chart: return "Chart"
        case .template: return "Template"
        case .report: return "Report"
        case .cameraMode: return "Camera Mode"
        case .referenceImage: return "Reference"
        }
    }
}

// MARK: - Framing Chart Row

struct FramingChartRow: View {
    let entry: FDLEntry
    let metadata: ChartRowMetadata?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                        .lineLimit(1)
                }
            }

            if let metadata {
                metadataPairLine(
                    leftLabel: "Canvas",
                    leftValue: metadata.canvasDimensions,
                    rightLabel: "Framing",
                    rightValue: metadata.framingDimensions
                )
                metadataPairLine(
                    leftLabel: "Intent",
                    leftValue: metadata.framingIntent,
                    rightLabel: "Protection",
                    rightValue: metadata.intentProtection
                )
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

    @ViewBuilder
    private func metadataPairLine(
        leftLabel: String,
        leftValue: String,
        rightLabel: String,
        rightValue: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            metadataItem(label: leftLabel, value: leftValue)
            metadataItem(label: rightLabel, value: rightValue)
        }
    }

    @ViewBuilder
    private func metadataItem(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(label):")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var isEditingEnabled = false
    @State private var editConfig = CanvasTemplateConfig()
    @State private var assignedProjectIDs: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerView
                templateFieldsView
                projectAssignmentView
                jsonDisclosure
            }
            .padding()
        }
        .onAppear { loadState() }
        .onChange(of: template.id) { _, _ in
            isEditingEnabled = false
            loadState()
        }
        .onChange(of: isEditingEnabled) { _, editing in
            if !editing { saveEdits() }
        }
    }

    private func loadState() {
        editConfig = parseConfig()
        assignedProjectIDs = (
            try? libraryViewModel.libraryStore.projectIDsForTemplate(
                template.id
            )
        ) ?? []
    }

    // MARK: - Header

    @ViewBuilder
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if isEditingEnabled {
                    TextField("Label", text: $editConfig.label)
                        .font(.title3.weight(.semibold))
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(template.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Toggle(isOn: $isEditingEnabled) {
                    Image(
                        systemName: isEditingEnabled
                            ? "lock.open.fill" : "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        isEditingEnabled ? .orange : .secondary
                    )
                }
                .toggleStyle(.button)
                .help(isEditingEnabled ? "Lock editing" : "Unlock editing")

                Button {
                    viewModel.exportTemplate(template)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .help("Export")

                Button(role: .destructive) {
                    viewModel.deleteTemplate(template)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .disabled(!isEditingEnabled)
            }

            if let desc = template.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Template Fields (lock/unlock)

    @ViewBuilder
    private var templateFieldsView: some View {
        GroupBox("Template Parameters") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Target Dims")
                        .gridColumnAlignment(.trailing)
                    if isEditingEnabled {
                        HStack(spacing: 4) {
                            TextField("W", value: $editConfig.targetWidth, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("\u{00D7}").foregroundStyle(.secondary)
                            TextField("H", value: $editConfig.targetHeight, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    } else {
                        Text(verbatim: "\(editConfig.targetWidth) \u{00D7} \(editConfig.targetHeight)")
                    }
                }

                GridRow {
                    Text("Squeeze")
                    if isEditingEnabled {
                        TextField("Squeeze", value: $editConfig.targetAnamorphicSqueeze, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    } else {
                        Text(verbatim: "\(String(format: "%.1f", editConfig.targetAnamorphicSqueeze))\u{00D7}")
                    }
                }

                GridRow {
                    Text("Fit Source")
                    if isEditingEnabled {
                        Picker("", selection: $editConfig.fitSource) {
                            ForEach(TemplatePresets.fitSourceOptions, id: \.value) { opt in
                                Text(opt.label).tag(opt.value)
                            }
                        }
                        .labelsHidden()
                    } else {
                        Text(TemplatePresets.fitSourceOptions.first { $0.value == editConfig.fitSource }?.label ?? editConfig.fitSource)
                    }
                }

                GridRow {
                    Text("Fit Method")
                    if isEditingEnabled {
                        Picker("", selection: $editConfig.fitMethod) {
                            ForEach(TemplatePresets.fitMethodOptions, id: \.value) { opt in
                                Text(opt.label).tag(opt.value)
                            }
                        }
                        .labelsHidden()
                    } else {
                        Text(TemplatePresets.fitMethodOptions.first { $0.value == editConfig.fitMethod }?.label ?? editConfig.fitMethod)
                    }
                }

                GridRow {
                    Text("Alignment")
                    if isEditingEnabled {
                        HStack(spacing: 4) {
                            Picker("H", selection: $editConfig.alignmentHorizontal) {
                                ForEach(TemplatePresets.alignmentHOptions, id: \.value) { o in
                                    Text(o.label).tag(o.value)
                                }
                            }
                            .frame(minWidth: 80)
                            Picker("V", selection: $editConfig.alignmentVertical) {
                                ForEach(TemplatePresets.alignmentVOptions, id: \.value) { o in
                                    Text(o.label).tag(o.value)
                                }
                            }
                            .frame(minWidth: 80)
                        }
                    } else {
                        Text(verbatim: "\(editConfig.alignmentHorizontal) / \(editConfig.alignmentVertical)")
                    }
                }

                GridRow {
                    Text("Rounding")
                    if isEditingEnabled {
                        HStack(spacing: 4) {
                            Picker("", selection: $editConfig.roundEven) {
                                ForEach(TemplatePresets.roundEvenOptions, id: \.value) { o in
                                    Text(o.label).tag(o.value)
                                }
                            }
                            .labelsHidden()
                            .frame(minWidth: 90)
                            Picker("", selection: $editConfig.roundMode) {
                                ForEach(TemplatePresets.roundModeOptions, id: \.value) { o in
                                    Text(o.label).tag(o.value)
                                }
                            }
                            .labelsHidden()
                            .frame(minWidth: 90)
                        }
                    } else {
                        Text(verbatim: "\(editConfig.roundEven) / \(editConfig.roundMode)")
                    }
                }

                GridRow {
                    Text("Max Dims")
                    if isEditingEnabled {
                        HStack(spacing: 4) {
                            TextField("Max W", value: $editConfig.maximumWidth, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("\u{00D7}").foregroundStyle(.secondary)
                            TextField("Max H", value: $editConfig.maximumHeight, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    } else {
                        if let mw = editConfig.maximumWidth, let mh = editConfig.maximumHeight {
                            Text(verbatim: "\(mw) \u{00D7} \(mh)")
                        } else {
                            Text("None").foregroundStyle(.tertiary)
                        }
                    }
                }

                GridRow {
                    Text("Pad to Max")
                    if isEditingEnabled {
                        Toggle("", isOn: $editConfig.padToMaximum)
                            .labelsHidden()
                    } else {
                        Text(editConfig.padToMaximum ? "Yes" : "No")
                    }
                }

                GridRow {
                    Text("Preserve")
                    if isEditingEnabled {
                        Picker("", selection: Binding(
                            get: { editConfig.preserveFromSourceCanvas ?? "" },
                            set: { editConfig.preserveFromSourceCanvas = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("None").tag("")
                            Text("Framing Decision").tag("framing_decision.dimensions")
                            Text("Protection").tag("framing_decision.protection_dimensions")
                            Text("Effective Canvas").tag("canvas.effective_dimensions")
                            Text("Full Canvas").tag("canvas.dimensions")
                        }
                        .labelsHidden()
                    } else {
                        if let preserve = editConfig.preserveFromSourceCanvas, !preserve.isEmpty {
                            Text(preserveLabel(preserve))
                        } else {
                            Text("None").foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func preserveLabel(_ value: String) -> String {
        switch value {
        case "framing_decision.dimensions": return "Framing Decision"
        case "framing_decision.protection_dimensions": return "Protection"
        case "canvas.effective_dimensions": return "Effective Canvas"
        case "canvas.dimensions": return "Full Canvas"
        default: return value
        }
    }

    // MARK: - Project Assignment (checkmarks)

    @ViewBuilder
    private var projectAssignmentView: some View {
        GroupBox("Projects") {
            VStack(alignment: .leading, spacing: 4) {
                if libraryViewModel.projects.isEmpty {
                    Text("No projects. Create one in the Projects tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(libraryViewModel.projects) { project in
                        let isAssigned = assignedProjectIDs.contains(
                            project.id
                        )
                        Button {
                            toggleProjectAssignment(
                                projectID: project.id,
                                isAssigned: isAssigned
                            )
                        } label: {
                            HStack(spacing: 8) {
                                Image(
                                    systemName: isAssigned
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                                .foregroundStyle(
                                    isAssigned ? .blue : .secondary
                                )
                                Text(project.name)
                                    .font(.caption)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggleProjectAssignment(
        projectID: String, isAssigned: Bool
    ) {
        do {
            if isAssigned {
                try libraryViewModel.libraryStore.removeTemplateFromProject(
                    templateID: template.id, projectID: projectID
                )
                assignedProjectIDs.remove(projectID)
            } else {
                try libraryViewModel.libraryStore.assignTemplate(
                    templateID: template.id,
                    toProject: projectID
                )
                assignedProjectIDs.insert(projectID)
            }
        } catch {
            viewModel.errorMessage = "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - JSON Disclosure

    @ViewBuilder
    private var jsonDisclosure: some View {
        DisclosureGroup {
            ScrollView([.horizontal, .vertical]) {
                Text(formattedJSON)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Template JSON")
                .font(.caption.weight(.medium))
        }
    }

    // MARK: - Helpers

    private func parseConfig() -> CanvasTemplateConfig {
        var c = CanvasTemplateConfig()
        guard let data = template.templateJSON.data(using: .utf8),
              let d = try? JSONSerialization.jsonObject(
                  with: data
              ) as? [String: Any]
        else {
            c.label = template.name
            return c
        }
        if let id = d["id"] as? String { c.id = id }
        c.label = (d["label"] as? String) ?? template.name
        if let t = d["target_dimensions"] as? [String: Any] {
            if let w = t["width"] as? Int { c.targetWidth = w }
            if let h = t["height"] as? Int { c.targetHeight = h }
        }
        if let v = d["target_anamorphic_squeeze"] as? Double { c.targetAnamorphicSqueeze = v }
        else if let v = d["target_anamorphic_squeeze"] as? Int { c.targetAnamorphicSqueeze = Double(v) }
        if let v = d["fit_source"] as? String { c.fitSource = v }
        if let v = d["fit_method"] as? String { c.fitMethod = v }
        if let v = d["alignment_method_horizontal"] as? String {
            c.alignmentHorizontal = v
        }
        if let v = d["alignment_method_vertical"] as? String {
            c.alignmentVertical = v
        }
        if let v = d["preserve_from_source_canvas"] as? String {
            c.preserveFromSourceCanvas = v
        }
        if let v = d["pad_to_maximum"] as? Bool { c.padToMaximum = v }
        if let mx = d["maximum_dimensions"] as? [String: Any] {
            c.maximumWidth = mx["width"] as? Int
            c.maximumHeight = mx["height"] as? Int
        }
        if let r = d["round"] as? [String: Any] {
            if let v = r["even"] as? String { c.roundEven = v }
            if let v = r["mode"] as? String { c.roundMode = v }
        }
        return c
    }

    private func saveEdits() {
        let dict = editConfig.toDict()
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]
        ),
              let jsonStr = String(data: data, encoding: .utf8)
        else { return }
        let updated = CanvasTemplate(
            id: template.id,
            name: editConfig.label,
            description: template.description,
            templateJSON: jsonStr,
            source: template.source,
            createdAt: template.createdAt,
            updatedAt: Date()
        )
        try? libraryViewModel.libraryStore.saveCanvasTemplate(updated)
        viewModel.loadTemplates()
    }

    private var formattedJSON: String {
        guard let data = template.templateJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let str = String(data: pretty, encoding: .utf8) else {
            return template.templateJSON
        }
        return str
    }
}

// MARK: - Template Preview Panel (Right Pane)

struct TemplatePreviewPanel: View {
    @ObservedObject var viewModel: CanvasTemplateViewModel
    let pythonBridge: PythonBridge
    @State private var sourceFDLDoc: FDLDocument?
    @State private var sourceFileName: String?
    @State private var previewGeometry: ComputedGeometry?
    @State private var errorMessage: String?

    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var showCanvasLayer = true
    @State private var showEffectiveLayer = true
    @State private var showProtectionLayer = true
    @State private var showFramingLayer = true
    @State private var showDimensionLabels = true
    @State private var showAnchorPoints = false
    @State private var showCrosshairs = true
    @State private var showHUD = true

    var body: some View {
        VStack(spacing: 0) {
            if let template = viewModel.selectedTemplate {
                previewToolbar
                Divider()

                if sourceFDLDoc == nil {
                    sourceSelectionView(template: template)
                } else {
                    previewCanvas
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "eye")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("Template Preview")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Select a template and load a source FDL to see a visual preview.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 240)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: viewModel.selectedTemplate?.id) { _, _ in
            if let doc = sourceFDLDoc {
                applyTemplatePreview(doc: doc)
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var previewToolbar: some View {
        HStack(spacing: 8) {
            Text("Preview")
                .font(.headline)

            Spacer()

            if sourceFDLDoc != nil {
                HStack(spacing: 4) {
                    Button(action: { zoomScale = max(zoomScale / 1.25, 0.1) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    Text(verbatim: "\(Int(zoomScale * 100))%")
                        .font(.caption)
                        .frame(width: 36)
                    Button(action: { zoomScale = min(zoomScale * 1.25, 10) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    Button(action: { zoomScale = 1.0; panOffset = .zero }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .help("Fit to view")
                }

                Divider().frame(height: 18)

                Menu {
                    Toggle("Canvas", isOn: $showCanvasLayer)
                    Toggle("Effective", isOn: $showEffectiveLayer)
                    Toggle("Framing", isOn: $showFramingLayer)
                    Toggle("Protection", isOn: $showProtectionLayer)
                    Divider()
                    Toggle("Labels", isOn: $showDimensionLabels)
                    Toggle("Anchors", isOn: $showAnchorPoints)
                    Toggle("Crosshairs", isOn: $showCrosshairs)
                    Toggle("HUD", isOn: $showHUD)
                } label: {
                    Label("Layers", systemImage: "square.3.layers.3d")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Divider().frame(height: 18)

                Button("Clear") {
                    sourceFDLDoc = nil
                    sourceFileName = nil
                    previewGeometry = nil
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Source Selection

    @ViewBuilder
    private func sourceSelectionView(template: CanvasTemplate) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Load a Source FDL to preview against this template")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open FDL File...") {
                loadSourceFDL()
            }
            .buttonStyle(.bordered)

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(
                    "public.file-url"
                ) {
                    provider.loadItem(
                        forTypeIdentifier: "public.file-url"
                    ) { item, _ in
                        if let data = item as? Data,
                           let url = URL(
                               dataRepresentation: data,
                               relativeTo: nil
                           ) {
                            let ext = url.pathExtension.lowercased()
                            if ["fdl", "json"].contains(ext) {
                                DispatchQueue.main.async {
                                    loadFDLFromURL(url)
                                }
                            }
                        }
                    }
                }
            }
            return true
        }
    }

    // MARK: - Preview Canvas

    @ViewBuilder
    private var previewCanvas: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let doc = sourceFDLDoc {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue)
                    Text(sourceFileName ?? "Source FDL")
                        .font(.caption.weight(.medium))
                    Spacer()
                    if let canvas = doc.contexts.first?.canvases.first {
                        Text(verbatim: "Source: \(Int(canvas.dimensions.width))\u{00D7}\(Int(canvas.dimensions.height))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            if let geo = previewGeometry,
               let ctx = geo.contexts.first,
               let computedCanvas = ctx.canvases.first {
                GeometryReader { proxy in
                    let cRect = computedCanvas.canvasRect
                    let canvasW = cRect.width
                    let canvasH = cRect.height

                    let fitScale = min(
                        proxy.size.width / max(canvasW, 1),
                        proxy.size.height / max(canvasH, 1)
                    ) * 0.9
                    let totalScale = fitScale * zoomScale
                    let scaledW = canvasW * totalScale
                    let scaledH = canvasH * totalScale
                    let baseX = (proxy.size.width - scaledW) / 2 + panOffset.width
                    let baseY = (proxy.size.height - scaledH) / 2 + panOffset.height

                    ZStack(alignment: .topLeading) {
                        Color.clear

                        if showCanvasLayer {
                            previewRect(
                                cRect, scale: totalScale,
                                baseX: baseX, baseY: baseY,
                                color: ViewerColors.canvas,
                                lineWidth: 2, dashed: false, fill: 0.08
                            )
                            if showDimensionLabels {
                                previewDimLabel(
                                    "\(Int(cRect.width))\u{00D7}\(Int(cRect.height))",
                                    rect: cRect, scale: totalScale,
                                    baseX: baseX, baseY: baseY,
                                    color: ViewerColors.canvas,
                                    position: .topRight
                                )
                            }
                        }

                        if showEffectiveLayer,
                           let eff = computedCanvas.effectiveRect {
                            previewRect(
                                eff, scale: totalScale,
                                baseX: baseX, baseY: baseY,
                                color: ViewerColors.effective,
                                lineWidth: 1.5, dashed: false, fill: 0.08
                            )
                            if showDimensionLabels {
                                previewDimLabel(
                                    "Eff \(Int(eff.width))\u{00D7}\(Int(eff.height))",
                                    rect: eff, scale: totalScale,
                                    baseX: baseX, baseY: baseY,
                                    color: ViewerColors.effective,
                                    position: .bottomLeft
                                )
                            }
                        }

                        ForEach(
                            Array(
                                computedCanvas.framingDecisions
                                    .enumerated()
                            ), id: \.offset
                        ) { _, fd in
                            if showProtectionLayer,
                               let prot = fd.protectionRect {
                                previewRect(
                                    prot, scale: totalScale,
                                    baseX: baseX, baseY: baseY,
                                    color: ViewerColors.protection,
                                    lineWidth: 1.5, dashed: true,
                                    fill: 0.05
                                )
                                if showDimensionLabels {
                                    previewDimLabel(
                                        "Prot \(Int(prot.width))\u{00D7}\(Int(prot.height))",
                                        rect: prot, scale: totalScale,
                                        baseX: baseX, baseY: baseY,
                                        color: ViewerColors.protection,
                                        position: .bottomLeft
                                    )
                                }
                            }

                            if showFramingLayer {
                                let fr = fd.framingRect
                                previewRect(
                                    fr, scale: totalScale,
                                    baseX: baseX, baseY: baseY,
                                    color: ViewerColors.framing,
                                    lineWidth: 2, dashed: false,
                                    fill: 0.08
                                )

                                if showCrosshairs {
                                    previewCrosshair(
                                        rect: fr, scale: totalScale,
                                        baseX: baseX, baseY: baseY
                                    )
                                }

                                if showAnchorPoints,
                                   let anchor = fd.anchorPoint {
                                    previewAnchorMarker(
                                        x: anchor.x, y: anchor.y,
                                        scale: totalScale,
                                        baseX: baseX, baseY: baseY
                                    )
                                }

                                if showDimensionLabels {
                                    previewDimLabel(
                                        "\(Int(fr.width))\u{00D7}\(Int(fr.height))",
                                        rect: fr, scale: totalScale,
                                        baseX: baseX, baseY: baseY,
                                        color: ViewerColors.framing,
                                        position: .bottomRight
                                    )
                                }
                            }
                        }

                        if showHUD {
                            previewHUD(
                                canvasW: canvasW, canvasH: canvasH
                            )
                        }
                    }
                    .gesture(
                        DragGesture().onChanged { value in
                            panOffset = value.translation
                        }
                    )
                    .onTapGesture(count: 2) {
                        zoomScale = 1.0
                        panOffset = .zero
                    }
                }
                .background(
                    Color(nsColor: NSColor(white: 0.12, alpha: 1))
                )
            } else {
                VStack {
                    ProgressView()
                    Text("Computing preview...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Color(nsColor: NSColor(white: 0.12, alpha: 1))
                )
            }
        }
    }

    // MARK: - Drawing Primitives

    @ViewBuilder
    private func previewRect(
        _ gr: GeometryRect,
        scale: CGFloat, baseX: CGFloat, baseY: CGFloat,
        color: Color, lineWidth: CGFloat, dashed: Bool, fill: Double
    ) -> some View {
        let x = baseX + CGFloat(gr.x) * scale
        let y = baseY + CGFloat(gr.y) * scale
        let w = CGFloat(gr.width) * scale
        let h = CGFloat(gr.height) * scale

        Rectangle()
            .fill(color.opacity(fill))
            .frame(width: w, height: h)
            .offset(x: x, y: y)

        if dashed {
            Rectangle()
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: lineWidth, dash: [8, 5]
                    )
                )
                .frame(width: w, height: h)
                .offset(x: x, y: y)
        } else {
            Rectangle()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: w, height: h)
                .offset(x: x, y: y)
        }
    }

    @ViewBuilder
    private func previewCrosshair(
        rect gr: GeometryRect,
        scale: CGFloat, baseX: CGFloat, baseY: CGFloat
    ) -> some View {
        let cx = baseX + CGFloat(gr.x + gr.width / 2) * scale
        let cy = baseY + CGFloat(gr.y + gr.height / 2) * scale
        let arm: CGFloat = 10
        Path { path in
            path.move(to: CGPoint(x: cx - arm, y: cy))
            path.addLine(to: CGPoint(x: cx + arm, y: cy))
            path.move(to: CGPoint(x: cx, y: cy - arm))
            path.addLine(to: CGPoint(x: cx, y: cy + arm))
        }
        .stroke(ViewerColors.crosshair, lineWidth: 1)
    }

    @ViewBuilder
    private func previewAnchorMarker(
        x: Double, y: Double,
        scale: CGFloat, baseX: CGFloat, baseY: CGFloat
    ) -> some View {
        let px = baseX + CGFloat(x) * scale
        let py = baseY + CGFloat(y) * scale
        Circle()
            .fill(ViewerColors.framing)
            .frame(width: 6, height: 6)
            .offset(x: px - 3, y: py - 3)
    }

    private enum LabelPosition {
        case topRight, bottomLeft, bottomRight
    }

    @ViewBuilder
    private func previewDimLabel(
        _ text: String, rect gr: GeometryRect,
        scale: CGFloat, baseX: CGFloat, baseY: CGFloat,
        color: Color, position: LabelPosition
    ) -> some View {
        let rx = baseX + CGFloat(gr.x) * scale
        let ry = baseY + CGFloat(gr.y) * scale
        let rw = CGFloat(gr.width) * scale
        let rh = CGFloat(gr.height) * scale
        let pt: CGPoint = {
            switch position {
            case .topRight:
                return CGPoint(x: rx + rw - 4, y: ry + 2)
            case .bottomLeft:
                return CGPoint(x: rx + 4, y: ry + rh - 16)
            case .bottomRight:
                return CGPoint(x: rx + rw - 4, y: ry + rh - 16)
            }
        }()

        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(color.opacity(0.9))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                .black.opacity(0.5),
                in: RoundedRectangle(cornerRadius: 2)
            )
            .offset(x: pt.x, y: pt.y)
    }

    @ViewBuilder
    private func previewHUD(
        canvasW: Double, canvasH: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("TEMPLATE PREVIEW")
                .foregroundStyle(.yellow)
            Text(
                verbatim: "Output: \(Int(canvasW))\u{00D7}\(Int(canvasH))"
            )
            .foregroundStyle(ViewerColors.canvas)

            if let doc = sourceFDLDoc,
               let src = doc.contexts.first?.canvases.first {
                Text(
                    verbatim: "Source: \(Int(src.dimensions.width))\u{00D7}\(Int(src.dimensions.height))"
                )
                .foregroundStyle(.white.opacity(0.6))
            }

            if let tpl = viewModel.selectedTemplate {
                Text(tpl.name)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white.opacity(0.8))
        .padding(8)
        .background(
            .black.opacity(0.65),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .padding(8)
        .frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    // MARK: - Data Loading

    private func loadSourceFDL() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .data]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.message = "Select a Source FDL (.fdl or .json)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFDLFromURL(url)
    }

    private func loadFDLFromURL(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let doc = try JSONDecoder().decode(
                FDLDocument.self, from: data
            )
            sourceFDLDoc = doc
            sourceFileName = url.lastPathComponent
            errorMessage = nil
            applyTemplatePreview(doc: doc)
        } catch {
            errorMessage = "Invalid FDL: \(error.localizedDescription)"
        }
    }

    private func applyTemplatePreview(doc: FDLDocument) {
        guard let template = viewModel.selectedTemplate,
              let tplData = template.templateJSON.data(using: .utf8),
              let tplDict = try? JSONSerialization.jsonObject(
                  with: tplData
              ) as? [String: Any]
        else { return }

        var config = CanvasTemplateConfig()
        if let t = tplDict["target_dimensions"] as? [String: Any] {
            if let w = t["width"] as? Int { config.targetWidth = w }
            if let h = t["height"] as? Int { config.targetHeight = h }
        }
        if let fs = tplDict["fit_source"] as? String {
            config.fitSource = fs
        }
        if let fm = tplDict["fit_method"] as? String {
            config.fitMethod = fm
        }
        if let ah = tplDict["alignment_method_horizontal"] as? String {
            config.alignmentHorizontal = ah
        }
        if let av = tplDict["alignment_method_vertical"] as? String {
            config.alignmentVertical = av
        }
        if let pm = tplDict["pad_to_maximum"] as? Bool {
            config.padToMaximum = pm
        }
        if let mx = tplDict["maximum_dimensions"] as? [String: Any] {
            config.maximumWidth = mx["width"] as? Int
            config.maximumHeight = mx["height"] as? Int
        }
        if let r = tplDict["round"] as? [String: Any] {
            if let re = r["even"] as? String { config.roundEven = re }
            if let rm = r["mode"] as? String { config.roundMode = rm }
        }

        guard let ctx = doc.contexts.first,
              let canvas = ctx.canvases.first,
              let fd = canvas.framingDecisions.first else {
            previewGeometry = computeGeoLocally(from: doc)
            return
        }

        let sourceDims: (w: Double, h: Double) = {
            switch config.fitSource {
            case "canvas.dimensions":
                return (canvas.dimensions.width, canvas.dimensions.height)
            case "canvas.effective_dimensions":
                if let e = canvas.effectiveDimensions {
                    return (e.width, e.height)
                }
                return (canvas.dimensions.width, canvas.dimensions.height)
            case "framing_decision.protection_dimensions":
                if let p = fd.protectionDimensions {
                    return (p.width, p.height)
                }
                return (fd.dimensions.width, fd.dimensions.height)
            default:
                return (fd.dimensions.width, fd.dimensions.height)
            }
        }()

        let tw = Double(config.targetWidth)
        let th = Double(config.targetHeight)
        let sx = tw / max(sourceDims.w, 1)
        let sy = th / max(sourceDims.h, 1)
        let scale: Double = {
            switch config.fitMethod {
            case "fill": return max(sx, sy)
            case "width": return sx
            case "height": return sy
            default: return min(sx, sy)
            }
        }()

        func applyRound(_ val: Double) -> Double {
            let rounded: Double
            switch config.roundMode {
            case "down": rounded = floor(val)
            case "round": rounded = val.rounded()
            default: rounded = ceil(val)
            }
            if config.roundEven == "even" {
                let r = Int(rounded)
                return Double(r % 2 == 0 ? r : r + 1)
            }
            return rounded
        }

        let nfw = applyRound(fd.dimensions.width * scale)
        let nfh = applyRound(fd.dimensions.height * scale)
        var ncw = tw
        var nch = th

        if let mw = config.maximumWidth, let mh = config.maximumHeight {
            ncw = min(ncw, Double(mw))
            nch = min(nch, Double(mh))
            if config.padToMaximum {
                ncw = Double(mw); nch = Double(mh)
            }
        }

        var newProtW: Double?
        var newProtH: Double?
        if let p = fd.protectionDimensions {
            newProtW = applyRound(p.width * scale)
            newProtH = applyRound(p.height * scale)
        }

        var effectiveRect: GeometryRect?
        if let e = canvas.effectiveDimensions {
            let ew = applyRound(e.width * scale)
            let eh = applyRound(e.height * scale)
            let ea = anchor(ew, eh, cw: ncw, ch: nch, config: config)
            effectiveRect = GeometryRect(
                x: ea.x, y: ea.y, width: ew, height: eh
            )
        }

        let fa = anchor(nfw, nfh, cw: ncw, ch: nch, config: config)
        let framingRect = GeometryRect(
            x: fa.x, y: fa.y, width: nfw, height: nfh
        )

        var protRect: GeometryRect?
        if let pw = newProtW, let ph = newProtH {
            let pa = anchor(pw, ph, cw: ncw, ch: nch, config: config)
            protRect = GeometryRect(
                x: pa.x, y: pa.y, width: pw, height: ph
            )
        }

        let outCanvas = ComputedCanvas(
            label: "Output",
            canvasRect: GeometryRect(
                x: 0, y: 0, width: ncw, height: nch
            ),
            effectiveRect: effectiveRect,
            framingDecisions: [
                ComputedFramingDecision(
                    label: fd.label ?? "FD",
                    framingIntent: "",
                    framingRect: framingRect,
                    protectionRect: protRect,
                    anchorPoint: GeometryPoint(x: fa.x, y: fa.y)
                ),
            ]
        )
        previewGeometry = ComputedGeometry(contexts: [
            ComputedContext(label: "Output", canvases: [outCanvas]),
        ])
    }

    private func anchor(
        _ ow: Double, _ oh: Double,
        cw: Double, ch: Double,
        config: CanvasTemplateConfig
    ) -> (x: Double, y: Double) {
        let x: Double
        switch config.alignmentHorizontal {
        case "left": x = 0
        case "right": x = cw - ow
        default: x = (cw - ow) / 2
        }
        let y: Double
        switch config.alignmentVertical {
        case "top": y = 0
        case "bottom": y = ch - oh
        default: y = (ch - oh) / 2
        }
        return (x, y)
    }

    private func computeGeoLocally(
        from doc: FDLDocument
    ) -> ComputedGeometry {
        let contexts = doc.contexts.map { ctx in
            let canvases = ctx.canvases.map { canvas in
                let cw = canvas.dimensions.width
                let ch = canvas.dimensions.height
                let fds = canvas.framingDecisions.map { fd in
                    let fx: Double
                    let fy: Double
                    if let a = fd.anchorPoint {
                        fx = a.x; fy = a.y
                    } else {
                        fx = (cw - fd.dimensions.width) / 2
                        fy = (ch - fd.dimensions.height) / 2
                    }
                    var protRect: GeometryRect?
                    if let p = fd.protectionDimensions {
                        let px: Double
                        let py: Double
                        if let pa = fd.protectionAnchorPoint {
                            px = pa.x; py = pa.y
                        } else {
                            px = (cw - p.width) / 2
                            py = (ch - p.height) / 2
                        }
                        protRect = GeometryRect(
                            x: px, y: py,
                            width: p.width, height: p.height
                        )
                    }
                    return ComputedFramingDecision(
                        label: fd.label ?? fd.id,
                        framingIntent: "",
                        framingRect: GeometryRect(
                            x: fx, y: fy,
                            width: fd.dimensions.width,
                            height: fd.dimensions.height
                        ),
                        protectionRect: protRect,
                        anchorPoint: fd.anchorPoint.map {
                            GeometryPoint(x: $0.x, y: $0.y)
                        }
                    )
                }
                var effectiveRect: GeometryRect?
                if let e = canvas.effectiveDimensions {
                    let ex: Double
                    let ey: Double
                    if let a = canvas.effectiveAnchorPoint {
                        ex = a.x; ey = a.y
                    } else {
                        ex = (cw - e.width) / 2
                        ey = (ch - e.height) / 2
                    }
                    effectiveRect = GeometryRect(
                        x: ex, y: ey,
                        width: e.width, height: e.height
                    )
                }
                return ComputedCanvas(
                    label: canvas.label,
                    canvasRect: GeometryRect(
                        x: 0, y: 0, width: cw, height: ch
                    ),
                    effectiveRect: effectiveRect,
                    framingDecisions: fds
                )
            }
            return ComputedContext(label: ctx.label, canvases: canvases)
        }
        return ComputedGeometry(contexts: contexts)
    }
}
