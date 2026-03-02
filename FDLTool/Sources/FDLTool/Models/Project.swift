import Foundation

struct Project: Codable, Identifiable {
    let id: String
    var name: String
    var description: String?
    var createdAt: Date
    var updatedAt: Date

    init(name: String, description: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.description = description
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(id: String, name: String, description: String?, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct FDLEntry: Codable, Identifiable {
    let id: String
    var projectID: String
    var fdlUUID: String
    var name: String
    var filePath: String
    var sourceTool: String?
    var cameraModel: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date

    init(projectID: String, fdlUUID: String, name: String, filePath: String,
         sourceTool: String? = nil, cameraModel: String? = nil, tags: [String] = []) {
        self.id = UUID().uuidString
        self.projectID = projectID
        self.fdlUUID = fdlUUID
        self.name = name
        self.filePath = filePath
        self.sourceTool = sourceTool
        self.cameraModel = cameraModel
        self.tags = tags
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(id: String, projectID: String, fdlUUID: String, name: String, filePath: String,
         sourceTool: String?, cameraModel: String?, tags: [String], createdAt: Date, updatedAt: Date) {
        self.id = id
        self.projectID = projectID
        self.fdlUUID = fdlUUID
        self.name = name
        self.filePath = filePath
        self.sourceTool = sourceTool
        self.cameraModel = cameraModel
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
