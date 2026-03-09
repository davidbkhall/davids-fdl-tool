import XCTest
@testable import FDLTool

@MainActor
final class ViewerViewModelTests: XCTestCase {
    func testOutputContextCreatorWithoutDefault() {
        let viewModel = ViewerViewModel()
        XCTAssertEqual(viewModel.outputContextCreator(defaultCreator: ""), "FDL Tool v1.0")
    }

    func testOutputContextCreatorWithDefault() {
        let viewModel = ViewerViewModel()
        XCTAssertEqual(
            viewModel.outputContextCreator(defaultCreator: "David Hall"),
            "FDL Tool v1.0 - David Hall"
        )
    }

    func testMakeTransformInfoIncludesSourceAndOutputDimensions() {
        let viewModel = ViewerViewModel()
        let sourceFD = FDLFramingDecision(
            id: "fd-1",
            label: nil,
            framingIntentId: nil,
            dimensions: FDLDimensions(width: 3800, height: 2000),
            anchorPoint: nil,
            protectionDimensions: nil,
            protectionAnchorPoint: nil
        )
        let sourceCanvas = FDLCanvas(
            id: "canvas-src",
            label: nil,
            sourceCanvasId: nil,
            dimensions: FDLDimensions(width: 4000, height: 2160),
            effectiveDimensions: nil,
            effectiveAnchorPoint: nil,
            photositeDimensions: nil,
            physicalDimensions: nil,
            anamorphicSqueeze: 1.0,
            framingDecisions: [sourceFD]
        )

        let outputFD = FDLFramingDecision(
            id: "fd-out",
            label: nil,
            framingIntentId: nil,
            dimensions: FDLDimensions(width: 2000, height: 1080),
            anchorPoint: nil,
            protectionDimensions: nil,
            protectionAnchorPoint: nil
        )
        let outputCanvas = FDLCanvas(
            id: "canvas-out",
            label: nil,
            sourceCanvasId: "canvas-src",
            dimensions: FDLDimensions(width: 2048, height: 1152),
            effectiveDimensions: nil,
            effectiveAnchorPoint: nil,
            photositeDimensions: nil,
            physicalDimensions: nil,
            anamorphicSqueeze: 1.0,
            framingDecisions: [outputFD]
        )
        let outputDoc = FDLDocument(
            id: "doc-out",
            version: FDLVersion(major: 2, minor: 0),
            fdlCreator: "FDL Tool",
            defaultFramingIntent: nil,
            framingIntents: nil,
            contexts: [
                FDLContext(label: "Output", contextCreator: "FDL Tool", canvases: [outputCanvas])
            ],
            canvasTemplates: nil
        )

        let info = viewModel.makeTransformInfo(
            sourceCanvas: sourceCanvas,
            sourceFramingDecision: sourceFD,
            outputDocument: outputDoc
        )

        XCTAssertEqual(info.sourceCanvas, "4000×2160")
        XCTAssertEqual(info.sourceFraming, "3800×2000")
        XCTAssertEqual(info.outputCanvas, "2048×1152")
        XCTAssertEqual(info.outputFraming, "2000×1080")
    }

    func testScenarioPresetExistsAndApplies() {
        let viewModel = ViewerViewModel()
        XCTAssertTrue(
            TemplatePresets.scenarioContexts.contains(where: { $0.name == "Scenario: VFX Pull" })
        )

        viewModel.applyPreset("Scenario: VFX Pull")
        XCTAssertEqual(viewModel.templateConfig.label, "Scenario - VFX Pull")
        XCTAssertEqual(viewModel.templateConfig.fitSource, "framing_decision.protection_dimensions")
        XCTAssertEqual(viewModel.templateConfig.padToMaximum, true)
        XCTAssertNotNil(TemplatePresets.scenarioDescription(for: "Scenario: VFX Pull"))
    }
}
