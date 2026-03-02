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
}
