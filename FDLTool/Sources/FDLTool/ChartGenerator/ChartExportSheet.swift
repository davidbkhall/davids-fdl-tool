import SwiftUI

/// Export options sheet for the framing chart.
struct ChartExportSheet: View {
    @ObservedObject var viewModel: ChartGeneratorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .svg
    @State private var printSafeMarginPercent: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Framing Chart")
                .font(.headline)

            HStack(alignment: .center, spacing: 8) {
                Text("Format")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 52, alignment: .leading)
                ExportFormatPicker(selectedFormat: $selectedFormat, options: availableFormats, compactMenuStyle: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Format-specific options
            switch selectedFormat {
            case .png:
                Text("Exports high-quality raster output with automatic DPI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .tiff:
                Text("Exports production TIFF with automatic DPI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .svg:
                Text("Exports as scalable vector graphics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .pdf:
                Text("Exports as vector PDF for print and sharing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .arriXML:
                Text("Exports the generated chart FDL as ARRI frameline XML.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .sonyXML:
                Text("Exports the generated chart FDL as Sony frameline XML.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .json:
                Text("Exports as an ASC FDL document with a .fdl extension.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                    let format = selectedFormat
                    let margin = printSafeMarginPercent
                    dismiss()
                    // Launch save panel after this modal sheet closes.
                    DispatchQueue.main.async {
                        performExport(format: format, printSafeMarginPercent: margin)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear {
            if !availableFormats.contains(selectedFormat) {
                selectedFormat = .svg
            }
        }
    }

    private func performExport(format: ExportFormat, printSafeMarginPercent: Double) {
        switch format {
        case .svg:
            viewModel.exportSVG(printSafeMarginPercent: printSafeMarginPercent)
        case .png:
            viewModel.exportPNG(printSafeMarginPercent: printSafeMarginPercent)
        case .tiff:
            viewModel.exportTIFF(printSafeMarginPercent: printSafeMarginPercent)
        case .pdf:
            viewModel.exportPDF(printSafeMarginPercent: printSafeMarginPercent)
        case .arriXML:
            viewModel.exportArriXML()
        case .sonyXML:
            viewModel.exportSonyXML()
        case .json:
            viewModel.exportFDL()
        }
    }

    private var availableFormats: [ExportFormat] {
        var formats: [ExportFormat] = [.json, .svg, .png, .pdf, .tiff]
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
        switch selectedFormat {
        case .pdf:
            return true
        default:
            return false
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
