import SwiftUI

/// Compact camera and recording mode picker for use in Chart Generator and other tools.
struct CameraPickerView: View {
    @ObservedObject var cameraDB: CameraDBStore
    @Binding var selectedCameraID: String?
    @Binding var selectedModeID: String?

    @State private var searchText = ""
    @State private var isExpanded = false

    var selectedCamera: CameraSpec? {
        guard let id = selectedCameraID else { return nil }
        return cameraDB.camera(byID: id)
    }

    var selectedMode: RecordingMode? {
        guard let camera = selectedCamera, let modeID = selectedModeID else { return nil }
        return camera.recordingModes.first { $0.id == modeID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Camera selection
            VStack(alignment: .leading, spacing: 4) {
                Text("Camera")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let camera = selectedCamera {
                    selectedCameraBadge(camera)
                } else {
                    cameraSelector
                }
            }

            // Recording mode selection (shown when camera is selected)
            if let camera = selectedCamera {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording Mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Mode", selection: Binding(
                        get: { selectedModeID ?? "" },
                        set: { selectedModeID = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Select mode...").tag("")
                        ForEach(camera.recordingModes) { mode in
                            Text("\(mode.name) (\(mode.activePhotosites.width)\u{00D7}\(mode.activePhotosites.height))")
                                .tag(mode.id)
                        }
                    }
                    .labelsHidden()
                }

                // Selected mode summary
                if let mode = selectedMode {
                    modeSummary(mode)
                }
            }
        }
    }

    // MARK: - Camera Selector

    @ViewBuilder
    private var cameraSelector: some View {
        VStack(spacing: 4) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                TextField("Search cameras...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit { isExpanded = true }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .onTapGesture { isExpanded = true }

            // Dropdown list
            if isExpanded {
                let results = cameraDB.search(query: searchText)
                if results.isEmpty {
                    Text("No cameras found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(4)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(results.prefix(10)) { camera in
                                Button(action: {
                                    selectedCameraID = camera.id
                                    selectedModeID = nil
                                    isExpanded = false
                                    searchText = ""
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("\(camera.manufacturer) \(camera.model)")
                                                .font(.caption)
                                            Text(camera.sensor.name)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if camera.id != results.prefix(10).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(.background)
                    .border(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    // MARK: - Selected Camera Badge

    @ViewBuilder
    private func selectedCameraBadge(_ camera: CameraSpec) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(camera.manufacturer) \(camera.model)")
                    .font(.caption.weight(.medium))
                Text(camera.sensor.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: {
                selectedCameraID = nil
                selectedModeID = nil
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Mode Summary

    @ViewBuilder
    private func modeSummary(_ mode: RecordingMode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("\(mode.activePhotosites.width) \u{00D7} \(mode.activePhotosites.height)")
                    .font(.system(.caption, design: .monospaced))
                AspectRatioLabel(width: Double(mode.activePhotosites.width),
                                 height: Double(mode.activePhotosites.height))
                Text("up to \(mode.maxFPS) fps")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(String(format: "%.2f \u{00D7} %.2f mm active area",
                        mode.activeImageAreaMM.width, mode.activeImageAreaMM.height))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(6)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
    }
}
