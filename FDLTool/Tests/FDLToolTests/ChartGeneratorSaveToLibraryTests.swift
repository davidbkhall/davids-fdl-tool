import XCTest
@testable import FDLTool

@MainActor
final class ChartGeneratorSaveToLibraryTests: XCTestCase {
    func testSaveToLibrarySuccessPersistsEntryAndTelemetry() async throws {
        let store = LibraryStore()
        let project = try store.createProject(name: "SaveSuccess-\(UUID().uuidString)", description: "test")
        defer { try? store.deleteProject(id: project.id) }

        let vm = ChartGeneratorViewModel(
            pythonBridge: PythonBridge(),
            cameraDBStore: CameraDBStore(),
            libraryStore: store
        )
        vm.chartTitle = "Chart Save Success"
        vm.errorMessage = nil

        let requestID = "save-success-\(UUID().uuidString)"
        await vm.saveToLibrary(
            projectID: project.id,
            projectName: project.name,
            requestID: requestID,
            generateFDL: {
                [
                    "fdl": [
                        "uuid": UUID().uuidString,
                        "version": ["major": 2, "minor": 0],
                        "contexts": [],
                    ],
                ]
            }
        )

        XCTAssertEqual(vm.saveStatusMessage, "Saved to Library.\nProject: \(project.name)")
        XCTAssertNil(vm.errorMessage)

        let entries = try store.fdlEntries(forProject: project.id)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "Chart Save Success")
        let savedEntry = try XCTUnwrap(entries.first)

        let assets = try store.projectAssets(forProject: project.id)
        let chartAsset = try XCTUnwrap(assets.first(where: {
            $0.assetType == .chart && $0.referenceID == savedEntry.id
        }))
        let links = try store.assetLinks(forProject: project.id)
        XCTAssertTrue(links.contains(where: {
            $0.fromAssetID == "asset-fdl-\(savedEntry.id)" &&
            $0.toAssetID == chartAsset.id &&
            $0.linkType == .derivedFrom
        }))

        let trace = exportTraceText()
        XCTAssertTrue(trace.contains("\"event\":\"save_to_library_started\""))
        XCTAssertTrue(trace.contains("\"event\":\"save_to_library_complete\""))
        XCTAssertTrue(trace.contains("\"request_id\":\"\(requestID)\""))
    }

    func testSaveToLibraryMissingPayloadSetsFailureMessageAndTelemetry() async throws {
        let store = LibraryStore()
        let project = try store.createProject(name: "SaveMissing-\(UUID().uuidString)", description: "test")
        defer { try? store.deleteProject(id: project.id) }

        let vm = ChartGeneratorViewModel(
            pythonBridge: PythonBridge(),
            cameraDBStore: CameraDBStore(),
            libraryStore: store
        )

        let requestID = "save-missing-\(UUID().uuidString)"
        await vm.saveToLibrary(
            projectID: project.id,
            projectName: project.name,
            requestID: requestID,
            generateFDL: { [:] }
        )

        XCTAssertNil(vm.saveStatusMessage)
        XCTAssertEqual(vm.errorMessage, "Save to Library failed.\nReason: Generated FDL payload missing.")
        XCTAssertTrue((try store.fdlEntries(forProject: project.id)).isEmpty)

        let trace = exportTraceText()
        XCTAssertTrue(trace.contains("\"event\":\"save_to_library_failed\""))
        XCTAssertTrue(trace.contains("\"reason\":\"generated_fdl_missing\""))
        XCTAssertTrue(trace.contains("\"request_id\":\"\(requestID)\""))
    }

    func testSaveToLibraryThrownErrorUsesMappedReasonAndFailureTelemetry() async throws {
        let store = LibraryStore()
        let project = try store.createProject(name: "SaveError-\(UUID().uuidString)", description: "test")
        defer { try? store.deleteProject(id: project.id) }

        let vm = ChartGeneratorViewModel(
            pythonBridge: PythonBridge(),
            cameraDBStore: CameraDBStore(),
            libraryStore: store
        )

        let requestID = "save-error-\(UUID().uuidString)"
        await vm.saveToLibrary(
            projectID: project.id,
            projectName: project.name,
            requestID: requestID,
            generateFDL: {
                throw PythonBridgeError.notStarted
            }
        )

        XCTAssertNil(vm.saveStatusMessage)
        XCTAssertEqual(vm.errorMessage, "Save to Library failed.\nReason: Python bridge not started")
        XCTAssertTrue((try store.fdlEntries(forProject: project.id)).isEmpty)

        let trace = exportTraceText()
        XCTAssertTrue(trace.contains("\"event\":\"save_to_library_failed\""))
        XCTAssertTrue(trace.contains("\"reason\":\"Python bridge not started\""))
        XCTAssertTrue(trace.contains("\"request_id\":\"\(requestID)\""))
    }

    private func exportTraceText() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FDLTool", isDirectory: true)
        guard let url = dir?.appendingPathComponent("export_trace.log") else {
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
