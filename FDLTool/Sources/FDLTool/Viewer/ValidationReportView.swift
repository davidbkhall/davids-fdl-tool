import SwiftUI

/// Displays FDL validation results with errors and warnings.
struct ValidationReportView: View {
    let result: ValidationResult

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    statusBadge
                    Text("Validation")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if !result.errors.isEmpty || !result.warnings.isEmpty {
                        Text("\(result.errors.count) error(s), \(result.warnings.count) warning(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !result.errors.isEmpty {
                    ForEach(result.errors) { error in
                        ValidationMessageRow(message: error)
                    }
                }

                if !result.warnings.isEmpty {
                    ForEach(result.warnings) { warning in
                        ValidationMessageRow(message: warning)
                    }
                }

                if result.valid && result.errors.isEmpty && result.warnings.isEmpty {
                    Label("Document is valid", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if result.valid {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

struct ValidationMessageRow: View {
    let message: ValidationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.caption)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(message.message)
                    .font(.caption)

                if !message.path.isEmpty {
                    Text(message.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fontDesign(.monospaced)
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 4))
    }

    private var iconName: String {
        switch message.severity {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        switch message.severity {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    private var backgroundColor: Color {
        switch message.severity {
        case .error: return .red.opacity(0.08)
        case .warning: return .orange.opacity(0.08)
        case .info: return .blue.opacity(0.08)
        }
    }
}
