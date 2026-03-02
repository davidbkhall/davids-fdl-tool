import SwiftUI

/// Progress indicator for batch scanning and FDL generation.
struct ClipBatchProgressView: View {
    let isScanning: Bool
    let isGenerating: Bool
    let generationProgress: Double
    let clipCount: Int
    let generatedCount: Int
    let errorCount: Int

    var body: some View {
        VStack(spacing: 8) {
            if isScanning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Scanning directory for video files...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isGenerating {
                VStack(spacing: 4) {
                    ProgressView(value: generationProgress)
                    HStack {
                        Text("Generating FDLs...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(generatedCount) / \(clipCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !isScanning && !isGenerating && (clipCount > 0 || errorCount > 0) {
                HStack(spacing: 12) {
                    Label("\(clipCount) clip\(clipCount == 1 ? "" : "s")", systemImage: "film")
                        .font(.caption)

                    if generatedCount > 0 {
                        Label("\(generatedCount) FDL\(generatedCount == 1 ? "" : "s")", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    if errorCount > 0 {
                        Label("\(errorCount) error\(errorCount == 1 ? "" : "s")", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}
