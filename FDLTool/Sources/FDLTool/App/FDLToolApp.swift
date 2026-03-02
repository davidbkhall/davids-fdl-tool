import SwiftUI

@main
struct FDLToolApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    await appState.startServices()
                }
        }
        .commands {
            // File menu
            CommandGroup(after: .newItem) {
                Button("New Project...") {
                    appState.selectedTool = .library
                    appState.libraryViewModel.showProjectCreation = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Import FDL...") {
                    appState.selectedTool = .library
                    appState.libraryViewModel.showImportSheet = true
                }
                .keyboardShortcut("i", modifiers: [.command])

                Divider()

                Button("Open FDL File...") {
                    appState.selectedTool = .viewer
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            // View menu — tool navigation
            CommandGroup(after: .sidebar) {
                Divider()

                ForEach(Tool.allCases) { tool in
                    Button(tool.rawValue) {
                        appState.selectedTool = tool
                    }
                    .keyboardShortcut(tool.shortcutKey, modifiers: [.command])
                }
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Link("ASC FDL Specification",
                     destination: URL(string: "https://github.com/ascmitc/fdl")!)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedTool: $appState.selectedTool,
                bridgeStatus: appState.pythonBridgeStatus,
                cameraCount: appState.cameraDBStore.cameras.count
            )
        } detail: {
            detailView
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedTool {
        case .library:
            LibraryView()
        case .chartGenerator:
            ChartGeneratorView()
        case .viewer:
            ViewerView()
        case .clipID:
            ClipIDView()
        case .cameraDB:
            CameraDatabaseView()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var pythonPath = ""
    @State private var cameraDBPath = ""

    var body: some View {
        TabView {
            Form {
                Section("Python Backend") {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(appState.pythonBridgeStatus.rawValue)
                        }
                    }

                    TextField("Python Backend Path", text: $pythonPath)
                        .textFieldStyle(.roundedBorder)
                    Text("Set FDL_PYTHON_BACKEND environment variable to override.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Restart Python Bridge") {
                            Task {
                                await appState.shutdownPythonBridge()
                                await appState.startServices()
                            }
                        }
                    }
                }

                Section("Camera Database") {
                    LabeledContent("Cameras Loaded") {
                        Text("\(appState.cameraDBStore.cameras.count)")
                    }
                    if !appState.cameraDBStore.databaseVersion.isEmpty {
                        LabeledContent("Version") {
                            Text(appState.cameraDBStore.databaseVersion)
                        }
                    }
                    TextField("Custom Camera DB Path", text: $cameraDBPath)
                        .textFieldStyle(.roundedBorder)
                    Text("Set FDL_CAMERA_DB environment variable to override.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Storage") {
                    LabeledContent("Database") {
                        Text(LibraryStore.databaseURL.path)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Projects") {
                        Text(LibraryStore.appSupportURL.appendingPathComponent("projects").path)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 500, height: 400)
    }

    private var statusColor: Color {
        switch appState.pythonBridgeStatus {
        case .stopped: return .gray
        case .starting: return .orange
        case .running: return .green
        case .error: return .red
        }
    }
}
