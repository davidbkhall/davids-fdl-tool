import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    private static let keychainService = "com.fdltool.credentials"
    private static let cinedPasswordAccount = "cinedPassword"

    @Published var selectedTool: Tool = .library
    @Published var currentProject: Project?
    @Published var pythonBridgeStatus: BridgeStatus = .stopped

    /// Persists the selected Library section across navigation.
    @Published var librarySelectedSection: LibrarySection = .projects

    enum LibrarySection: String, CaseIterable {
        case projects = "Projects"
        case templates = "Canvas Templates"
    }

    /// Default creator name used when generating new FDLs (persisted to UserDefaults).
    @Published var defaultCreator: String {
        didSet { UserDefaults.standard.set(defaultCreator, forKey: "defaultCreator") }
    }

    /// CineD credentials for camera database sync (persisted to UserDefaults).
    @Published var cinedEmail: String {
        didSet { UserDefaults.standard.set(cinedEmail, forKey: "cinedEmail") }
    }
    @Published var cinedPassword: String {
        didSet {
            KeychainStore.setString(
                cinedPassword,
                service: Self.keychainService,
                account: Self.cinedPasswordAccount
            )
            // Cleanup legacy plain-text storage.
            UserDefaults.standard.removeObject(forKey: "cinedPassword")
        }
    }

    var isCinedPasswordStoredInKeychain: Bool {
        guard let value = KeychainStore.getString(
            service: Self.keychainService,
            account: Self.cinedPasswordAccount
        ) else { return false }
        return !value.isEmpty
    }

    var hasLegacyCinedPasswordInUserDefaults: Bool {
        let legacy = UserDefaults.standard.string(forKey: "cinedPassword") ?? ""
        return !legacy.isEmpty
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
    let cinedSyncService = CineDSyncService()

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

    lazy var viewerViewModel: ViewerViewModel = {
        ViewerViewModel()
    }()

    enum BridgeStatus: String {
        case stopped, starting, running, error
    }

    var isBridgeReady: Bool { pythonBridgeStatus == .running }

    private var nestedCancellables = Set<AnyCancellable>()

    init() {
        self.pythonBridge = PythonBridge()
        self.libraryStore = LibraryStore()
        self.cameraDBStore = CameraDBStore()
        self.defaultCreator = UserDefaults.standard.string(forKey: "defaultCreator") ?? "FDL Tool"
        self.cinedEmail = UserDefaults.standard.string(forKey: "cinedEmail") ?? ""
        if let keychainPassword = KeychainStore.getString(
            service: Self.keychainService,
            account: Self.cinedPasswordAccount
        ) {
            self.cinedPassword = keychainPassword
        } else {
            // One-time migration from legacy UserDefaults storage.
            let legacyPassword = UserDefaults.standard.string(forKey: "cinedPassword") ?? ""
            self.cinedPassword = legacyPassword
            if !legacyPassword.isEmpty {
                KeychainStore.setString(
                    legacyPassword,
                    service: Self.keychainService,
                    account: Self.cinedPasswordAccount
                )
                UserDefaults.standard.removeObject(forKey: "cinedPassword")
            }
        }
    }

    /// Forward objectWillChange from nested ViewModels so SwiftUI views
    /// that observe AppState also react to changes in those children.
    func wireUpNestedObservables() {
        canvasTemplateViewModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &nestedCancellables)
        libraryViewModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &nestedCancellables)
    }

    func startServices() async {
        wireUpNestedObservables()
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
