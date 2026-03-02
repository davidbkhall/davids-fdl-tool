import SwiftUI

struct ProjectCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    let onCreate: (String, String?) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Project")
                .font(.headline)

            Form {
                TextField("Project Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Description (optional)", text: $description, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    onCreate(name, description.isEmpty ? nil : description)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
