import SwiftUI

struct FDLDetailView: View {
    let entry: FDLEntry
    let document: FDLDocument?
    let validationResult: ValidationResult?
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                metadataSection
                tagsSection

                if let result = validationResult {
                    ValidationReportView(result: result)
                }

                if let doc = document {
                    FDLTreeView(document: doc)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("UUID: \(entry.fdlUUID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onExport) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        GroupBox("Metadata") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Source")
                        .foregroundStyle(.secondary)
                    Text(entry.sourceTool ?? "Unknown")
                }
                if let camera = entry.cameraModel {
                    GridRow {
                        Text("Camera")
                            .foregroundStyle(.secondary)
                        Text(camera)
                    }
                }
                GridRow {
                    Text("Created")
                        .foregroundStyle(.secondary)
                    Text(entry.createdAt, style: .date)
                }
                GridRow {
                    Text("Updated")
                        .foregroundStyle(.secondary)
                    Text(entry.updatedAt, style: .date)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        if !entry.tags.isEmpty {
            GroupBox("Tags") {
                FlowLayout(spacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Simple horizontal flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
