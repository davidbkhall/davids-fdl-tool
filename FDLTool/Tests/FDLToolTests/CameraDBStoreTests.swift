import XCTest
@testable import FDLTool

final class CameraDBStoreTests: XCTestCase {

    func testCameraSpecDecoding() throws {
        let json = """
        {
          "id": "arri-alexa-35",
          "manufacturer": "ARRI",
          "model": "ALEXA 35",
          "sensor": {
            "name": "ALEV 4",
            "photosite_dimensions": {"width": 4608, "height": 3164},
            "physical_dimensions_mm": {"width": 27.98, "height": 19.22},
            "pixel_pitch_um": 6.075
          },
          "recording_modes": [
            {
              "id": "4.6k-3-2-ow",
              "name": "4.6K 3:2 Open Window",
              "active_photosites": {"width": 4608, "height": 3164},
              "active_image_area_mm": {"width": 27.98, "height": 19.22},
              "max_fps": 120,
              "codec_options": ["ARRIRAW", "ProRes 4444 XQ"]
            }
          ],
          "common_deliverables": ["4096x2160", "3840x2160"]
        }
        """
        let data = json.data(using: .utf8)!
        let camera = try JSONDecoder().decode(CameraSpec.self, from: data)

        XCTAssertEqual(camera.id, "arri-alexa-35")
        XCTAssertEqual(camera.manufacturer, "ARRI")
        XCTAssertEqual(camera.sensor.name, "ALEV 4")
        XCTAssertEqual(camera.sensor.photositeDimensions.width, 4608)
        XCTAssertEqual(camera.sensor.physicalDimensionsMM.width, 27.98)
        XCTAssertEqual(camera.sensor.pixelPitchUM, 6.075)
        XCTAssertEqual(camera.recordingModes.count, 1)
        XCTAssertEqual(camera.recordingModes[0].maxFPS, 120)
        XCTAssertEqual(camera.commonDeliverables, ["4096x2160", "3840x2160"])
    }

    func testCameraDatabaseDecoding() throws {
        let json = """
        {
          "version": "1.0",
          "last_updated": "2026-03-01",
          "cameras": [
            {
              "id": "test-cam",
              "manufacturer": "TestCo",
              "model": "Model X",
              "sensor": {
                "name": "TestSensor",
                "photosite_dimensions": {"width": 3840, "height": 2160},
                "physical_dimensions_mm": {"width": 24.0, "height": 13.5},
                "pixel_pitch_um": 6.25
              },
              "recording_modes": [],
              "common_deliverables": []
            }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let db = try JSONDecoder().decode(CameraDatabase.self, from: data)

        XCTAssertEqual(db.version, "1.0")
        XCTAssertEqual(db.lastUpdated, "2026-03-01")
        XCTAssertEqual(db.cameras.count, 1)
        XCTAssertEqual(db.cameras[0].id, "test-cam")
    }

    func testRecordingModeDecoding() throws {
        let json = """
        {
          "id": "4k-16-9",
          "name": "4K 16:9",
          "active_photosites": {"width": 4096, "height": 2304},
          "active_image_area_mm": {"width": 24.88, "height": 14.0},
          "max_fps": 150,
          "codec_options": ["ARRIRAW", "ProRes 4444"]
        }
        """
        let data = json.data(using: .utf8)!
        let mode = try JSONDecoder().decode(RecordingMode.self, from: data)

        XCTAssertEqual(mode.id, "4k-16-9")
        XCTAssertEqual(mode.name, "4K 16:9")
        XCTAssertEqual(mode.activePhotosites.width, 4096)
        XCTAssertEqual(mode.activeImageAreaMM.height, 14.0)
        XCTAssertEqual(mode.maxFPS, 150)
        XCTAssertEqual(mode.codecOptions.count, 2)
    }

    func testValidationResultDecoding() throws {
        let json = """
        {
          "valid": false,
          "errors": [{"path": "header.uuid", "message": "Missing UUID", "severity": "error"}],
          "warnings": [{"path": "header.version", "message": "Outdated version", "severity": "warning"}]
        }
        """
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(ValidationResult.self, from: data)

        XCTAssertFalse(result.valid)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.errors[0].severity, .error)
    }
}
