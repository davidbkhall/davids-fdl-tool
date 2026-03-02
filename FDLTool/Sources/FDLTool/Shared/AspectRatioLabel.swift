import SwiftUI

/// Displays an aspect ratio computed from width and height.
struct AspectRatioLabel: View {
    let width: Double
    let height: Double

    var body: some View {
        Text(aspectRatioString)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
    }

    private var aspectRatioString: String {
        guard height > 0 else { return "N/A" }
        let ratio = width / height

        // Check common ratios
        let knownRatios: [(Double, String)] = [
            (16.0/9.0, "16:9"),
            (1.85, "1.85:1"),
            (2.39, "2.39:1"),
            (2.35, "2.35:1"),
            (1.78, "1.78:1"),
            (1.33, "4:3"),
            (1.0, "1:1"),
            (3.0/2.0, "3:2"),
            (2.0, "2:1"),
            (1.9, "1.9:1"),
        ]

        for (value, label) in knownRatios {
            if abs(ratio - value) < 0.02 {
                return label
            }
        }

        return String(format: "%.2f:1", ratio)
    }
}
