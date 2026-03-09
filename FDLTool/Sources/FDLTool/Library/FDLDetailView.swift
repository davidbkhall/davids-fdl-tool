import SwiftUI

struct FDLDetailView: View {
    let entry: FDLEntry
    let document: FDLDocument?
    let validationResult: ValidationResult?
    @ObservedObject var libraryViewModel: LibraryViewModel
    let onOpenInViewer: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                metadataSection
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

    @ViewBuilder
    private var framelineInteropSection: some View {
        GroupBox("Manufacturer XML Interop") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(
                        libraryViewModel.framelineStatus.arriAvailable ? "ARRI Ready" : "ARRI Unavailable",
                        systemImage: libraryViewModel.framelineStatus.arriAvailable ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(libraryViewModel.framelineStatus.arriAvailable ? .green : .orange)
                    .font(.caption)

                    Label(
                        libraryViewModel.framelineStatus.sonyAvailable ? "Sony Ready" : "Sony Unavailable",
                        systemImage: libraryViewModel.framelineStatus.sonyAvailable ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    .foregroundStyle(libraryViewModel.framelineStatus.sonyAvailable ? .green : .orange)
                    .font(.caption)
                }

                if libraryViewModel.framelineStatus.arriAvailable {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ARRI XML")
                            .font(.caption.weight(.semibold))
                        HStack(spacing: 6) {
                            Picker("Camera", selection: $libraryViewModel.selectedArriCameraType) {
                                ForEach(libraryViewModel.arriCameras) { camera in
                                    Text(camera.cameraType).tag(camera.cameraType)
                                }
                            }
                            .controlSize(.small)
                            .onChange(of: libraryViewModel.selectedArriCameraType) { _, selected in
                                libraryViewModel.selectedArriSensorMode = libraryViewModel.arriCameras
                                    .first(where: { $0.cameraType == selected })?
                                    .modes.first?.name ?? ""
                            }
                            Picker("Mode", selection: $libraryViewModel.selectedArriSensorMode) {
                                let modes = libraryViewModel.arriCameras
                                    .first(where: { $0.cameraType == libraryViewModel.selectedArriCameraType })?
                                    .modes ?? []
                                ForEach(modes) { mode in
                                    Text(mode.name).tag(mode.name)
                                }
                            }
                            .controlSize(.small)
                        }
                        .font(.caption)

                        HStack(spacing: 6) {
                            Button("Export ARRI XML") {
                                libraryViewModel.exportSelectedEntryToArriXML()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Import ARRI XML to Project") {
                                libraryViewModel.importArriXMLToSelectedProject()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                if libraryViewModel.framelineStatus.sonyAvailable {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sony XML")
                            .font(.caption.weight(.semibold))
                        HStack(spacing: 6) {
                            Picker("Camera", selection: $libraryViewModel.selectedSonyCameraType) {
                                ForEach(libraryViewModel.sonyCameras) { camera in
                                    Text(camera.cameraType).tag(camera.cameraType)
                                }
                            }
                            .controlSize(.small)
                            .onChange(of: libraryViewModel.selectedSonyCameraType) { _, selected in
                                libraryViewModel.selectedSonyImagerMode = libraryViewModel.sonyCameras
                                    .first(where: { $0.cameraType == selected })?
                                    .modes.first?.name ?? ""
                            }
                            Picker("Mode", selection: $libraryViewModel.selectedSonyImagerMode) {
                                let modes = libraryViewModel.sonyCameras
                                    .first(where: { $0.cameraType == libraryViewModel.selectedSonyCameraType })?
                                    .modes ?? []
                                ForEach(modes) { mode in
                                    Text(mode.name).tag(mode.name)
                                }
                            }
                            .controlSize(.small)
                        }
                        .font(.caption)

                        HStack(spacing: 6) {
                            Button("Export Sony XML") {
                                libraryViewModel.exportSelectedEntryToSonyXML()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Import Sony XML to Project") {
                                libraryViewModel.importSonyXMLToSelectedProject()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                if let report = libraryViewModel.framelineReport {
                    Divider()
                    FramelineReportCard(
                        report: report,
                        onCopy: {
                            if let data = try? JSONEncoder().encode(report),
                               let text = String(data: data, encoding: .utf8) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            }
                        },
                        onExport: { libraryViewModel.exportFramelineReportJSON() },
                        onSave: { libraryViewModel.saveFramelineReportToSelectedProject() },
                        saveTitle: "Save Report to Project"
                    )
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
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
