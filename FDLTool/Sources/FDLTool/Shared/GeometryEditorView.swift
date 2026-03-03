import SwiftUI

/// Reusable editor for FDL geometry: dimensions (4 layers) and anchors (3 points).
struct GeometryEditorView: View {
    @Binding var canvasWidth: Double
    @Binding var canvasHeight: Double
    @Binding var effectiveWidth: Double
    @Binding var effectiveHeight: Double
    @Binding var effectiveAnchorX: Double
    @Binding var effectiveAnchorY: Double
    @Binding var photositeWidth: Double
    @Binding var photositeHeight: Double
    @Binding var photositeAnchorX: Double
    @Binding var photositeAnchorY: Double

    var body: some View {
        Form {
            Section("Canvas Dimensions") {
                DimensionsField(label: "Canvas", width: $canvasWidth, height: $canvasHeight)
                AspectRatioLabel(width: canvasWidth, height: canvasHeight)
            }

            Section("Effective Dimensions") {
                DimensionsField(label: "Effective", width: $effectiveWidth, height: $effectiveHeight)
                HStack {
                    Text("Anchor")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("X", value: $effectiveAnchorX, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    TextField("Y", value: $effectiveAnchorY, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }

            Section("Photosite Dimensions") {
                DimensionsField(label: "Photosites", width: $photositeWidth, height: $photositeHeight)
                HStack {
                    Text("Anchor")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("X", value: $photositeAnchorX, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    TextField("Y", value: $photositeAnchorY, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
        }
        .formStyle(.grouped)
    }
}
