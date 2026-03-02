import SwiftUI

/// Text editor with paste/load JSON support, live validation badge, and error list.
struct JSONImportValidatorView: View {
    @Binding var jsonText: String
    let validationResult: ValidationResult?
    let onValidate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("JSON Input")
                    .font(.headline)
                Spacer()
                if let result = validationResult {
                    validationBadge(result)
                }
                Button("Validate") {
                    onValidate()
                }
                .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .border(Color.secondary.opacity(0.3))
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleFileDrop(providers: providers)
                    return true
                }

            if let result = validationResult, !result.errors.isEmpty || !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.errors) { error in
                        Label(error.message, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    ForEach(result.warnings) { warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }

            HStack {
                Button("Load File...") {
                    loadFile()
                }
                Button("Paste from Clipboard") {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        jsonText = string
                    }
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func validationBadge(_ result: ValidationResult) -> some View {
        if result.valid {
            Label("Valid", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else {
            Label("\(result.errors.count) error(s)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    private func loadFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url),
               let string = String(data: data, encoding: .utf8) {
                jsonText = string
            }
        }
    }

    private func handleFileDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   let contents = try? String(contentsOf: url, encoding: .utf8) {
                    DispatchQueue.main.async {
                        jsonText = contents
                    }
                }
            }
        }
    }
}
