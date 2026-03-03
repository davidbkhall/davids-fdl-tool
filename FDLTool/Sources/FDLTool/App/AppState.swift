import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var selectedTool: Tool = .library
    @Published var currentProject: Project?
    @Published var pythonBridgeStatus: BridgeStatus = .stopped

    /// Default creator name used when generating new FDLs (persisted to UserDefaults).
    @Published var defaultCreator: String {
        didSet { UserDefaults.standard.set(defaultCreator, forKey: "defaultCreator") }
    }

    /// Surfaced to the user as a blocking alert when the bridge fails.
    @Published var pythonBridgeError: String?

    /// URL pending open via Cmd+O or system file association; ViewerView observes this.
    @Published var pendingOpenURL: URL?
    /// In-memory FDL document pending load in the Viewer (e.g. from Chart Generator).
    @Published var pendingFDLDocument: FDLDocument?
    @Published var pendingFDLFileName: String?
    /// Triggers the file-open panel from the menu bar command.
    @Published var showOpenFDLPanel = false

    let pythonBridge: PythonBridge
    let libraryStore: LibraryStore
    let cameraDBStore: CameraDBStore
    let cameraDBSyncService = CameraDBSyncService()

    // ViewModels (lazy-initialized after services are ready)
    lazy var libraryViewModel: LibraryViewModel = {
        LibraryViewModel(libraryStore: libraryStore, pythonBridge: pythonBridge)
    }()

    lazy var canvasTemplateViewModel: CanvasTemplateViewModel = {
        CanvasTemplateViewModel(libraryStore: libraryStore, pythonBridge: pythonBridge)
    }()

    lazy var chartGeneratorViewModel: ChartGeneratorViewModel = {
        ChartGeneratorViewModel(pythonBridge: pythonBridge, cameraDBStore: cameraDBStore, libraryStore: libraryStore)
    }()

    lazy var clipIDViewModel: ClipIDViewModel = {
        ClipIDViewModel(pythonBridge: pythonBridge, libraryStore: libraryStore)
    }()

    enum BridgeStatus: String {
        case stopped, starting, running, error
    }

    var isBridgeReady: Bool { pythonBridgeStatus == .running }

    init() {
        self.pythonBridge = PythonBridge()
        self.libraryStore = LibraryStore()
        self.cameraDBStore = CameraDBStore()
        self.defaultCreator = UserDefaults.standard.string(forKey: "defaultCreator") ?? "FDL Tool"
    }

    func startServices() async {
        cameraDBStore.loadBundled()

        pythonBridgeStatus = .starting
        pythonBridgeError = nil
        do {
            try await pythonBridge.start()
            pythonBridgeStatus = .running
        } catch {
            pythonBridgeStatus = .error
            pythonBridgeError = error.localizedDescription
        }
    }

    func restartPythonBridge() async {
        await pythonBridge.shutdown()
        pythonBridgeStatus = .stopped
        pythonBridgeError = nil
        do {
            try await pythonBridge.start()
            pythonBridgeStatus = .running
        } catch {
            pythonBridgeStatus = .error
            pythonBridgeError = error.localizedDescription
        }
    }

    func shutdownPythonBridge() async {
        await pythonBridge.shutdown()
        pythonBridgeStatus = .stopped
    }
}
