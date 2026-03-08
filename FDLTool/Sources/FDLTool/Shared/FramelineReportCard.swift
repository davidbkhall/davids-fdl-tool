import SwiftUI

struct FramelineReportCard: View {
    let report: FramelineConversionReport
    let onCopy: () -> Void
    let onExport: () -> Void
    let onSave: (() -> Void)?
    let saveTitle: String

    @State private var showMappings = false
    @State private var showDropped = false
    @State private var showWarnings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.title)
                .font(.caption.weight(.semibold))
            Text(report.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                statusPill(
                    title: report.lossy ? "Lossy" : "Lossless",
                    color: report.lossy ? .orange : .green
                )
                statusPill(
                    title: "\(report.validationErrorCount)E / \(report.validationWarningCount)W",
                    color: report.validationErrorCount == 0 ? .green : .orange
                )
                statusPill(
                    title: "\(report.mappingDetails.count) mappings",
                    color: .blue
                )
            }

            Text("Mapped fields: \(report.mappedFields.joined(separator: ", "))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !report.mappingDetails.isEmpty {
                DisclosureGroup("Mapping Details", isExpanded: $showMappings) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(report.mappingDetails.prefix(20)) { detail in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(detail.sourceField) -> \(detail.targetField)")
                                        .font(.caption2.weight(.medium))
                                    Text("\(detail.sourceValue ?? "n/a") -> \(detail.targetValue ?? "n/a")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    if let note = detail.note, !note.isEmpty {
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
                .font(.caption2)
            }

            if !report.droppedFields.isEmpty {
                DisclosureGroup("Dropped Fields (\(report.droppedFields.count))", isExpanded: $showDropped) {
                    Text(report.droppedFields.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                .font(.caption2)
            }

            if !report.warnings.isEmpty {
                DisclosureGroup("Warnings (\(report.warnings.count))", isExpanded: $showWarnings) {
                    Text(report.warnings.joined(separator: " | "))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                .font(.caption2)
            }

            HStack(spacing: 6) {
                Button("Copy Report", action: onCopy)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Export Report JSON", action: onExport)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if let onSave {
                    Button(saveTitle, action: onSave)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}
