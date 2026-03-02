import Foundation

struct ValidationResult: Codable {
    var valid: Bool
    var errors: [ValidationMessage]
    var warnings: [ValidationMessage]
}

struct ValidationMessage: Codable, Identifiable {
    var id: String { "\(path):\(message)" }
    var path: String
    var message: String
    var severity: Severity

    enum Severity: String, Codable {
        case error
        case warning
        case info
    }
}
