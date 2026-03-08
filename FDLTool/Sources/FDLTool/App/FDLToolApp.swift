import SwiftUI
import AppKit
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct FDLToolApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(idealWidth: 1200, idealHeight: 750)
                .environmentObject(appState)
                .task {
                    await appState.startServices()
                }
                .fileImporter(
                    isPresented: $appState.showOpenFDLPanel,
                    allowedContentTypes: [.fdl, .json, .data],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        appState.selectedTool = .viewer
                        appState.pendingOpenURL = url
                    }
                }
                .onOpenURL { url in
                    appState.selectedTool = .viewer
                    appState.pendingOpenURL = url
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
                    appState.showOpenFDLPanel = true
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
        ZStack {
            NavigationSplitView {
                SidebarView(selectedTool: $appState.selectedTool)
            } detail: {
                detailView
            }
            .frame(minWidth: 1000, minHeight: 650)

            // Blocking overlay when Python bridge fails
            if appState.pythonBridgeStatus == .error {
                bridgeErrorOverlay
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedTool {
        case .library:
            LibraryView()
        case .chartGenerator:
            ChartGeneratorView()
        case .viewer:
            ViewerView(viewModel: appState.viewerViewModel)
        case .clipID:
            ClipIDView()
        case .cameraDB:
            CameraDatabaseView()
        }
    }

    @ViewBuilder
    private var bridgeErrorOverlay: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.yellow)

                Text("Python Backend Unavailable")
                    .font(.title2.weight(.semibold))

                Text(
                    "FDL Tool requires Python 3.10+ with the fdl package.\n"
                    + "The backend failed to start and core features will not work."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)

                if let error = appState.pythonBridgeError {
                    GroupBox {
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: 400)
                }

                HStack(spacing: 12) {
                    Button("Retry") {
                        Task { await appState.restartPythonBridge() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Continue Anyway") {
                        appState.pythonBridgeError = nil
                        appState.pythonBridgeStatus = .stopped
                    }
                }
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Default Creator") {
                    TextField(
                        "Creator name",
                        text: $appState.defaultCreator
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                }
                Text(
                    "Used as the fdl_creator when generating new FDL documents"
                    + " (e.g. from the Framing Chart Generator)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("Camera data is sourced from bundled data, MatchMove Machine API, and CineD Camera Database.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        Link("camdb.matchmovemachine.com",
                             destination: URL(string: "https://camdb.matchmovemachine.com/")!)
                            .font(.caption)
                        Link("cined.com/camera-database",
                             destination: URL(string: "https://www.cined.com/camera-database/")!)
                            .font(.caption)
                    }
                }
            }

            Section("CineD Credentials") {
                LabeledContent("Email") {
                    TextField("CineD email", text: $appState.cinedEmail)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                LabeledContent("Password") {
                    SecureField("CineD password", text: $appState.cinedPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                LabeledContent("Storage") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(appState.isCinedPasswordStoredInKeychain ? .green : .orange)
                            .frame(width: 8, height: 8)
                        Text(appState.isCinedPasswordStoredInKeychain ? "Keychain" : "Not saved")
                            .font(.caption)
                        if appState.hasLegacyCinedPasswordInUserDefaults {
                            Text("(legacy plaintext found)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Text("Optional. Required if CineD restricts access to full camera database content. Credentials are stored locally.")
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

            Section("Troubleshooting") {
                LabeledContent("Python Backend") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.isBridgeReady ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(appState.isBridgeReady ? "Active" : "Inactive")
                    }
                }

                if let error = appState.pythonBridgeError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button("Restart Python Backend") {
                    Task { await appState.restartPythonBridge() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
    }
}
