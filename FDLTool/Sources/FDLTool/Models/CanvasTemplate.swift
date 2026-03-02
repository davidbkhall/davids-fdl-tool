import Foundation

struct CanvasTemplate: Codable, Identifiable {
    let id: String
    var name: String
    var description: String?
    var templateJSON: String
    var source: String?
    var createdAt: Date
    var updatedAt: Date

    init(name: String, description: String? = nil, templateJSON: String, source: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.description = description
        self.templateJSON = templateJSON
        self.source = source
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(id: String, name: String, description: String?, templateJSON: String,
         source: String?, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.description = description
        self.templateJSON = templateJSON
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ProjectTemplate: Codable {
    var projectID: String
    var templateID: String
    var role: String?
}
