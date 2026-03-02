import SwiftUI

/// Table showing match/mismatch status for each clip vs FDL canvas.
struct ClipValidationView: View {
    let results: [ClipCanvasComparison]

    var matchCount: Int { results.filter(\.match).count }
    var mismatchCount: Int { results.filter { !$0.match }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Canvas Validation")
                    .font(.headline)
                Spacer()
                summaryBadge
            }

            if results.isEmpty {
                Text("No validation results. Generate FDLs first, then validate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                Table(results) {
                    TableColumn("Clip") { result in
                        Text(result.clipFileName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .width(min: 120, ideal: 180)

                    TableColumn("Canvas") { result in
                        Text("\(result.canvasWidth) \u{00D7} \(result.canvasHeight)")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Actual") { result in
                        Text("\(result.actualWidth) \u{00D7} \(result.actualHeight)")
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Status") { result in
                        HStack(spacing: 4) {
                            Image(systemName: result.match ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.match ? .green : .red)
                            Text(result.match ? "Match" : "Mismatch")
                                .font(.caption)
                                .foregroundStyle(result.match ? .green : .red)
                        }
                    }
                    .width(min: 80, ideal: 100)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    @ViewBuilder
    private var summaryBadge: some View {
        HStack(spacing: 8) {
            if matchCount > 0 {
                Label("\(matchCount)", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if mismatchCount > 0 {
                Label("\(mismatchCount)", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
