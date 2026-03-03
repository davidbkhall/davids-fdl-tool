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
                                ForEach(Array(viewModel.editorPipeline.enumerated()), id: \.element.id) { index, _ in
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

/// Sheet for creating/editing an ASC FDL Canvas Template (spec-based fields).
struct ASCCanvasTemplateEditorSheet: View {
    @ObservedObject var viewModel: CanvasTemplateViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Canvas Template")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("General") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Label")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "Template Label",
                                    text: $viewModel.ascEditorConfig.label
                                )
                                .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Target Dimensions") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                LabeledContent("Width") {
                                    TextField(
                                        "W",
                                        value: $viewModel.ascEditorConfig.targetWidth,
                                        format: .number.grouping(.never)
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                }
                                LabeledContent("Height") {
                                    TextField(
                                        "H",
                                        value: $viewModel.ascEditorConfig.targetHeight,
                                        format: .number.grouping(.never)
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                }
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Fit") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker(
                                "Fit Source",
                                selection: $viewModel.ascEditorConfig.fitSource
                            ) {
                                ForEach(
                                    TemplatePresets.fitSourceOptions,
                                    id: \.value
                                ) { opt in
                                    Text(opt.label).tag(opt.value)
                                }
                            }
                            .font(.caption)

                            Picker(
                                "Fit Method",
                                selection: $viewModel.ascEditorConfig.fitMethod
                            ) {
                                ForEach(
                                    TemplatePresets.fitMethodOptions,
                                    id: \.value
                                ) { opt in
                                    Text(opt.label).tag(opt.value)
                                }
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Alignment") {
                        HStack(spacing: 8) {
                            Picker(
                                "Horizontal",
                                selection: $viewModel.ascEditorConfig.alignmentHorizontal
                            ) {
                                ForEach(
                                    TemplatePresets.alignmentHOptions,
                                    id: \.value
                                ) { opt in
                                    Text(opt.label).tag(opt.value)
                                }
                            }
                            .font(.caption)
                            Picker(
                                "Vertical",
                                selection: $viewModel.ascEditorConfig.alignmentVertical
                            ) {
                                ForEach(
                                    TemplatePresets.alignmentVOptions,
                                    id: \.value
                                ) { opt in
                                    Text(opt.label).tag(opt.value)
                                }
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Advanced") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maximum Dimensions")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                LabeledContent("Max W") {
                                    TextField(
                                        "Max W",
                                        value: $viewModel.ascEditorConfig.maximumWidth,
                                        format: .number.grouping(.never)
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                }
                                LabeledContent("Max H") {
                                    TextField(
                                        "Max H",
                                        value: $viewModel.ascEditorConfig.maximumHeight,
                                        format: .number.grouping(.never)
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                }
                            }
                            .font(.caption)

                            Toggle(
                                "Pad to Maximum",
                                isOn: $viewModel.ascEditorConfig.padToMaximum
                            )
                            .font(.caption)

                            Divider()

                            Text("Rounding")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)

                            Picker(
                                "Round To",
                                selection: $viewModel.ascEditorConfig.roundEven
                            ) {
                                ForEach(
                                    TemplatePresets.roundEvenOptions,
                                    id: \.value
                                ) { opt in
                                    Text(opt.label).tag(opt.value)
                                }
                            }
                            .font(.caption)

                            Picker(
                                "Mode",
                                selection: $viewModel.ascEditorConfig.roundMode
                            ) {
                                ForEach(
                                    TemplatePresets.roundModeOptions,
                                    id: \.value
                                ) { opt in
                                    Text(opt.label).tag(opt.value)
                                }
                            }
                            .font(.caption)

                            Divider()

                            Picker(
                                "Preserve from Source",
                                selection: Binding(
                                    get: {
                                        viewModel.ascEditorConfig
                                            .preserveFromSourceCanvas ?? ""
                                    },
                                    set: {
                                        viewModel.ascEditorConfig
                                            .preserveFromSourceCanvas =
                                            $0.isEmpty ? nil : $0
                                    }
                                )
                            ) {
                                Text("None").tag("")
                                Text("Framing Decision")
                                    .tag("framing_decision.dimensions")
                                Text("Protection")
                                    .tag(
                                        "framing_decision"
                                            + ".protection_dimensions"
                                    )
                                Text("Effective Canvas")
                                    .tag("canvas.effective_dimensions")
                                Text("Full Canvas")
                                    .tag("canvas.dimensions")
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    viewModel.saveASCTemplate()
                    dismiss()
                }
                .disabled(
                    viewModel.ascEditorConfig.label
                        .trimmingCharacters(in: .whitespaces).isEmpty
                )
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 500)
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
                            TextField("X", value: $step.scaleX, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        LabeledContent("Scale Y") {
                            TextField("Y", value: $step.scaleY, format: .number.grouping(.never))
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
                            TextField("X", value: $step.offsetX, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        LabeledContent("Offset Y") {
                            TextField("Y", value: $step.offsetY, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }
                    .font(.caption)

                case .crop:
                    HStack(spacing: 12) {
                        LabeledContent("Width") {
                            TextField("W", value: $step.cropWidth, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        LabeledContent("Height") {
                            TextField("H", value: $step.cropHeight, format: .number.grouping(.never))
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
