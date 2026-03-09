import SwiftUI

/// Export options sheet for the framing chart.
struct ChartExportSheet: View {
    @ObservedObject var viewModel: ChartGeneratorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormats: Set<ExportFormat> = [.tiff]
    @State private var printSafeMarginPercent: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Framing Chart")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Export one or more formats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 8),
                ], spacing: 6) {
                    ForEach(availableFormats) { format in
                        Button {
                            if selectedFormats.contains(format) {
                                selectedFormats.remove(format)
                            } else {
                                selectedFormats.insert(format)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: selectedFormats.contains(format) ? "checkmark.circle.fill" : "circle")
                                Text(format.rawValue)
                                    .lineLimit(1)
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedFormats.contains(format) ? .accentColor : .secondary)
                    }
                }
            }
            Text("FDL export uses ASC FDL JSON content with a .fdl extension.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if supportsPrintSafeOption {
                HStack(spacing: 8) {
                    Text("Print-safe margin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $printSafeMarginPercent, in: 0...15, step: 0.5)
                    Text("\(printSafeMarginPercent, specifier: "%.1f")%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 44, alignment: .trailing)
                }
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
                    let formats = Array(selectedFormats)
                    let margin = printSafeMarginPercent
                    viewModel.requestExport(formats: formats, printSafeMarginPercent: margin)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedFormats.isEmpty || availableFormats.isEmpty)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear {
            selectedFormats = Set(selectedFormats.filter { availableFormats.contains($0) })
            if selectedFormats.isEmpty {
                selectedFormats.insert(.tiff)
            }
        }
    }

    private var availableFormats: [ExportFormat] {
        var formats: [ExportFormat] = [.tiff, .png, .pdf, .svg, .json]
        guard let camera = viewModel.selectedCamera else { return formats }
        let manufacturer = camera.manufacturer.lowercased()
        if manufacturer.contains("arri") {
            formats.append(.arriXML)
        }
        if manufacturer.contains("sony") {
            formats.append(.sonyXML)
        }
        return formats
    }

    private var supportsPrintSafeOption: Bool {
        selectedFormats.contains(.pdf)
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
