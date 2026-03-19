import SwiftUI

struct FDLDetailView: View {
    let entry: FDLEntry
    let document: FDLDocument?
    let validationResult: ValidationResult?
    @ObservedObject var libraryViewModel: LibraryViewModel
    let onOpenInViewer: () -> Void
    let onExport: () -> Void
    let onEditTitle: (() -> Void)?
    let onDelete: () -> Void

    private var firstCanvas: FDLCanvas? {
        document?.contexts.first?.canvases.first
    }

    private var firstFramingDecision: FDLFramingDecision? {
        firstCanvas?.framingDecisions.first
    }

    private var resolvedFramingIntent: FDLFramingIntent? {
        guard let doc = document,
              let intentID = firstFramingDecision?.framingIntentId else { return nil }
        return doc.framingIntents?.first(where: { $0.id == intentID })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                metadataSection
                geometryMetadataSection
                tagsSection
                framelineInteropSection

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
                Button(action: onOpenInViewer) {
                    Label("Open in Framing Workspace", systemImage: "eye")
                }

                Button(action: onExport) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                if let onEditTitle {
                    Button(action: onEditTitle) {
                        Label("Edit Title", systemImage: "pencil")
                    }
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
    private var geometryMetadataSection: some View {
        if let canvas = firstCanvas {
            GroupBox("Geometry Metadata") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Canvas")
                            .foregroundStyle(.secondary)
                        Text(verbatim: "\(Int(canvas.dimensions.width)) x \(Int(canvas.dimensions.height))")
                    }

                    if let effective = canvas.effectiveDimensions {
                        GridRow {
                            Text("Effective")
                                .foregroundStyle(.secondary)
                            Text(verbatim: "\(Int(effective.width)) x \(Int(effective.height))")
                        }
                    }

                    if let fd = firstFramingDecision {
                        GridRow {
                            Text("Framing Decision")
                                .foregroundStyle(.secondary)
                            Text(verbatim: "\(Int(fd.dimensions.width)) x \(Int(fd.dimensions.height))")
                        }

                        if let protection = fd.protectionDimensions {
                            GridRow {
                                Text("Protection")
                                    .foregroundStyle(.secondary)
                                Text(verbatim: "\(Int(protection.width)) x \(Int(protection.height))")
                            }
                        }
                    }

                    if let intent = resolvedFramingIntent {
                        if let aspect = intent.aspectRatio {
                            GridRow {
                                Text("Framing Intent")
                                    .foregroundStyle(.secondary)
                                Text("\(intent.label ?? intent.id) (\(Int(aspect.width)):\(Int(aspect.height)))")
                            }
                        } else {
                            GridRow {
                                Text("Framing Intent")
                                    .foregroundStyle(.secondary)
                                Text(intent.label ?? intent.id)
                            }
                        }

                        if let intentProtection = intent.protection {
                            GridRow {
                                Text("Intent Protection")
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f%%", intentProtection * 100.0))
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    @ViewBuilder
    private var framelineInteropSection: some View {
        GroupBox("Manufacturer XML Interop") {
            VStack(alignment: .leading, spacing: 8) {
                interopStatusRow(
                    title: "ARRI",
                    isReady: libraryViewModel.framelineStatus.arriAvailable,
                    compatibility: compatibilityState(for: "arri")
                )
                interopStatusRow(
                    title: "Sony",
                    isReady: libraryViewModel.framelineStatus.sonyAvailable,
                    compatibility: compatibilityState(for: "sony")
                )

                Text("XML exports/imports are available from Framing Workspace and export menus.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private enum CompatibilityState {
        case compatible
        case incompatible
        case unknown
    }

    private func compatibilityState(for manufacturer: String) -> CompatibilityState {
        guard let camera = entry.cameraModel?.lowercased(), !camera.isEmpty else {
            return .unknown
        }
        if manufacturer == "arri" {
            return camera.contains("arri") ? .compatible : .incompatible
        }
        if manufacturer == "sony" {
            return camera.contains("sony") ? .compatible : .incompatible
        }
        return .unknown
    }

    @ViewBuilder
    private func interopStatusRow(title: String, isReady: Bool, compatibility: CompatibilityState) -> some View {
        let readinessText = isReady ? "Ready" : "Unavailable"
        let readinessIcon = isReady ? "checkmark.circle.fill" : "xmark.circle"
        let readinessColor: Color = isReady ? .green : .orange

        let compatibilityText: String = {
            switch compatibility {
            case .compatible: return "Compatible"
            case .incompatible: return "Incompatible"
            case .unknown: return "Unknown"
            }
        }()
        let compatibilityIcon: String = {
            switch compatibility {
            case .compatible: return "checkmark.seal.fill"
            case .incompatible: return "xmark.seal.fill"
            case .unknown: return "questionmark.circle"
            }
        }()
        let compatibilityColor: Color = {
            switch compatibility {
            case .compatible: return .green
            case .incompatible: return .red
            case .unknown: return .secondary
            }
        }()

        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(width: 44, alignment: .leading)

            Label(readinessText, systemImage: readinessIcon)
                .foregroundStyle(readinessColor)
                .font(.caption)

            Label(compatibilityText, systemImage: compatibilityIcon)
                .foregroundStyle(compatibilityColor)
                .font(.caption)

            Spacer()
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
