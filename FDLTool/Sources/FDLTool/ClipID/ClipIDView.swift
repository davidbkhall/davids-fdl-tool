import SwiftUI

struct ClipIDView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        let vm = appState.clipIDViewModel

        VStack(spacing: 0) {
            // Toolbar
            toolbar(vm: vm)
            Divider()

            // Progress bar
            ClipBatchProgressView(
                isScanning: vm.isScanning,
                isGenerating: vm.isGenerating,
                generationProgress: vm.generationProgress,
                clipCount: vm.clips.count,
                generatedCount: vm.generatedFDLs.count,
                errorCount: vm.scanErrors.count
            )
            Divider()

            if vm.clips.isEmpty && !vm.isScanning {
                emptyState(vm: vm)
            } else {
                HSplitView {
                    // Left: Clip table
                    clipTable(vm: vm)
                        .frame(minWidth: 400, idealWidth: 500)

                    // Right: Detail + Validation
                    rightPane(vm: vm)
                        .frame(minWidth: 300, idealWidth: 400)
                }
            }
        }
        .navigationTitle("Clip ID")
        .sheet(isPresented: $appState.clipIDViewModel.showTemplateSelector) {
            TemplateSelectionSheet(viewModel: vm)
        }
        .sheet(isPresented: $appState.clipIDViewModel.showSaveToLibrary) {
            ClipSaveToLibrarySheet(
                viewModel: vm,
                projects: appState.libraryViewModel.projects
            )
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private func toolbar(vm: ClipIDViewModel) -> some View {
        HStack(spacing: 12) {
            Text("Clip ID Parser")
                .font(.title2)

            Spacer()

            if !vm.clips.isEmpty {
                // Batch actions
                Button(action: { vm.showTemplateSelector = true }) {
                    Label("Template", systemImage: "rectangle.3.group")
                }

                Button(action: { vm.generateFDLsForAllClips() }) {
                    Label("Generate FDLs", systemImage: "doc.badge.gearshape")
                }
                .disabled(vm.clips.isEmpty || vm.isGenerating)

                if !vm.generatedFDLs.isEmpty {
                    Button(action: { vm.validateAllClips() }) {
                        Label("Validate", systemImage: "checkmark.shield")
                    }
                    .disabled(vm.isValidating)

                    Button(action: { vm.exportAllFDLs() }) {
                        Label("Export FDLs", systemImage: "square.and.arrow.up")
                    }

                    Button(action: { vm.showSaveToLibrary = true }) {
                        Label("Save to Library", systemImage: "folder.badge.plus")
                    }
                }

                Divider()
                    .frame(height: 20)
            }

            Toggle("Recursive", isOn: $appState.clipIDViewModel.scanRecursive)
                .toggleStyle(.checkbox)
                .font(.caption)

            Button("Select Directory...") {
                vm.selectDirectory()
            }

            if vm.selectedDirectory != nil {
                Button(action: { vm.scanDirectory() }) {
                    Label("Scan", systemImage: "arrow.clockwise")
                }
                .disabled(vm.isScanning)
            }

            Button("Add Files...") {
                vm.probeSingleFile()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    @ViewBuilder
    private func emptyState(vm: ClipIDViewModel) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Select a directory to scan for video clips")
                .foregroundStyle(.secondary)

            if let dir = vm.selectedDirectory {
                Text(dir.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button("Scan Now") { vm.scanDirectory() }
            } else {
                Text("Use \"Select Directory\" or \"Add Files\" to get started.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Clip Table

    @ViewBuilder
    private func clipTable(vm: ClipIDViewModel) -> some View {
        VStack(spacing: 0) {
            // Directory path + summary
            if let dir = vm.selectedDirectory {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(dir.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(vm.formattedDuration(vm.totalClipDuration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(vm.formattedFileSize(vm.totalFileSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.bar)
                Divider()
            }

            // The table
            Table(vm.clips, selection: Binding(
                get: { vm.selectedClip?.filePath },
                set: { newID in
                    vm.selectedClip = vm.clips.first { $0.filePath == newID }
                }
            )) {
                TableColumn("File") { clip in
                    Text(clip.fileName)
                        .font(.caption)
                        .lineLimit(1)
                }
                .width(min: 120, ideal: 200)

                TableColumn("Resolution") { clip in
                    HStack(spacing: 4) {
                        Text("\(clip.width)\u{00D7}\(clip.height)")
                            .font(.system(.caption, design: .monospaced))
                        AspectRatioLabel(width: Double(clip.width), height: Double(clip.height))
                    }
                }
                .width(min: 100, ideal: 140)

                TableColumn("Codec") { clip in
                    Text(clip.codec)
                        .font(.caption)
                }
                .width(min: 50, ideal: 70)

                TableColumn("FPS") { clip in
                    Text(String(format: "%.2f", clip.fps))
                        .font(.system(.caption, design: .monospaced))
                }
                .width(min: 50, ideal: 60)

                TableColumn("Duration") { clip in
                    Text(vm.formattedDuration(clip.duration))
                        .font(.system(.caption, design: .monospaced))
                }
                .width(min: 50, ideal: 70)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            // Errors
            if !vm.scanErrors.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(vm.scanErrors.enumerated()), id: \.offset) { _, err in
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption2)
                                Text(URL(fileURLWithPath: err.filePath).lastPathComponent)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                Text(err.error)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 80)
                .background(.orange.opacity(0.05))
            }
        }
    }

    // MARK: - Right Pane

    @ViewBuilder
    private func rightPane(vm: ClipIDViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Selected clip detail
                if let clip = vm.selectedClip {
                    clipDetail(clip)
                }

                // Template status
                templateStatus(vm: vm)

                // Validation results
                if !vm.validationResults.isEmpty {
                    ClipValidationView(results: vm.validationResults)
                }

                // Generated FDLs summary
                if !vm.generatedFDLs.isEmpty {
                    generatedFDLsSummary(vm: vm)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func clipDetail(_ clip: ClipInfo) -> some View {
        GroupBox("Selected Clip") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("File").foregroundStyle(.secondary)
                    Text(clip.fileName).textSelection(.enabled)
                }
                GridRow {
                    Text("Path").foregroundStyle(.secondary)
                    Text(clip.filePath)
                        .font(.caption2)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
                GridRow {
                    Text("Resolution").foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("\(clip.width) \u{00D7} \(clip.height)")
                        AspectRatioLabel(width: Double(clip.width), height: Double(clip.height))
                    }
                }
                GridRow {
                    Text("Codec").foregroundStyle(.secondary)
                    Text(clip.codec)
                }
                GridRow {
                    Text("Frame Rate").foregroundStyle(.secondary)
                    Text(String(format: "%.3f fps", clip.fps))
                }
                GridRow {
                    Text("Duration").foregroundStyle(.secondary)
                    Text(String(format: "%.3f sec", clip.duration))
                }
                if let size = clip.fileSize, size > 0 {
                    GridRow {
                        Text("Size").foregroundStyle(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                }
            }
            .font(.caption)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func templateStatus(vm: ClipIDViewModel) -> some View {
        GroupBox("FDL Template") {
            VStack(alignment: .leading, spacing: 6) {
                if vm.templateFDLJSON != nil {
                    HStack {
                        Label("Template loaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Clear") { vm.templateFDLJSON = nil }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                } else {
                    Text("No template selected. Generated FDLs will have canvas only, no framing decisions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Select Template...") { vm.showTemplateSelector = true }
                    .font(.caption)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func generatedFDLsSummary(vm: ClipIDViewModel) -> some View {
        GroupBox("Generated FDLs") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(vm.generatedFDLs.count) FDL\(vm.generatedFDLs.count == 1 ? "" : "s") generated")
                    .font(.caption)
                ForEach(vm.generatedFDLs.prefix(10)) { gen in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                        Text(gen.clipInfo.fileName)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        Text("\(gen.clipInfo.width)\u{00D7}\(gen.clipInfo.height)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                if vm.generatedFDLs.count > 10 {
                    Text("... and \(vm.generatedFDLs.count - 10) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Template Selection Sheet

struct TemplateSelectionSheet: View {
    @ObservedObject var viewModel: ClipIDViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var jsonText = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Select FDL Template")
                .font(.headline)

            Text("Paste FDL JSON to use as a template for framing decisions. "
                + "The canvas dimensions will be replaced by each clip's actual resolution.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $jsonText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color.secondary.opacity(0.3))

            HStack {
                Button("Load File...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.json]
                    if panel.runModal() == .OK, let url = panel.url,
                       let data = try? Data(contentsOf: url),
                       let str = String(data: data, encoding: .utf8) {
                        jsonText = str
                    }
                }

                Button("Clear Template") {
                    viewModel.templateFDLJSON = nil
                    dismiss()
                }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Use Template") {
                    viewModel.templateFDLJSON = jsonText
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 350)
        .onAppear {
            jsonText = viewModel.templateFDLJSON ?? ""
        }
    }
}

// MARK: - Save to Library Sheet

struct ClipSaveToLibrarySheet: View {
    @ObservedObject var viewModel: ClipIDViewModel
    let projects: [Project]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProjectID: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Save \(viewModel.generatedFDLs.count) FDLs to Library")
                .font(.headline)

            if projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No projects available. Create a project in the Library first.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()
            } else {
                List(projects, selection: $selectedProjectID) { project in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                        if let desc = project.description {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(project.id)
                }
                .listStyle(.inset)
                .frame(height: 200)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    if let id = selectedProjectID {
                        viewModel.saveToLibrary(projectID: id)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedProjectID == nil)
            }
        }
        .padding()
        .frame(width: 400, height: 380)
    }
}
