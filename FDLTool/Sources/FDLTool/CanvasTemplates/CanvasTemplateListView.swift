import SwiftUI

/// Browse and manage canvas templates.
struct CanvasTemplateListView: View {
    @ObservedObject var viewModel: CanvasTemplateViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Canvas Templates")
                    .font(.headline)
                Spacer()

                Menu {
                    Button("Custom") {
                        viewModel.beginNewASCTemplate(config: CanvasTemplateConfig())
                    }
                    Divider()
                    ForEach(TemplatePresets.all, id: \.name) { preset in
                        Button(preset.name) {
                            viewModel.beginNewASCTemplate(config: preset.config)
                        }
                    }
                    Divider()
                    Button("Import JSON...") {
                        viewModel.showImportSheet = true
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if viewModel.templates.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No templates yet")
                        .foregroundStyle(.secondary)
                    Text("Create or import a canvas template to get started.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { viewModel.selectedTemplate?.id },
                    set: { newID in
                        viewModel.selectedTemplate = viewModel.templates.first { $0.id == newID }
                    }
                )) {
                    ForEach(viewModel.templates) { template in
                        CanvasTemplateRow(template: template)
                            .tag(template.id)
                            .contextMenu {
                                Button("Edit") {
                                    viewModel.beginEditingASC(template)
                                }
                                Button("Export") {
                                    viewModel.exportTemplate(template)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    viewModel.deleteTemplate(template)
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $viewModel.showASCEditor) {
            ASCCanvasTemplateEditorSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showImportSheet) {
            CanvasTemplateImportSheet(viewModel: viewModel)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

struct CanvasTemplateRow: View {
    let template: CanvasTemplate

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(template.name)
                .font(.body)
                .lineLimit(1)

            if let desc = template.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let source = template.source {
                    Text(source)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.1), in: Capsule())
                }

                Text(verbatim: templateDimsSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var templateDimsSummary: String {
        guard let data = template.templateJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let target = dict["target_dimensions"] as? [String: Any],
              let w = target["width"] as? Int,
              let h = target["height"] as? Int else {
            return ""
        }
        let fit = (dict["fit_method"] as? String) ?? ""
        return "\(w)\u{00D7}\(h) \(fit)"
    }
}
