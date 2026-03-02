import SwiftUI

/// Reusable field for entering width x height dimensions.
struct DimensionsField: View {
    let label: String
    @Binding var width: Double
    @Binding var height: Double
    var unit: String = "px"

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField("W", value: $width, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text("\u{00D7}")
                    .foregroundStyle(.secondary)
                TextField("H", value: $height, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}
