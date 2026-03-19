import XCTest
@testable import FDLTool

@MainActor
final class LibraryViewModelTests: XCTestCase {

    func testLoadEntriesClearsStaleSelectionAndDetailState() throws {
        let store = LibraryStore()
        let project = try store.createProject(name: "LibraryVM-\(UUID().uuidString)", description: "test")
        defer { try? store.deleteProject(id: project.id) }

        let entry = FDLEntry(
            projectID: project.id,
            fdlUUID: UUID().uuidString,
            name: "State Test",
            filePath: "",
            sourceTool: "chart_generator",
            tags: ["chart"]
        )
        let json = try XCTUnwrap(
            """
            {
              "uuid": "\(entry.fdlUUID)",
              "version": {"major": 2, "minor": 0},
              "contexts": []
            }
            """.data(using: .utf8)
        )
        try store.addFDLEntry(entry, jsonData: json)

        let vm = LibraryViewModel(libraryStore: store, pythonBridge: PythonBridge())
        vm.selectProject(project)
        vm.selectedEntry = entry
        vm.parsedDocument = FDLDocument(
            id: UUID().uuidString,
            version: FDLVersion(major: 2, minor: 0),
            fdlCreator: "test",
            defaultFramingIntent: nil,
            framingIntents: nil,
            contexts: [],
            canvasTemplates: nil
        )
        vm.validationResult = ValidationResult(valid: true, errors: [], warnings: [])

        try store.deleteFDLEntry(id: entry.id, projectID: project.id)
        vm.loadEntries()

        XCTAssertNil(vm.selectedEntry)
        XCTAssertNil(vm.parsedDocument)
        XCTAssertNil(vm.validationResult)
        XCTAssertTrue(vm.fdlEntries.isEmpty)
    }

    func testLoadEntriesKeepsValidSelection() throws {
        let store = LibraryStore()
        let project = try store.createProject(name: "LibraryVM-Keep-\(UUID().uuidString)", description: "test")
        defer { try? store.deleteProject(id: project.id) }

        let entry = FDLEntry(
            projectID: project.id,
            fdlUUID: UUID().uuidString,
            name: "Keep Selection",
            filePath: "",
            sourceTool: "chart_generator",
            tags: ["chart"]
        )
        let json = try XCTUnwrap(
            """
            {
              "uuid": "\(entry.fdlUUID)",
              "version": {"major": 2, "minor": 0},
              "contexts": []
            }
            """.data(using: .utf8)
        )
        try store.addFDLEntry(entry, jsonData: json)

        let vm = LibraryViewModel(libraryStore: store, pythonBridge: PythonBridge())
        vm.selectProject(project)
        vm.selectedEntry = entry

        vm.loadEntries()

        XCTAssertEqual(vm.selectedEntry?.id, entry.id)
        XCTAssertEqual(vm.fdlEntries.count, 1)
    }
}
