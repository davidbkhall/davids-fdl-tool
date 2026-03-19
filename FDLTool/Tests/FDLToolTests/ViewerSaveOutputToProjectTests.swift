import XCTest
@testable import FDLTool

@MainActor
final class ViewerSaveOutputToProjectTests: XCTestCase {
    func testSaveOutputToProjectAddsUsesTemplateAndDerivedFromInSameProject() throws {
        let store = LibraryStore()
        let project = try store.createProject(name: "ViewerSave-\(UUID().uuidString)", description: "test")
        defer { try? store.deleteProject(id: project.id) }

        let sourceEntry = try makeSourceEntry(projectID: project.id, store: store, name: "Source")
        let vm = ViewerViewModel()
        vm.templateConfig = CanvasTemplateConfig(id: "tpl-test", label: "Template A")
        vm.outputDocument = makeOutputDocument(id: UUID().uuidString)
        vm.outputRawJSON = FDLJSONSerializer.string(from: vm.outputDocument!)

        let lvm = LibraryViewModel(libraryStore: store, pythonBridge: PythonBridge())
        vm.saveOutputToProject(
            projectID: project.id,
            libraryStore: store,
            libraryViewModel: lvm,
            sourceEntryID: sourceEntry.id,
            sourceProjectID: project.id
        )

        let entries = try store.fdlEntries(forProject: project.id)
        let outputEntry = try XCTUnwrap(entries.first(where: { $0.sourceTool == "viewer_output" }))

        let links = try store.assetLinks(forProject: project.id)
        XCTAssertTrue(links.contains(where: {
            $0.fromAssetID == "asset-fdl-\(outputEntry.id)" &&
            $0.toAssetID == "asset-template-\(project.id)-tpl-test" &&
            $0.linkType == .usesTemplate
        }))
        XCTAssertTrue(links.contains(where: {
            $0.fromAssetID == "asset-fdl-\(outputEntry.id)" &&
            $0.toAssetID == "asset-fdl-\(sourceEntry.id)" &&
            $0.linkType == .derivedFrom
        }))
    }

    func testSaveOutputToProjectDoesNotLinkDerivedFromAcrossProjects() throws {
        let store = LibraryStore()
        let sourceProject = try store.createProject(name: "ViewerSource-\(UUID().uuidString)", description: "test")
        let outputProject = try store.createProject(name: "ViewerOutput-\(UUID().uuidString)", description: "test")
        defer {
            try? store.deleteProject(id: sourceProject.id)
            try? store.deleteProject(id: outputProject.id)
        }

        let sourceEntry = try makeSourceEntry(projectID: sourceProject.id, store: store, name: "Source Cross Project")

        let vm = ViewerViewModel()
        vm.templateConfig = CanvasTemplateConfig(id: "tpl-cross", label: "Template Cross")
        vm.outputDocument = makeOutputDocument(id: UUID().uuidString)
        vm.outputRawJSON = FDLJSONSerializer.string(from: vm.outputDocument!)

        let lvm = LibraryViewModel(libraryStore: store, pythonBridge: PythonBridge())
        vm.saveOutputToProject(
            projectID: outputProject.id,
            libraryStore: store,
            libraryViewModel: lvm,
            sourceEntryID: sourceEntry.id,
            sourceProjectID: sourceProject.id
        )

        let outputEntries = try store.fdlEntries(forProject: outputProject.id)
        let outputEntry = try XCTUnwrap(outputEntries.first(where: { $0.sourceTool == "viewer_output" }))

        let links = try store.assetLinks(forProject: outputProject.id)
        XCTAssertTrue(links.contains(where: {
            $0.fromAssetID == "asset-fdl-\(outputEntry.id)" &&
            $0.toAssetID == "asset-template-\(outputProject.id)-tpl-cross" &&
            $0.linkType == .usesTemplate
        }))
        XCTAssertFalse(links.contains(where: { $0.linkType == .derivedFrom }))
    }

    private func makeSourceEntry(projectID: String, store: LibraryStore, name: String) throws -> FDLEntry {
        let entry = FDLEntry(
            projectID: projectID,
            fdlUUID: UUID().uuidString,
            name: name,
            filePath: "",
            sourceTool: "library_import",
            tags: ["source"]
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
        return entry
    }

    private func makeOutputDocument(id: String) -> FDLDocument {
        FDLDocument(
            id: id,
            version: FDLVersion(major: 2, minor: 0),
            fdlCreator: "FDL Tool",
            defaultFramingIntent: nil,
            framingIntents: nil,
            contexts: [],
            canvasTemplates: nil
        )
    }
}
