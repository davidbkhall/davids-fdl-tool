import SwiftUI

struct CameraDatabaseView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedCameraID: String?
    @State private var selectedManufacturer: String?

    var body: some View {
        HSplitView {
            // Left: Camera list
            cameraListPane
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            // Right: Camera detail
            detailPane
                .frame(minWidth: 400, idealWidth: 500)
        }
        .navigationTitle("Camera Database")
        .task {
            if !appState.cameraDBStore.isLoaded {
                appState.cameraDBStore.loadBundled()
            }
        }
    }

    // MARK: - Camera List

    @ViewBuilder
    private var cameraListPane: some View {
        let store = appState.cameraDBStore

        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search cameras...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.bar)

            Divider()

            // Status bar
            HStack {
                if store.isLoaded {
                    Text("\(filteredCameras.count) camera\(filteredCameras.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !store.databaseVersion.isEmpty {
                    Text("v\(store.databaseVersion)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // Camera list grouped by manufacturer
            List(selection: $selectedCameraID) {
                if filteredCameras.isEmpty && store.isLoaded {
                    Text(searchText.isEmpty ? "No cameras in database" : "No results for \"\(searchText)\"")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(groupedCameras, id: \.manufacturer) { group in
                        Section(group.manufacturer) {
                            ForEach(group.cameras) { camera in
                                CameraListRow(camera: camera)
                                    .tag(camera.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        let store = appState.cameraDBStore
        if let cameraID = selectedCameraID, let camera = store.camera(byID: cameraID) {
            CameraDetailView(camera: camera)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "camera")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Select a camera to view specifications")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Computed

    private var filteredCameras: [CameraSpec] {
        appState.cameraDBStore.search(query: searchText)
    }

    private var groupedCameras: [(manufacturer: String, cameras: [CameraSpec])] {
        let cams = filteredCameras
        let grouped = Dictionary(grouping: cams, by: \.manufacturer)
        return grouped.keys.sorted().map { key in
            (manufacturer: key, cameras: grouped[key]!.sorted { $0.model < $1.model })
        }
    }
}

// MARK: - Camera List Row

struct CameraListRow: View {
    let camera: CameraSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(camera.model)
                .font(.body)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(camera.sensor.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(camera.sensor.photositeDimensions.width)\u{00D7}\(camera.sensor.photositeDimensions.height)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Camera Detail View

struct CameraDetailView: View {
    let camera: CameraSpec

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(camera.manufacturer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(camera.model)
                        .font(.title)
                        .fontWeight(.semibold)
                }

                // Sensor specifications
                GroupBox("Sensor") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Name")
                                .foregroundStyle(.secondary)
                            Text(camera.sensor.name)
                        }
                        GridRow {
                            Text("Photosites")
                                .foregroundStyle(.secondary)
                            Text("\(camera.sensor.photositeDimensions.width) \u{00D7} \(camera.sensor.photositeDimensions.height)")
                        }
                        GridRow {
                            Text("Physical Size")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f \u{00D7} %.2f mm",
                                        camera.sensor.physicalDimensionsMM.width,
                                        camera.sensor.physicalDimensionsMM.height))
                        }
                        GridRow {
                            Text("Diagonal")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2f mm", sensorDiagonal))
                        }
                        GridRow {
                            Text("Pixel Pitch")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.3f \u{03BC}m", camera.sensor.pixelPitchUM))
                        }
                    }
                    .font(.body)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Recording modes
                GroupBox("Recording Modes") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(camera.recordingModes) { mode in
                            RecordingModeRow(mode: mode)
                            if mode.id != camera.recordingModes.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Common deliverables
                GroupBox("Common Deliverables") {
                    FlowLayout(spacing: 6) {
                        ForEach(camera.commonDeliverables, id: \.self) { deliverable in
                            Text(deliverable)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.blue.opacity(0.1), in: Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Sensor visual (proportional rectangle)
                GroupBox("Sensor Visualization") {
                    SensorVisualization(camera: camera)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .padding()
        }
    }

    private var sensorDiagonal: Double {
        let w = camera.sensor.physicalDimensionsMM.width
        let h = camera.sensor.physicalDimensionsMM.height
        return (w * w + h * h).squareRoot()
    }
}

// MARK: - Recording Mode Row

struct RecordingModeRow: View {
    let mode: RecordingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mode.name)
                .font(.body.weight(.medium))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Text("Active Area")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(mode.activePhotosites.width) \u{00D7} \(mode.activePhotosites.height) px")
                        .font(.caption)
                    AspectRatioLabel(width: Double(mode.activePhotosites.width),
                                     height: Double(mode.activePhotosites.height))
                }
                GridRow {
                    Text("Image Area")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f \u{00D7} %.2f mm",
                                mode.activeImageAreaMM.width,
                                mode.activeImageAreaMM.height))
                        .font(.caption)
                    Text("")
                }
                GridRow {
                    Text("Max FPS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(mode.maxFPS) fps")
                        .font(.caption)
                    Text("")
                }
            }

            if !mode.codecOptions.isEmpty {
                HStack(spacing: 4) {
                    Text("Codecs:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(mode.codecOptions.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Sensor Visualization

/// Draws a proportional visualization of the sensor with recording mode areas overlaid.
struct SensorVisualization: View {
    let camera: CameraSpec

    private let modeColors: [Color] = [.blue, .green, .orange, .purple, .red, .cyan]

    var body: some View {
        GeometryReader { geo in
            let sensorW = camera.sensor.physicalDimensionsMM.width
            let sensorH = camera.sensor.physicalDimensionsMM.height
            guard sensorW > 0 && sensorH > 0 else { return AnyView(EmptyView()) }

            let maxScale = min((geo.size.width - 40) / sensorW, (geo.size.height - 50) / sensorH)
            let scaledW = sensorW * maxScale
            let scaledH = sensorH * maxScale
            let originX = (geo.size.width - scaledW) / 2
            let originY = (geo.size.height - scaledH - 20) / 2

            return AnyView(
                ZStack(alignment: .topLeading) {
                    // Sensor outline
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .border(Color.gray.opacity(0.5), width: 1)
                        .frame(width: scaledW, height: scaledH)
                        .offset(x: originX, y: originY)

                    // Recording mode areas (centered within sensor)
                    ForEach(Array(camera.recordingModes.enumerated()), id: \.element.id) { index, mode in
                        let modeW = mode.activeImageAreaMM.width * maxScale
                        let modeH = mode.activeImageAreaMM.height * maxScale
                        let modeX = originX + (scaledW - modeW) / 2
                        let modeY = originY + (scaledH - modeH) / 2
                        let color = modeColors[index % modeColors.count]

                        Rectangle()
                            .fill(color.opacity(0.08))
                            .border(color, width: 1.5)
                            .frame(width: modeW, height: modeH)
                            .offset(x: modeX, y: modeY)
                    }

                    // Legend
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(camera.recordingModes.enumerated()), id: \.element.id) { index, mode in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(modeColors[index % modeColors.count])
                                    .frame(width: 6, height: 6)
                                Text(mode.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .offset(x: 4, y: geo.size.height - 20)
                }
            )
        }
    }
}
