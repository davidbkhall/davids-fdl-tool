import SwiftUI

/// Export options sheet for the framing chart.
struct ChartExportSheet: View {
    @ObservedObject var viewModel: ChartGeneratorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .svg
    @State private var pngDPI: Int = 150

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Framing Chart")
                .font(.headline)

            // Format picker
            ExportFormatPicker(selectedFormat: $selectedFormat)

            // Format-specific options
            switch selectedFormat {
            case .png:
                HStack {
                    Text("DPI")
                        .foregroundStyle(.secondary)
                    Picker("DPI", selection: $pngDPI) {
                        Text("72").tag(72)
                        Text("150").tag(150)
                        Text("300").tag(300)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            case .svg:
                Text("Exports as scalable vector graphics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .json:
                Text("Exports as an ASC FDL JSON document.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Summary
            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("Canvas")
                            .foregroundStyle(.secondary)
                        Text(verbatim: "\(Int(viewModel.canvasWidth)) \u{00D7} \(Int(viewModel.canvasHeight))")
                    }
                    GridRow {
                        Text("Framelines")
                            .foregroundStyle(.secondary)
                        Text("\(viewModel.framelines.count)")
                    }
                    if let camera = viewModel.selectedCamera {
                        GridRow {
                            Text("Camera")
                                .foregroundStyle(.secondary)
                            Text("\(camera.manufacturer) \(camera.model)")
                        }
                    }
                }
                .font(.caption)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Export") {
                    performExport()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private func performExport() {
        switch selectedFormat {
        case .svg:
            viewModel.exportSVG()
        case .png:
            viewModel.exportPNG(dpi: pngDPI)
        case .json:
            viewModel.exportFDL()
        }
    }
}

/// Sheet for saving the generated FDL to a library project.
struct SaveToLibrarySheet: View {
    @ObservedObject var viewModel: ChartGeneratorViewModel
    let projects: [Project]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProjectID: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Save to Library")
                .font(.headline)

            if projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No projects available.")
                        .foregroundStyle(.secondary)
                    Text("Create a project in the Library first.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            } else {
                Text("Select a project:")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                List(projects, selection: $selectedProjectID) { project in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.body)
                        if let desc = project.description {
                            Text(desc)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(project.id)
                    .padding(.vertical, 2)
                }
                .listStyle(.inset)
                .frame(height: 200)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    if let projectID = selectedProjectID {
                        viewModel.saveToLibrary(projectID: projectID)
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
