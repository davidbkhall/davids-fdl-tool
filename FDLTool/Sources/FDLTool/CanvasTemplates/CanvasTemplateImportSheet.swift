import SwiftUI

/// Import a canvas template from JSON with validation.
struct CanvasTemplateImportSheet: View {
    @ObservedObject var viewModel: CanvasTemplateViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Import Canvas Template")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }

            JSONImportValidatorView(
                jsonText: $viewModel.importJSONText,
                validationResult: viewModel.importValidation,
                onValidate: { viewModel.validateImportJSON() }
            )

            HStack {
                if viewModel.isValidating {
                    ProgressView()
                        .controlSize(.small)
                    Text("Validating...")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import") {
                    viewModel.importTemplate()
                    dismiss()
                }
                .disabled(viewModel.importJSONText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
    }
}
