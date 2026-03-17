import XCTest
@testable import FDLTool

final class ChartExportFailurePathTests: XCTestCase {
    func testNoFormatSelectedMessage() {
        XCTAssertEqual(
            ExportTraceEventComposer.noFormatSelectedMessage(),
            "Export failed.\nReason: Choose at least one format."
        )
    }

    func testUserFacingReasonMapsTimeout() {
        let reason = ExportTraceEventComposer.userFacingReason(PythonBridgeError.timeout)
        XCTAssertEqual(reason, "Request timed out")
    }

    func testUserFacingReasonMapsNotStarted() {
        let reason = ExportTraceEventComposer.userFacingReason(PythonBridgeError.notStarted)
        XCTAssertEqual(reason, "Python bridge not started")
    }

    func testMultiExportFailureMessageIncludesPartialProgress() {
        let message = ExportTraceEventComposer.multiExportFailureMessage(
            completedCount: 2,
            totalCount: 5,
            failedFormat: "TIFF",
            reason: "Request timed out"
        )
        XCTAssertEqual(
            message,
            "Export failed.\nCompleted 2/5. Failed: TIFF. Reason: Request timed out"
        )
    }

    func testTelemetryRecordContainsRequiredKeys() {
        let record = ExportTraceEventComposer.telemetryRecord(
            event: "multi_export_item_failed",
            requestID: "req-123",
            fields: [
                "format": "PDF",
                "completed": "1",
                "total": "3",
            ]
        )
        XCTAssertEqual(record["event"], "multi_export_item_failed")
        XCTAssertEqual(record["request_id"], "req-123")
        XCTAssertEqual(record["format"], "PDF")
        XCTAssertEqual(record["completed"], "1")
        XCTAssertEqual(record["total"], "3")
    }

    func testTelemetryLineEncodesStructuredJSONPayload() throws {
        let line = ExportTraceEventComposer.telemetryLine(
            event: "multi_export_started",
            requestID: "req-abc",
            fields: [
                "formats": "TIFF,PNG",
                "folder": "Exports",
            ]
        )

        XCTAssertTrue(line.hasPrefix("event="))
        let jsonText = String(line.dropFirst("event=".count))
        let data = try XCTUnwrap(jsonText.data(using: .utf8))
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: String]

        XCTAssertEqual(payload?["event"], "multi_export_started")
        XCTAssertEqual(payload?["request_id"], "req-abc")
        XCTAssertEqual(payload?["formats"], "TIFF,PNG")
        XCTAssertEqual(payload?["folder"], "Exports")
    }

    func testTelemetryLineForSingleCancelEvent() throws {
        let line = ExportTraceEventComposer.telemetryLine(
            event: "single_export_cancelled",
            requestID: "req-cancel",
            fields: ["format": "TIFF"]
        )
        let jsonText = String(line.dropFirst("event=".count))
        let data = try XCTUnwrap(jsonText.data(using: .utf8))
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(payload?["event"], "single_export_cancelled")
        XCTAssertEqual(payload?["request_id"], "req-cancel")
        XCTAssertEqual(payload?["format"], "TIFF")
    }

    func testMultiExportRunnerCancelledSkipsWork() async {
        var called = 0
        let result = await MultiExportExecutionRunner.run(
            formats: [.tiff, .png],
            isCancelled: true,
            exportOne: { _ in called += 1 },
            mapError: { _ in "unused" }
        )

        XCTAssertEqual(called, 0)
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertEqual(result.completedCount, 0)
        XCTAssertEqual(result.totalCount, 2)
        XCTAssertNil(result.failedFormat)
        XCTAssertNil(result.failureReason)
    }

    func testMultiExportRunnerPartialFailureReturnsProgress() async {
        enum TestErr: Error { case failed }
        var attempted: [ExportFormat] = []

        let result = await MultiExportExecutionRunner.run(
            formats: [.tiff, .png, .pdf],
            isCancelled: false,
            exportOne: { format in
                attempted.append(format)
                if format == .png { throw TestErr.failed }
            },
            mapError: { _ in "Injected failure" }
        )

        XCTAssertEqual(attempted, [.tiff, .png])
        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(result.completedCount, 1)
        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.failedFormat, .png)
        XCTAssertEqual(result.failureReason, "Injected failure")
    }

    func testMultiExportRunnerSuccessCompletesAllFormats() async {
        var attempted: [ExportFormat] = []

        let result = await MultiExportExecutionRunner.run(
            formats: [.tiff, .png, .pdf],
            isCancelled: false,
            exportOne: { format in attempted.append(format) },
            mapError: { _ in "unused" }
        )

        XCTAssertEqual(attempted, [.tiff, .png, .pdf])
        XCTAssertEqual(result.outcome, .succeeded)
        XCTAssertEqual(result.completedCount, 3)
        XCTAssertEqual(result.totalCount, 3)
        XCTAssertNil(result.failedFormat)
        XCTAssertNil(result.failureReason)
    }

}
