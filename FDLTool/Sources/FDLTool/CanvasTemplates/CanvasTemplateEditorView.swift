import SwiftUI

/// Create or edit a canvas template via UI form.
struct CanvasTemplateEditorView: View {
    @ObservedObject var viewModel: CanvasTemplateViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(viewModel.editingTemplate == nil ? "New Canvas Template" : "Edit Canvas Template")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Name & description
                    GroupBox("General") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Template Name", text: $viewModel.editorName)
                                .textFieldStyle(.roundedBorder)
                            TextField("Description (optional)", text: $viewModel.editorDescription)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 4)
                    }

                    // Pipeline steps
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Pipeline Steps")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                addStepMenu
                            }

                            if viewModel.editorPipeline.isEmpty {
                                Text("No pipeline steps. Add steps using the + button above.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(Array(viewModel.editorPipeline.enumerated()), id: \.element.id) { index, step in
                                    PipelineStepEditor(
                                        step: Binding(
                                            get: { viewModel.editorPipeline[index] },
                                            set: { viewModel.editorPipeline[index] = $0 }
                                        ),
                                        onDelete: { viewModel.removePipelineStep(at: index) },
                                        stepNumber: index + 1
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Text("Pipeline")
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save") {
                    viewModel.saveTemplate()
                    dismiss()
                }
                .disabled(viewModel.editorName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 450)
    }

    private var addStepMenu: some View {
        Menu {
            ForEach(PipelineStepType.allCases) { stepType in
                Button(action: { viewModel.addPipelineStep(stepType) }) {
                    Label(stepType.label, systemImage: stepType.systemImage)
                }
            }
        } label: {
            Label("Add Step", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
    }
}

/// Editor for a single pipeline step
struct PipelineStepEditor: View {
    @Binding var step: PipelineStep
    let onDelete: () -> Void
    let stepNumber: Int

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(step.type.label, systemImage: step.type.systemImage)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("Step \(stepNumber)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }

                switch step.type {
                case .normalize:
                    Text("Normalizes dimensions to unit scale based on larger axis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .scale:
                    HStack(spacing: 12) {
                        LabeledContent("Scale X") {
                            TextField("X", value: $step.scaleX, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        LabeledContent("Scale Y") {
                            TextField("Y", value: $step.scaleY, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                    .font(.caption)

                case .round:
                    Picker("Strategy", selection: $step.roundStrategy) {
                        Text("Nearest").tag("nearest")
                        Text("Floor").tag("floor")
                        Text("Ceil").tag("ceil")
                        Text("Even").tag("even")
                    }
                    .pickerStyle(.segmented)
                    .font(.caption)

                case .offset:
                    HStack(spacing: 12) {
                        LabeledContent("Offset X") {
                            TextField("X", value: $step.offsetX, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        LabeledContent("Offset Y") {
                            TextField("Y", value: $step.offsetY, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                    .font(.caption)

                case .crop:
                    HStack(spacing: 12) {
                        LabeledContent("Width") {
                            TextField("W", value: $step.cropWidth, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        LabeledContent("Height") {
                            TextField("H", value: $step.cropHeight, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
