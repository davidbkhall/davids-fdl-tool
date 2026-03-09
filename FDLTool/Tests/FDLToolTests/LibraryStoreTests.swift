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
}
