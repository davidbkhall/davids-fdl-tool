import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var selectedTool: Tool = .library
    @Published var currentProject: Project?
    @Published var pythonBridgeStatus: BridgeStatus = .stopped

    let pythonBridge: PythonBridge
    let libraryStore: LibraryStore
    let cameraDBStore: CameraDBStore

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
        case stopped = "Stopped"
        case starting = "Starting"
        case running = "Running"
        case error = "Error"
    }

    init() {
        self.pythonBridge = PythonBridge()
        self.libraryStore = LibraryStore()
        self.cameraDBStore = CameraDBStore()
    }

    func startServices() async {
        // Load camera database
        cameraDBStore.loadBundled()

        // Start Python bridge
        pythonBridgeStatus = .starting
        do {
            try await pythonBridge.start()
            pythonBridgeStatus = .running
        } catch {
            pythonBridgeStatus = .error
            print("Failed to start Python bridge: \(error)")
        }
    }

    func shutdownPythonBridge() async {
        await pythonBridge.shutdown()
        pythonBridgeStatus = .stopped
    }
}
