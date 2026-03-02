import SwiftUI

/// Preview template applied to an FDL — shows step-by-step pipeline results.
struct CanvasTemplatePreviewView: View {
    let template: CanvasTemplate
    let steps: [PreviewStep]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Template Preview: \(template.name)")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            if steps.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No preview data available")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            StepPreviewRow(step: step, isFirst: index == 0, isLast: index == steps.count - 1)

                            if index < steps.count - 1 {
                                Image(systemName: "arrow.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

struct StepPreviewRow: View {
    let step: PreviewStep
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Step label
            VStack(alignment: .trailing, spacing: 2) {
                Text(step.stepName.capitalized)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isFirst ? .secondary : .primary)
                Text(step.stepType)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 80, alignment: .trailing)

            // Input dimensions (if not first step)
            if let inW = step.inputWidth, let inH = step.inputHeight {
                VStack(spacing: 2) {
                    Text("Input")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    dimensionBox(width: inW, height: inH, color: .blue.opacity(0.1))
                }
            }

            if step.inputWidth != nil {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Output dimensions
            VStack(spacing: 2) {
                Text(isFirst ? "Dimensions" : "Output")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                dimensionBox(
                    width: step.outputWidth,
                    height: step.outputHeight,
                    color: isLast ? .green.opacity(0.15) : .gray.opacity(0.1)
                )
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dimensionBox(width: Double, height: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(formatDimension(width, height))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
            AspectRatioLabel(width: width, height: height)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color, in: RoundedRectangle(cornerRadius: 6))
    }

    private func formatDimension(_ w: Double, _ h: Double) -> String {
        if w == w.rounded() && h == h.rounded() {
            return "\(Int(w)) \u{00D7} \(Int(h))"
        }
        return String(format: "%.2f \u{00D7} %.2f", w, h)
    }
}
