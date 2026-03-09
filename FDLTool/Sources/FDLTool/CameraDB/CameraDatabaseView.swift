import SwiftUI

struct CameraDatabaseView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedCameraID: String?
    @State private var selectedManufacturer: String?
    @State private var sortOrder: SortOrder = .name
    @State private var filterType: String = "All"

    @State private var searchMode: SearchMode = .text
    @State private var resWidth: Int = 3840
    @State private var resHeight: Int = 2160
    @State private var resolutionMatches: [CameraDBSyncService.APISensorMatch] = []
    @State private var isSearchingResolution = false
    @State private var resolutionSearchError: String?
    @State private var showAddCameraSheet = false
    @State private var showConflictSheet = false

    enum SearchMode: String, CaseIterable {
        case text = "Name"
        case resolution = "Resolution"
    }

    enum SortOrder: String, CaseIterable {
        case name = "Name (A-Z)"
        case manufacturer = "Manufacturer (A-Z)"
        case resolution = "Resolution (high to low)"
    }

    static let typeFilterOptions = ["All", "Cinema", "Photo", "Drone", "Mobile"]
    static let typeKeywords: [String: [String]] = [
        "Cinema": ["arri", "red", "sony", "panavision", "blackmagic", "varicam", "venice", "fx", "komodo"],
        "Photo": ["canon", "nikon", "fujifilm", "leica", "fuji", "olympus", "pentax"],
        "Drone": ["dji", "drone", "inspire", "phantom"],
        "Mobile": ["apple", "samsung", "iphone", "pixel", "mobile", "xiaomi"],
    ]

    var body: some View {
        HSplitView {
            cameraListPane
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            detailPane
                .frame(minWidth: 400, idealWidth: 500)
        }
        .navigationTitle("Camera Database")
        .task {
            if !appState.cameraDBStore.isLoaded {
                appState.cameraDBStore.loadBundled()
            }
        }
        .sheet(isPresented: $showAddCameraSheet) {
            AddCameraSheet(cameraDBStore: appState.cameraDBStore)
        }
        .sheet(isPresented: $showConflictSheet) {
            SyncConflictSheet(cameraDBStore: appState.cameraDBStore)
        }
        .onChange(of: appState.cameraDBStore.pendingConflicts.count) { _, newCount in
            if newCount > 0 {
                showConflictSheet = true
            }
        }
    }

    @ViewBuilder
    private var cameraListPane: some View {
        let store = appState.cameraDBStore
        let syncService = appState.cameraDBSyncService

        VStack(spacing: 0) {
            Picker("Search", selection: $searchMode) {
                ForEach(SearchMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            if searchMode == .text {
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
            } else {
                resolutionSearchBar
            }

            if searchMode == .text {
                HStack(spacing: 12) {
                    Picker("Type", selection: $filterType) {
                        ForEach(Self.typeFilterOptions, id: \.self) { opt in
                            Text(opt).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 120)

                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(maxWidth: 180)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                if syncService.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                    Text(syncService.syncProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if store.isLoaded {
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

                Button(action: { showAddCameraSheet = true }) {
                    Label("Add", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Add a custom camera")

                Menu {
                    Button("MatchMove Machine") {
                        Task {
                            await syncService.syncAll(cameraDBStore: store)
                        }
                    }
                    .disabled(syncService.isSyncing)

                    Button("CineD Camera Database") {
                        Task {
                            await appState.cinedSyncService.syncAll(
                                email: appState.cinedEmail,
                                password: appState.cinedPassword,
                                cameraDBStore: store
                            )
                        }
                    }
                    .disabled(appState.cinedSyncService.isSyncing)

                    Divider()

                    Button("Sync All Sources") {
                        Task {
                            await syncService.syncAll(cameraDBStore: store)
                            await appState.cinedSyncService.syncAll(
                                email: appState.cinedEmail,
                                password: appState.cinedPassword,
                                cameraDBStore: store
                            )
                        }
                    }
                    .disabled(syncService.isSyncing || appState.cinedSyncService.isSyncing)
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(syncService.isSyncing || appState.cinedSyncService.isSyncing)
                .help("Sync cameras from external sources")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            if let err = syncService.lastSyncError {
                Text("MatchMove: \(err)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
            }

            if appState.cinedSyncService.isSyncing {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text(appState.cinedSyncService.syncProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            }

            if let err = appState.cinedSyncService.lastSyncError {
                Text("CineD: \(err)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
            }

            if !store.pendingConflicts.isEmpty {
                Button(action: { showConflictSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("\(store.pendingConflicts.count) sync conflict\(store.pendingConflicts.count == 1 ? "" : "s")")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)
            }

            Divider()

            if searchMode == .resolution && !resolutionMatches.isEmpty {
                resolutionResultsList
            } else {
                List(selection: $selectedCameraID) {
                    if filteredCameras.isEmpty && store.isLoaded {
                        Text(searchText.isEmpty ? "No cameras in database" : "No results for \"\(searchText)\"")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(groupedCameras, id: \.manufacturer) { group in
                            Section {
                                ForEach(group.cameras) { camera in
                                    CameraListRow(camera: camera)
                                        .tag(camera.id)
                                        .contextMenu {
                                            if camera.source != .bundled {
                                                Button(role: .destructive) {
                                                    if selectedCameraID == camera.id {
                                                        selectedCameraID = nil
                                                    }
                                                    store.removeCamera(byID: camera.id)
                                                } label: {
                                                    Label("Delete Camera", systemImage: "trash")
                                                }
                                            } else {
                                                Text("Bundled cameras cannot be deleted")
                                            }
                                        }
                                }
                            } header: {
                                Text(group.manufacturer.uppercased())
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    @ViewBuilder
    private var resolutionSearchBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                TextField("W", value: $resWidth, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .font(.caption)
                Text("\u{00D7}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("H", value: $resHeight, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .font(.caption)

                Button("Search") {
                    Task { await performResolutionSearch() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSearchingResolution)

                if isSearchingResolution {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if let err = resolutionSearchError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 8)
            }
        }
        .background(.bar)
    }

    @ViewBuilder
    private var resolutionResultsList: some View {
        List {
            Section("Matches for \(resWidth)\u{00D7}\(resHeight)") {
                ForEach(resolutionMatches, id: \.id) { match in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(match.cameraMake ?? "") \(match.cameraName ?? "Camera \(match.camId)")")
                            .font(.body)
                        HStack(spacing: 8) {
                            Text(match.modeName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(verbatim: "\(match.resWidth)\u{00D7}\(match.resHeight)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(match.formatAspect)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(String(format: "Sensor: %.2f \u{00D7} %.2f mm", match.sensorWidth, match.sensorHeight))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func performResolutionSearch() async {
        isSearchingResolution = true
        resolutionSearchError = nil
        do {
            resolutionMatches = try await appState.cameraDBSyncService.searchByResolution(width: resWidth, height: resHeight)
        } catch {
            resolutionSearchError = error.localizedDescription
            resolutionMatches = []
        }
        isSearchingResolution = false
    }

    @ViewBuilder
    private var detailPane: some View {
        let store = appState.cameraDBStore
        if let cameraID = selectedCameraID, store.cameras.contains(where: { $0.id == cameraID }) {
            CameraDetailView(camera: Binding(
                get: {
                    store.cameras.first(where: { $0.id == cameraID })
                        ?? store.cameras[0]
                },
                set: { store.updateCamera($0) }
            ), cameraDBStore: store, onDelete: { selectedCameraID = nil })
        } else {
            VStack(spacing: 12) {
                Image(systemName: "camera")
                    .font(.system(size: 40))
                    .foregroundStyle(.quaternary)
                Text("Select a Camera")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Choose a camera from the list to view its specifications and recording modes.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filteredCameras: [CameraSpec] {
        var cams = appState.cameraDBStore.search(query: searchText)
        if filterType != "All", let keywords = Self.typeKeywords[filterType] {
            let lowered = keywords.map { $0.lowercased() }
            cams = cams.filter { cam in
                let mfr = cam.manufacturer.lowercased()
                let model = cam.model.lowercased()
                return lowered.contains { mfr.contains($0) || model.contains($0) }
            }
        }
        switch sortOrder {
        case .name:
            return cams.sorted { $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending }
        case .manufacturer:
            return cams.sorted { lhs, rhs in
                if lhs.manufacturer != rhs.manufacturer {
                    return lhs.manufacturer.localizedCaseInsensitiveCompare(rhs.manufacturer) == .orderedAscending
                }
                return lhs.model.localizedCaseInsensitiveCompare(rhs.model) == .orderedAscending
            }
        case .resolution:
            return cams.sorted { lhs, rhs in
                let lMax = lhs.recordingModes.map { $0.activePhotosites.width * $0.activePhotosites.height }.max() ?? 0
                let rMax = rhs.recordingModes.map { $0.activePhotosites.width * $0.activePhotosites.height }.max() ?? 0
                return lMax > rMax
            }
        }
    }

    private var groupedCameras: [(manufacturer: String, cameras: [CameraSpec])] {
        let grouped = Dictionary(grouping: filteredCameras, by: \.manufacturer)
        return grouped.keys.sorted().map { key in
            (manufacturer: key, cameras: grouped[key]!.sorted { $0.model < $1.model })
        }
    }
}

struct CameraListRow: View {
    let camera: CameraSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(camera.model)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer(minLength: 0)

                ForEach(camera.effectiveSourceBadges, id: \.self) { badge in
                    SourceBadge(label: badge)
                }
            }

            HStack(spacing: 12) {
                if !camera.sensor.name.isEmpty {
                    Label(camera.sensor.name, systemImage: "cpu")
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: "\(camera.sensor.photositeDimensions.width)\u{00D7}\(camera.sensor.photositeDimensions.height)")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

struct SourceBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Self.color(for: label), in: Capsule())
    }

    static func color(for badge: String) -> Color {
        switch badge {
        case "ARRI": return .teal
        case "RED": return .red
        case "Sony": return .indigo
        case "Canon": return .pink
        case "MMM": return .blue
        case "CineD": return .purple
        case "Custom": return .orange
        case "API": return .blue
        default: return .gray
        }
    }
}

extension CameraSpec {
    /// Compute display badges from syncSources, falling back to the source enum.
    var effectiveSourceBadges: [String] {
        if !syncSources.isEmpty {
            var badges: [String] = []
            let seen = NSMutableSet()
            for source in syncSources {
                let badge: String
                switch source {
                case let s where s.hasPrefix("ARRI"): badge = "ARRI"
                case let s where s.hasPrefix("RED"): badge = "RED"
                case let s where s.hasPrefix("Sony"): badge = "Sony"
                case let s where s.hasPrefix("Canon"): badge = "Canon"
                case "MatchMove Machine": badge = "MMM"
                case "CineD": badge = "CineD"
                default: badge = source
                }
                if !seen.contains(badge) {
                    seen.add(badge)
                    badges.append(badge)
                }
            }
            return badges
        }
        switch source {
        case .synced: return ["API"]
        case .custom: return ["Custom"]
        case .bundled: return []
        }
    }
}

struct CameraDetailView: View {
    @Binding var camera: CameraSpec
    @ObservedObject var cameraDBStore: CameraDBStore
    var onDelete: (() -> Void)?
    @EnvironmentObject var appState: AppState
    @State private var modeToEdit: RecordingMode?
    @State private var showAddModeSheet = false
    @State private var isEditingEnabled = false
    @State private var showDeleteConfirm = false
    @State private var isSyncingCamera = false
    @State private var cameraSyncError: String?
    @State private var cameraSyncSuccess: String?

    /// Extract the integer API ID from an "mmm-XX" style camera ID, if present.
    private var apiCameraID: Int? {
        guard camera.id.hasPrefix("mmm-") else { return nil }
        return Int(camera.id.dropFirst(4))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(camera.manufacturer)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Spacer()

                        HStack(spacing: 6) {
                            if apiCameraID != nil {
                                Button(action: { resyncCamera() }) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                .buttonStyle(.bordered)
                                .denseControl()
                                .disabled(isSyncingCamera)
                                .help("Re-sync this camera from API")
                            }

                            Toggle(isOn: $isEditingEnabled) {
                                Image(systemName: isEditingEnabled ? "lock.open.fill" : "lock.fill")
                                    .foregroundStyle(isEditingEnabled ? .orange : .secondary)
                            }
                            .toggleStyle(.button)
                            .help(isEditingEnabled ? "Lock editing" : "Unlock editing")

                            if camera.source != .bundled {
                                Button(action: { showDeleteConfirm = true }) {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.bordered)
                                .denseControl()
                                .help("Delete this camera")
                            }
                        }
                        .controlSize(.small)
                    }

                    if isEditingEnabled {
                        TextField("Model", text: $camera.model)
                            .font(.title2.weight(.semibold))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Text(camera.model)
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    if !camera.effectiveSourceBadges.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(camera.effectiveSourceBadges, id: \.self) { badge in
                                SourceBadge(label: badge)
                            }
                        }
                    }
                }

                if isSyncingCamera {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Syncing...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let err = cameraSyncError {
                    Label(err, systemImage: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                if let msg = cameraSyncSuccess {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                        .transition(.opacity)
                }

                // MARK: Extended Metadata
                if camera.releaseDate != nil || camera.lensMount != nil || camera.baseSensitivity != nil {
                    GroupBox {
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                            if let date = camera.releaseDate {
                                GridRow {
                                    Text("Released")
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)
                                    Text(date)
                                }
                            }
                            if let mount = camera.lensMount {
                                GridRow {
                                    Text("Lens Mount").foregroundStyle(.secondary)
                                    Text(mount)
                                }
                            }
                            if let iso = camera.baseSensitivity {
                                GridRow {
                                    Text("Base ISO").foregroundStyle(.secondary)
                                    Text(iso)
                                }
                            }
                        }
                        .font(.callout)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("Details", systemImage: "info.circle")
                            .primarySectionHeader()
                    }
                }

                // MARK: Sensor
                GroupBox {
                    if isEditingEnabled {
                        editableSensorGrid
                    } else {
                        readOnlySensorGrid
                    }
                } label: {
                    Label("Sensor", systemImage: "cpu")
                        .primarySectionHeader()
                }

                // MARK: Recording Modes
                GroupBox {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(camera.recordingModes) { mode in
                            RecordingModeRow(
                                mode: mode,
                                camera: camera,
                                appState: appState,
                                isEditingEnabled: isEditingEnabled,
                                onEdit: { modeToEdit = mode },
                                onDelete: { cameraDBStore.removeRecordingMode(fromCameraID: camera.id, modeID: mode.id) },
                                onResync: apiCameraID != nil ? { resyncMode(mode) } : nil,
                                onAssignToProject: { projectID in
                                    assignModeToProject(mode, projectID: projectID)
                                }
                            )
                            if mode.id != camera.recordingModes.last?.id {
                                Divider().padding(.vertical, 6)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack {
                        Label("Recording Modes", systemImage: "film")
                            .primarySectionHeader()
                        Spacer()
                        if isEditingEnabled {
                            Button(action: { showAddModeSheet = true }) {
                                Label("Add", systemImage: "plus")
                                    .font(.callout)
                            }
                            .buttonStyle(.bordered)
                            .denseControl()
                        }
                    }
                }

                // MARK: Sensor Visualization
                GroupBox {
                    SensorVisualization(camera: camera)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                } label: {
                    Label("Sensor Visualization", systemImage: "rectangle.dashed")
                        .primarySectionHeader()
                }
            }
            .padding()
        }
        .alert("Delete Camera?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                cameraDBStore.removeCamera(byID: camera.id)
                onDelete?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \"\(camera.manufacturer) \(camera.model)\" from the database? This cannot be undone.")
        }
        .sheet(item: $modeToEdit) { mode in
            EditRecordingModeSheet(
                mode: mode,
                onSave: { updated in
                    if let idx = camera.recordingModes.firstIndex(where: { $0.id == mode.id }) {
                        var updatedCamera = camera
                        updatedCamera.recordingModes[idx] = updated
                        camera = updatedCamera
                    }
                    modeToEdit = nil
                },
                onCancel: { modeToEdit = nil }
            )
        }
        .sheet(isPresented: $showAddModeSheet) {
            AddRecordingModeSheet(
                sensorPhysicalMM: camera.sensor.physicalDimensionsMM,
                onAdd: { newMode in
                    cameraDBStore.addRecordingMode(toCameraID: camera.id, mode: newMode)
                    showAddModeSheet = false
                },
                onCancel: { showAddModeSheet = false }
            )
        }
        .onChange(of: isEditingEnabled) { _, enabled in
            if !enabled {
                cameraDBStore.updateCamera(camera)
            }
        }
    }

    // MARK: - Sensor Grids

    @ViewBuilder
    private var readOnlySensorGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Name")
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Text(camera.sensor.name)
            }
            GridRow {
                Text("Photosites").foregroundStyle(.secondary)
                Text(verbatim: "\(camera.sensor.photositeDimensions.width) \u{00D7} \(camera.sensor.photositeDimensions.height)")
            }
            GridRow {
                Text("Physical Size").foregroundStyle(.secondary)
                Text(String(format: "%.2f \u{00D7} %.2f mm",
                            camera.sensor.physicalDimensionsMM.width,
                            camera.sensor.physicalDimensionsMM.height))
            }
            GridRow {
                Text("Diagonal").foregroundStyle(.secondary)
                Text(String(format: "%.2f mm", sensorDiagonal))
            }
            GridRow {
                Text("Pixel Pitch").foregroundStyle(.secondary)
                Text(String(format: "%.3f \u{03BC}m", camera.sensor.pixelPitchUM))
            }
        }
        .font(.callout)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var editableSensorGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Name")
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                TextField("Sensor Name", text: $camera.sensor.name)
                    .textFieldStyle(.roundedBorder)
            }
            GridRow {
                Text("Width (px)").foregroundStyle(.secondary)
                TextField("W", value: $camera.sensor.photositeDimensions.width, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 100)
            }
            GridRow {
                Text("Height (px)").foregroundStyle(.secondary)
                TextField("H", value: $camera.sensor.photositeDimensions.height, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 100)
            }
            GridRow {
                Text("Width (mm)").foregroundStyle(.secondary)
                TextField("W", value: $camera.sensor.physicalDimensionsMM.width, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 100)
            }
            GridRow {
                Text("Height (mm)").foregroundStyle(.secondary)
                TextField("H", value: $camera.sensor.physicalDimensionsMM.height, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 100)
            }
        }
        .font(.callout)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Resync

    private func resyncCamera() {
        guard let id = apiCameraID else { return }
        isSyncingCamera = true
        cameraSyncError = nil
        cameraSyncSuccess = nil

        let beforeModes = camera.recordingModes.count

        Task {
            do {
                try await appState.cameraDBSyncService.syncCamera(apiCameraID: id, cameraDBStore: cameraDBStore)
                let afterCam = cameraDBStore.cameras.first(where: { $0.id == camera.id })
                let afterModes = afterCam?.recordingModes.count ?? beforeModes
                let modesDiff = afterModes - beforeModes

                var message = "Sync complete."
                if modesDiff > 0 {
                    message += " \(modesDiff) new mode\(modesDiff == 1 ? "" : "s") added."
                } else if modesDiff < 0 {
                    message += " \(-modesDiff) mode\(modesDiff == -1 ? "" : "s") removed."
                } else {
                    message += " Camera is up to date."
                }
                withAnimation { cameraSyncSuccess = message }

                Task {
                    try? await Task.sleep(for: .seconds(5))
                    withAnimation { cameraSyncSuccess = nil }
                }
            } catch {
                cameraSyncError = error.localizedDescription
            }
            isSyncingCamera = false
        }
    }

    private func resyncMode(_ mode: RecordingMode) {
        guard let camID = apiCameraID else { return }
        isSyncingCamera = true
        cameraSyncError = nil
        cameraSyncSuccess = nil
        Task {
            do {
                try await appState.cameraDBSyncService.syncRecordingMode(apiCameraID: camID, modeID: mode.id, cameraDBStore: cameraDBStore)
                withAnimation { cameraSyncSuccess = "Mode \"\(mode.name)\" synced successfully." }
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    withAnimation { cameraSyncSuccess = nil }
                }
            } catch {
                cameraSyncError = error.localizedDescription
            }
            isSyncingCamera = false
        }
    }

    private func assignModeToProject(_ mode: RecordingMode, projectID: String) {
        do {
            let assignment = ProjectCameraModeAssignment(
                projectID: projectID,
                cameraModelID: camera.id,
                cameraModelName: "\(camera.manufacturer) \(camera.model)",
                recordingModeID: mode.id,
                recordingModeName: mode.name,
                source: "camera_db",
                notes: nil
            )
            try appState.libraryStore.assignCameraModeToProject(assignment)
            withAnimation {
                cameraSyncSuccess = "Assigned \"\(mode.name)\" to project."
            }
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { cameraSyncSuccess = nil }
            }
        } catch {
            cameraSyncError = "Assignment failed: \(error.localizedDescription)"
        }
    }

    private var sensorDiagonal: Double {
        let w = camera.sensor.physicalDimensionsMM.width
        let h = camera.sensor.physicalDimensionsMM.height
        return (w * w + h * h).squareRoot()
    }
}

struct RecordingModeRow: View {
    let mode: RecordingMode
    let camera: CameraSpec
    @ObservedObject var appState: AppState
    let isEditingEnabled: Bool
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onResync: (() -> Void)?
    var onAssignToProject: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(mode.name)
                    .font(.callout.weight(.medium))
                modeSourceBadges
                Spacer()
                actionButtons
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("Active Area")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(verbatim: "\(mode.activePhotosites.width) \u{00D7} \(mode.activePhotosites.height) px")
                    AspectRatioLabel(width: Double(mode.activePhotosites.width),
                                     height: Double(mode.activePhotosites.height))
                }
                GridRow {
                    Text("Image Area").foregroundStyle(.secondary)
                    Text(String(format: "%.2f \u{00D7} %.2f mm",
                                mode.activeImageAreaMM.width,
                                mode.activeImageAreaMM.height))
                    Text("")
                }
                if mode.maxFPS > 0 {
                    GridRow {
                        Text("Max FPS").foregroundStyle(.secondary)
                        Text("\(mode.maxFPS) fps")
                        Text("")
                    }
                }
            }
            .font(.caption)

            if !mode.codecOptions.isEmpty {
                HStack(spacing: 4) {
                    Text("Codecs:")
                        .foregroundStyle(.secondary)
                    Text(mode.codecOptions.joined(separator: ", "))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                .font(.caption)
            }

            let extFields = [
                mode.aspectRatio.map { "Aspect: \($0)" },
                mode.bitDepth.map { "\($0)" },
                mode.sampling,
                mode.fileFormat.map { "Format: \($0)" }
            ].compactMap { $0 }
            if !extFields.isEmpty {
                Text(extFields.joined(separator: " \u{2022} "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button(action: { onEdit?() }) {
                Image(systemName: "pencil")
                    .foregroundStyle(isEditingEnabled ? Color.accentColor : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.borderless)
            .disabled(!isEditingEnabled)
            .help("Edit recording mode")

            if onResync != nil && (mode.source == .synced || mode.source == .modified) {
                Button(action: { onResync?() }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(isEditingEnabled ? .blue : .secondary.opacity(0.3))
                }
                .buttonStyle(.borderless)
                .disabled(!isEditingEnabled)
                .help("Re-sync this mode from API")
            }

            Button(action: { onDelete?() }) {
                Image(systemName: "trash")
                    .foregroundStyle(isEditingEnabled ? .red : .secondary.opacity(0.3))
            }
            .buttonStyle(.borderless)
            .disabled(!isEditingEnabled)
            .help("Delete recording mode")

            Divider().frame(height: 14)

            Button(action: {
                appState.selectedTool = .chartGenerator
                appState.chartGeneratorViewModel.selectedCameraID = camera.id
                appState.chartGeneratorViewModel.selectedModeID = mode.id
                appState.chartGeneratorViewModel.useCustomCanvas = false
            }) {
                Label("Chart", systemImage: "rectangle.on.rectangle.angled")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Open in Chart Generator")

            if !appState.libraryViewModel.projects.isEmpty {
                Menu {
                    ForEach(appState.libraryViewModel.projects) { project in
                        Button(project.name) {
                            onAssignToProject?(project.id)
                        }
                    }
                } label: {
                    Label("Assign", systemImage: "folder.badge.plus")
                        .font(.caption)
                }
                .controlSize(.mini)
                .help("Assign mode to project")
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var modeSourceBadges: some View {
        if !mode.syncSources.isEmpty {
            ForEach(mode.syncSources, id: \.self) { src in
                let label = src == "MatchMove Machine" ? "MMM" : src
                SourceBadge(label: label)
            }
        } else {
            switch mode.source {
            case .synced:
                SourceBadge(label: "API")
            case .custom:
                SourceBadge(label: "Custom")
            case .modified:
                Text("Modified")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.yellow, in: Capsule())
            case .bundled:
                EmptyView()
            }
        }
    }
}

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
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .border(Color.gray.opacity(0.5), width: 1)
                        .frame(width: scaledW, height: scaledH)
                        .offset(x: originX, y: originY)

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

struct AddCameraSheet: View {
    @ObservedObject var cameraDBStore: CameraDBStore
    @Environment(\.dismiss) private var dismiss

    @State private var manufacturer = ""
    @State private var model = ""
    @State private var sensorName = ""
    @State private var sensorWidthPx = 3840
    @State private var sensorHeightPx = 2160
    @State private var sensorWidthMM = 23.76
    @State private var sensorHeightMM = 13.365
    @State private var modes: [ModeEntry] = [ModeEntry()]

    struct ModeEntry: Identifiable {
        let id = UUID()
        var name = ""
        var widthPx = 3840
        var heightPx = 2160
        var widthMM = 23.76
        var heightMM = 13.365
        var maxFPS = 24
    }

    struct ModeEntryFields: View {
        @Binding var name: String
        @Binding var widthPx: Int
        @Binding var heightPx: Int
        @Binding var widthMM: Double
        @Binding var heightMM: Double
        @Binding var maxFPS: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Mode Name", text: $name)
                HStack {
                    TextField("W px", value: $widthPx, format: .number.grouping(.never))
                        .frame(width: 70)
                    TextField("H px", value: $heightPx, format: .number.grouping(.never))
                        .frame(width: 70)
                }
                HStack {
                    TextField("W mm", value: $widthMM, format: .number.grouping(.never))
                        .frame(width: 70)
                    TextField("H mm", value: $heightMM, format: .number.grouping(.never))
                        .frame(width: 70)
                }
                TextField("Max FPS", value: $maxFPS, format: .number.grouping(.never))
                    .frame(width: 80)
            }
            .padding(.vertical, 4)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Custom Camera")
                .font(.headline)
                .padding()

            Form {
                Section("Camera") {
                    TextField("Manufacturer", text: $manufacturer)
                    TextField("Model", text: $model)
                }

                Section("Sensor") {
                    TextField("Sensor Name", text: $sensorName)
                    HStack {
                        TextField("Width (px)", value: $sensorWidthPx, format: .number.grouping(.never))
                        TextField("Height (px)", value: $sensorHeightPx, format: .number.grouping(.never))
                    }
                    HStack {
                        TextField("Width (mm)", value: $sensorWidthMM, format: .number.grouping(.never))
                        TextField("Height (mm)", value: $sensorHeightMM, format: .number.grouping(.never))
                    }
                }

                Section("Recording Modes") {
                    ForEach(modes) { mode in
                        if let idx = modes.firstIndex(where: { $0.id == mode.id }) {
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Mode Name", text: Binding(
                                    get: { modes[idx].name },
                                    set: { modes[idx].name = $0 }
                                ))
                                HStack {
                                    TextField("W px", value: Binding(
                                        get: { modes[idx].widthPx },
                                        set: { modes[idx].widthPx = $0 }
                                    ), format: .number.grouping(.never))
                                        .frame(width: 70)
                                    TextField("H px", value: Binding(
                                        get: { modes[idx].heightPx },
                                        set: { modes[idx].heightPx = $0 }
                                    ), format: .number.grouping(.never))
                                        .frame(width: 70)
                                }
                                HStack {
                                    TextField("W mm", value: Binding(
                                        get: { modes[idx].widthMM },
                                        set: { modes[idx].widthMM = $0 }
                                    ), format: .number.grouping(.never))
                                        .frame(width: 70)
                                    TextField("H mm", value: Binding(
                                        get: { modes[idx].heightMM },
                                        set: { modes[idx].heightMM = $0 }
                                    ), format: .number.grouping(.never))
                                        .frame(width: 70)
                                }
                                TextField("Max FPS", value: Binding(
                                    get: { modes[idx].maxFPS },
                                    set: { modes[idx].maxFPS = $0 }
                                ), format: .number.grouping(.never))
                                    .frame(width: 80)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Button(action: { modes.append(ModeEntry()) }) {
                        Label("Add Mode", systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Camera") { addCamera() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(manufacturer.isEmpty || model.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 560)
    }

    private func addCamera() {
        let effectiveSensorName = sensorName.isEmpty ? "\(sensorWidthPx)x\(sensorHeightPx)" : sensorName
        let pixelPitch: Double = sensorWidthMM > 0 && sensorWidthPx > 0
            ? (sensorWidthMM / Double(sensorWidthPx)) * 1000.0
            : 0

        let recordingModes: [RecordingMode] = modes.compactMap { m in
            let w = max(1, m.widthPx)
            let h = max(1, m.heightPx)
            let wMM = m.widthMM > 0 ? m.widthMM : (sensorWidthMM * Double(w) / Double(sensorWidthPx))
            let hMM = m.heightMM > 0 ? m.heightMM : (sensorHeightMM * Double(h) / Double(sensorHeightPx))
            let name = m.name.isEmpty ? "\(w)x\(h)" : m.name
            return RecordingMode(
                id: "custom-mode-\(UUID().uuidString)",
                name: name,
                activePhotosites: Dimensions(width: w, height: h),
                activeImageAreaMM: PhysicalDimensions(width: wMM, height: hMM),
                maxFPS: max(1, m.maxFPS),
                codecOptions: [],
                source: .custom
            )
        }

        if recordingModes.isEmpty {
            let mode = RecordingMode(
                id: "custom-mode-\(UUID().uuidString)",
                name: "\(sensorWidthPx)x\(sensorHeightPx)",
                activePhotosites: Dimensions(width: sensorWidthPx, height: sensorHeightPx),
                activeImageAreaMM: PhysicalDimensions(width: sensorWidthMM, height: sensorHeightMM),
                maxFPS: 24,
                codecOptions: [],
                source: .custom
            )
            let camera = CameraSpec(
                id: "custom-\(UUID().uuidString)",
                manufacturer: manufacturer,
                model: model,
                sensor: SensorSpec(
                    name: effectiveSensorName,
                    photositeDimensions: Dimensions(width: sensorWidthPx, height: sensorHeightPx),
                    physicalDimensionsMM: PhysicalDimensions(width: sensorWidthMM, height: sensorHeightMM),
                    pixelPitchUM: pixelPitch
                ),
                recordingModes: [mode],
                source: .custom
            )
            cameraDBStore.addCustomCamera(camera)
        } else {
            let maxMode = recordingModes.max(by: {
                let lhs = $0.activePhotosites.width * $0.activePhotosites.height
                let rhs = $1.activePhotosites.width * $1.activePhotosites.height
                return lhs < rhs
            })!
            let camera = CameraSpec(
                id: "custom-\(UUID().uuidString)",
                manufacturer: manufacturer,
                model: model,
                sensor: SensorSpec(
                    name: effectiveSensorName,
                    photositeDimensions: maxMode.activePhotosites,
                    physicalDimensionsMM: PhysicalDimensions(width: sensorWidthMM, height: sensorHeightMM),
                    pixelPitchUM: pixelPitch
                ),
                recordingModes: recordingModes,
                source: .custom
            )
            cameraDBStore.addCustomCamera(camera)
        }
        dismiss()
    }
}

struct EditRecordingModeSheet: View {
    let mode: RecordingMode
    let onSave: (RecordingMode) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var widthPx: Int = 3840
    @State private var heightPx: Int = 2160
    @State private var widthMM: Double = 23.76
    @State private var heightMM: Double = 13.365
    @State private var maxFPS: Int = 24

    private var isModifiedFromSync: Bool {
        mode.source == .synced || mode.source == .modified
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Recording Mode")
                    .font(.headline)
                if isModifiedFromSync {
                    Text("(synced from API)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Form {
                Section("Mode") {
                    LabeledContent("Name") {
                        TextField("Mode name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Resolution") {
                        HStack(spacing: 8) {
                            TextField("W", value: $widthPx, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("\u{00D7}").foregroundStyle(.secondary)
                            TextField("H", value: $heightPx, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("px").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Sensor Area") {
                        HStack(spacing: 8) {
                            TextField("W", value: $widthMM, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("\u{00D7}").foregroundStyle(.secondary)
                            TextField("H", value: $heightMM, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            Text("mm").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Max FPS") {
                        TextField("FPS", value: $maxFPS, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }

                if mode.source == .modified, let snapshot = mode.syncedSnapshot {
                    Section("Original Synced Values") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            GridRow {
                                Text("Name").foregroundStyle(.secondary).font(.caption)
                                Text(snapshot.name).font(.caption)
                            }
                            GridRow {
                                Text("Resolution").foregroundStyle(.secondary).font(.caption)
                                Text(verbatim: "\(snapshot.resWidth) \u{00D7} \(snapshot.resHeight) px").font(.caption)
                            }
                            GridRow {
                                Text("Sensor Area").foregroundStyle(.secondary).font(.caption)
                                Text(String(format: "%.2f \u{00D7} %.2f mm", snapshot.sensorWidth, snapshot.sensorHeight)).font(.caption)
                            }
                        }
                        Button("Revert to Synced Values") {
                            name = snapshot.name
                            widthPx = snapshot.resWidth
                            heightPx = snapshot.resHeight
                            widthMM = snapshot.sensorWidth
                            heightMM = snapshot.sensorHeight
                            maxFPS = snapshot.maxFPS
                        }
                        .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear {
                name = mode.name
                widthPx = mode.activePhotosites.width
                heightPx = mode.activePhotosites.height
                widthMM = mode.activeImageAreaMM.width
                heightMM = mode.activeImageAreaMM.height
                maxFPS = mode.maxFPS
            }

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    var updated = RecordingMode(
                        id: mode.id,
                        name: name.isEmpty ? "\(widthPx)x\(heightPx)" : name,
                        activePhotosites: Dimensions(width: max(1, widthPx), height: max(1, heightPx)),
                        activeImageAreaMM: PhysicalDimensions(width: widthMM, height: heightMM),
                        maxFPS: max(1, maxFPS),
                        codecOptions: mode.codecOptions,
                        source: mode.source
                    )
                    if mode.source == .synced {
                        updated.source = .modified
                        updated.syncedSnapshot = RecordingModeSnapshot(from: mode)
                    } else if mode.source == .modified {
                        updated.source = .modified
                        updated.syncedSnapshot = mode.syncedSnapshot
                    }
                    onSave(updated)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 440)
    }
}

struct AddRecordingModeSheet: View {
    let sensorPhysicalMM: PhysicalDimensions
    let onAdd: (RecordingMode) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var widthPx = 3840
    @State private var heightPx = 2160
    @State private var widthMM = 23.76
    @State private var heightMM = 13.365
    @State private var maxFPS = 24

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Recording Mode")
                .font(.headline)
                .padding()

            Form {
                Section("Mode") {
                    TextField("Name", text: $name)
                    HStack {
                        TextField("Width (px)", value: $widthPx, format: .number.grouping(.never))
                        TextField("Height (px)", value: $heightPx, format: .number.grouping(.never))
                    }
                    HStack {
                        TextField("Width (mm)", value: $widthMM, format: .number.grouping(.never))
                        TextField("Height (mm)", value: $heightMM, format: .number.grouping(.never))
                    }
                    TextField("Max FPS", value: $maxFPS, format: .number.grouping(.never))
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") {
                    let effectiveName = name.isEmpty ? "\(widthPx)x\(heightPx)" : name
                    let mode = RecordingMode(
                        id: "custom-mode-\(UUID().uuidString)",
                        name: effectiveName,
                        activePhotosites: Dimensions(width: max(1, widthPx), height: max(1, heightPx)),
                        activeImageAreaMM: PhysicalDimensions(width: widthMM, height: heightMM),
                        maxFPS: max(1, maxFPS),
                        codecOptions: [],
                        source: .custom
                    )
                    onAdd(mode)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 360, height: 320)
    }
}

// MARK: - Sync Conflict Resolution

struct SyncConflictSheet: View {
    @ObservedObject var cameraDBStore: CameraDBStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Sync Conflicts Detected")
                    .font(.headline)
            }
            .padding()

            Text("Some recording modes you've edited have been updated in the remote database.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Divider().padding(.vertical, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(cameraDBStore.pendingConflicts) { conflict in
                        ConflictRow(conflict: conflict, cameraDBStore: cameraDBStore)
                    }
                }
                .padding()
            }

            Divider()

            HStack {
                Button("Keep All Local") {
                    cameraDBStore.resolveAllConflicts(resolution: .keepLocal)
                    dismiss()
                }
                Spacer()
                Button("Accept All Remote") {
                    cameraDBStore.resolveAllConflicts(resolution: .acceptRemote)
                    dismiss()
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!cameraDBStore.pendingConflicts.isEmpty)
            }
            .padding()
        }
        .frame(width: 560, height: 480)
    }
}

struct ConflictRow: View {
    let conflict: SyncConflict
    @ObservedObject var cameraDBStore: CameraDBStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(conflict.cameraLabel)
                .font(.subheadline.weight(.semibold))
            Text("Mode: \(conflict.localMode.name)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Version")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    modeDetails(conflict.localMode)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Remote Version")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                    modeDetails(conflict.remoteMode)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(6)
            }

            HStack(spacing: 12) {
                Button("Keep Local") {
                    cameraDBStore.resolveConflict(conflict, resolution: .keepLocal)
                }
                .font(.caption)

                Button("Accept Remote") {
                    cameraDBStore.resolveConflict(conflict, resolution: .acceptRemote)
                }
                .font(.caption)
            }

            Divider()
        }
    }

    @ViewBuilder
    private func modeDetails(_ mode: RecordingMode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(mode.activePhotosites.width) \u{00D7} \(mode.activePhotosites.height) px")
                .font(.caption)
            Text(verbatim: String(format: "%.2f \u{00D7} %.2f mm",
                        mode.activeImageAreaMM.width,
                        mode.activeImageAreaMM.height))
                .font(.caption)
            if mode.maxFPS > 0 {
                Text("\(mode.maxFPS) fps")
                    .font(.caption)
            }
        }
    }
}
