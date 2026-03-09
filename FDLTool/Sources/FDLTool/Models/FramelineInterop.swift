import Foundation

struct FramelineModeOption: Identifiable, Hashable {
    let name: String
    let hres: Int?
    let vres: Int?
    let aspect: String?

    var id: String { name }
}

struct FramelineCameraOption: Identifiable, Hashable {
    let cameraType: String
    let modes: [FramelineModeOption]

    var id: String { cameraType }
}

struct FramelineInteropStatus {
    var arriAvailable = false
    var sonyAvailable = false
    var arriSource: String?
    var sonySource: String?
}

struct FramelineMappingDetail: Codable, Identifiable {
    var sourceField: String
    var sourceValue: String?
    var targetField: String
    var targetValue: String?
    var note: String?
    var status: String?

    var id: String {
        "\(sourceField)->\(targetField)->\(status ?? "")"
    }
}

struct FramelineConversionReport: Codable {
    var title: String
    var summary: String
    var mappedFields: [String]
    var mappingDetails: [FramelineMappingDetail]
    var droppedFields: [String]
    var warnings: [String]
    var lossy: Bool
    var validationErrorCount: Int
    var validationWarningCount: Int
    var generatedAt: Date = .init()
}
