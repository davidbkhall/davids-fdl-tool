import XCTest
@testable import FDLTool

final class LibraryStoreTests: XCTestCase {

    func testProjectModel() {
        let project = Project(name: "Test Project", description: "A test")
        XCTAssertFalse(project.id.isEmpty)
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.description, "A test")
    }

    func testFDLEntryModel() {
        let entry = FDLEntry(
            projectID: "proj-1",
            fdlUUID: "fdl-1",
            name: "Test FDL",
            filePath: "/test/path.fdl.json",
            sourceTool: "chart_generator",
            tags: ["scope", "4k"]
        )
        XCTAssertFalse(entry.id.isEmpty)
        XCTAssertEqual(entry.projectID, "proj-1")
        XCTAssertEqual(entry.tags, ["scope", "4k"])
    }

    func testCanvasTemplateModel() {
        let template = CanvasTemplate(
            name: "UHD Deliverable",
            description: "3840x2160 UHD output",
            templateJSON: "{\"pipeline\":[]}",
            source: "manual"
        )
        XCTAssertFalse(template.id.isEmpty)
        XCTAssertEqual(template.name, "UHD Deliverable")
    }

    func testProjectAssetModel() {
        let asset = ProjectAsset(
            projectID: "proj-1",
            assetType: .template,
            name: "Template A",
            sourceTool: "viewer",
            referenceID: "tpl-1",
            filePath: "/tmp/template.json",
            payloadJSON: "{\"k\":\"v\"}"
        )
        XCTAssertFalse(asset.id.isEmpty)
        XCTAssertEqual(asset.projectID, "proj-1")
        XCTAssertEqual(asset.assetType, .template)
        XCTAssertEqual(asset.name, "Template A")
    }

    func testProjectAssetLinkModel() {
        let link = ProjectAssetLink(
            projectID: "proj-1",
            fromAssetID: "asset-a",
            toAssetID: "asset-b",
            linkType: .usesTemplate
        )
        XCTAssertFalse(link.id.isEmpty)
        XCTAssertEqual(link.projectID, "proj-1")
        XCTAssertEqual(link.linkType, .usesTemplate)
    }

    func testProjectCameraModeAssignmentModel() {
        let assignment = ProjectCameraModeAssignment(
            projectID: "proj-1",
            cameraModelID: "cam-1",
            cameraModelName: "ALEXA 35",
            recordingModeID: "mode-1",
            recordingModeName: "4.6K 3:2 Open Gate",
            source: "camera_db",
            notes: "Primary capture mode"
        )
        XCTAssertFalse(assignment.id.isEmpty)
        XCTAssertEqual(assignment.projectID, "proj-1")
        XCTAssertEqual(assignment.cameraModelName, "ALEXA 35")
        XCTAssertEqual(assignment.recordingModeName, "4.6K 3:2 Open Gate")
    }


    @MainActor
    func testAddFDLEntryPersistsFileAndProjectAsset() throws {
        let store = LibraryStore()
        let project = try store.createProject(name: "SaveReliability-\(UUID().uuidString)", description: "test")
        defer { try? store.deleteProject(id: project.id) }

        let entry = FDLEntry(
            projectID: project.id,
            fdlUUID: UUID().uuidString,
            name: "Chart Output",
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

        let entries = try store.fdlEntries(forProject: project.id)
        XCTAssertNotNil(entries.first(where: { $0.id == entry.id }))

        let fileURL = LibraryStore.projectDirectoryURL(projectID: project.id)
            .appendingPathComponent("\(entry.id).fdl.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        let writtenData = try Data(contentsOf: fileURL)
        XCTAssertEqual(writtenData, json)

        let assets = try store.projectAssets(forProject: project.id, ofType: .fdl)
        let fdlAsset = try XCTUnwrap(assets.first(where: { $0.referenceID == entry.id }))
        XCTAssertEqual(fdlAsset.assetType, .fdl)
        XCTAssertEqual(fdlAsset.sourceTool, "chart_generator")
        XCTAssertEqual(fdlAsset.filePath, fileURL.path)
    }

    @MainActor
    func testAddFDLEntryPersistsTags() throws {
        let store = LibraryStore()
        let project = try store.createProject(name: "TagReliability-\(UUID().uuidString)", description: "test")
        defer { try? store.deleteProject(id: project.id) }

        let entry = FDLEntry(
            projectID: project.id,
            fdlUUID: UUID().uuidString,
            name: "Tagged Output",
            filePath: "",
            sourceTool: "chart_generator",
            tags: ["chart", "scope", "deliverable"]
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
        let saved = try store.fdlEntries(forProject: project.id)
        let loaded = try XCTUnwrap(saved.first(where: { $0.id == entry.id }))
        XCTAssertEqual(Set(loaded.tags), Set(["chart", "scope", "deliverable"]))
    }



    @MainActor
    func testDeleteFDLEntryRemovesFileAndGraphAsset() throws {
        let store = LibraryStore()
        let project = try store.createProject(name: "DeleteReliability-\(UUID().uuidString)", description: "test")
        defer { try? store.deleteProject(id: project.id) }

        let entry = FDLEntry(
            projectID: project.id,
            fdlUUID: UUID().uuidString,
            name: "Delete Me",
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

        let fdlAssetID = "asset-fdl-\(entry.id)"
        let otherAsset = ProjectAsset(
            projectID: project.id,
            assetType: .chart,
            name: "Derived Chart",
            sourceTool: "chart_generator",
            referenceID: "chart-1",
            filePath: nil,
            payloadJSON: nil
        )
        try store.saveProjectAsset(otherAsset)
        try store.linkAssets(ProjectAssetLink(
            projectID: project.id,
            fromAssetID: fdlAssetID,
            toAssetID: otherAsset.id,
            linkType: .inputOf
        ))

        try store.deleteFDLEntry(id: entry.id, projectID: project.id)

        let fileURL = LibraryStore.projectDirectoryURL(projectID: project.id)
            .appendingPathComponent("\(entry.id).fdl.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        let entries = try store.fdlEntries(forProject: project.id)
        XCTAssertNil(entries.first(where: { $0.id == entry.id }))

        let assets = try store.projectAssets(forProject: project.id)
        XCTAssertNil(assets.first(where: { $0.id == fdlAssetID }))

        let links = try store.assetLinks(forProject: project.id)
        XCTAssertNil(links.first(where: { $0.fromAssetID == fdlAssetID || $0.toAssetID == fdlAssetID }))
    }

}
