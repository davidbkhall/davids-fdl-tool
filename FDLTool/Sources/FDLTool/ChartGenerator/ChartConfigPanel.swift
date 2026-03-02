import SwiftUI

/// Left panel: camera picker, recording mode, frameline management.
struct ChartConfigPanel: View {
    @ObservedObject var viewModel: ChartGeneratorViewModel
    @ObservedObject var cameraDB: CameraDBStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Chart title
                GroupBox("Chart Title") {
                    TextField("Title", text: $viewModel.chartTitle)
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 2)
                }

                // Camera & Mode
                GroupBox("Camera & Mode") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use custom canvas", isOn: $viewModel.useCustomCanvas)
                            .font(.caption)

                        if viewModel.useCustomCanvas {
                            customCanvasFields
                        } else {
                            CameraPickerView(
                                cameraDB: cameraDB,
                                selectedCameraID: $viewModel.selectedCameraID,
                                selectedModeID: $viewModel.selectedModeID
                            )
                        }

                        // Canvas summary
                        canvasSummary
                    }
                    .padding(.vertical, 4)
                }

                // Framelines
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Framelines")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            addFramelineMenu
                        }

                        if viewModel.framelines.isEmpty {
                            Text("No framelines. Add from presets or create custom.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(viewModel.framelines.enumerated()), id: \.element.id) { index, frameline in
                                FramelineRow(
                                    frameline: Binding(
                                        get: { viewModel.framelines[index] },
                                        set: { viewModel.framelines[index] = $0 }
                                    ),
                                    onDelete: { viewModel.removeFrameline(frameline) }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text("Framing Intents")
                }

                // Options
                GroupBox("Options") {
                    Toggle("Show labels on chart", isOn: $viewModel.showLabels)
                        .font(.caption)
                        .padding(.vertical, 2)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var customCanvasFields: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Width")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("W", value: $viewModel.customCanvasWidth, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            Text("\u{00D7}")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Height")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("H", value: $viewModel.customCanvasHeight, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
        }
    }

    @ViewBuilder
    private var canvasSummary: some View {
        let w = viewModel.canvasWidth
        let h = viewModel.canvasHeight
        if w > 0 && h > 0 {
            HStack(spacing: 6) {
                Text("Canvas:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(w)) \u{00D7} \(Int(h))")
                    .font(.system(.caption, design: .monospaced))
                AspectRatioLabel(width: w, height: h)
            }
        }
    }

    private var addFramelineMenu: some View {
        Menu {
            Section("Presets") {
                ForEach(commonPresets) { preset in
                    Button(preset.label) {
                        viewModel.addPreset(preset)
                    }
                }
            }
            Divider()
            Button("Custom...") {
                viewModel.addFrameline(label: "Custom")
            }
        } label: {
            Label("Add", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - Frameline Row

struct FramelineRow: View {
    @Binding var frameline: Frameline
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: frameline.color) ?? .gray)
                    .frame(width: 10, height: 10)

                TextField("Label", text: $frameline.label)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .frame(maxWidth: 120)

                Spacer()

                Text(frameline.aspectRatioDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.7))
            }

            HStack(spacing: 4) {
                TextField("W", value: $frameline.width, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .font(.caption)
                Text("\u{00D7}")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("H", value: $frameline.height, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .font(.caption)
                Spacer()
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Color(hex:) Extension

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
