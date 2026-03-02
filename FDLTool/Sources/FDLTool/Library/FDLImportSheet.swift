import SwiftUI

struct FDLImportSheet: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Add FDL to Project")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }

            FDLImportOrManualToggle(mode: $viewModel.importMode)

            if viewModel.importMode == .importJSON {
                importJSONView
            } else {
                manualEntryView
            }
        }
        .padding()
        .frame(minWidth: 550, minHeight: 500)
    }

    @ViewBuilder
    private var importJSONView: some View {
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
                viewModel.importFDLFromJSON()
            }
            .disabled(viewModel.importJSONText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || viewModel.isImporting)
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var manualEntryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Section {
                    TextField("FDL Name", text: $viewModel.manualName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Description (optional)", text: $viewModel.manualDescription)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("General")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                GeometryEditorView(
                    canvasWidth: $viewModel.manualCanvasWidth,
                    canvasHeight: $viewModel.manualCanvasHeight,
                    effectiveWidth: $viewModel.manualEffectiveWidth,
                    effectiveHeight: $viewModel.manualEffectiveHeight,
                    effectiveAnchorX: $viewModel.manualEffectiveAnchorX,
                    effectiveAnchorY: $viewModel.manualEffectiveAnchorY,
                    photositeWidth: $viewModel.manualPhotositeWidth,
                    photositeHeight: $viewModel.manualPhotositeHeight,
                    photositeAnchorX: $viewModel.manualPhotositeAnchorX,
                    photositeAnchorY: $viewModel.manualPhotositeAnchorY
                )
            }
            .padding(.horizontal, 4)
        }

        HStack {
            if viewModel.isImporting {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Button("Create FDL") {
                viewModel.importFDLFromManualEntry()
            }
            .disabled(viewModel.manualCanvasWidth <= 0 || viewModel.manualCanvasHeight <= 0 || viewModel.isImporting)
            .keyboardShortcut(.defaultAction)
        }
    }
}
