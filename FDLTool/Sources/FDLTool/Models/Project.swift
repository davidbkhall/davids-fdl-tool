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

enum ProjectAssetType: String, Codable, CaseIterable {
    case fdl = "fdl"
    case chart = "chart"
    case template = "template"
    case report = "report"
    case cameraMode = "camera_mode"
    case referenceImage = "reference_image"
}

enum ProjectAssetLinkType: String, Codable, CaseIterable {
    case derivedFrom = "derived_from"
    case usesTemplate = "uses_template"
    case shotWith = "shot_with"
    case inputOf = "input_of"
}

struct ProjectAsset: Codable, Identifiable {
    let id: String
    var projectID: String
    var assetType: ProjectAssetType
    var name: String
    var sourceTool: String?
    var referenceID: String?
    var filePath: String?
    var payloadJSON: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        projectID: String,
        assetType: ProjectAssetType,
        name: String,
        sourceTool: String? = nil,
        referenceID: String? = nil,
        filePath: String? = nil,
        payloadJSON: String? = nil
    ) {
        self.id = UUID().uuidString
        self.projectID = projectID
        self.assetType = assetType
        self.name = name
        self.sourceTool = sourceTool
        self.referenceID = referenceID
        self.filePath = filePath
        self.payloadJSON = payloadJSON
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(
        id: String,
        projectID: String,
        assetType: ProjectAssetType,
        name: String,
        sourceTool: String?,
        referenceID: String?,
        filePath: String?,
        payloadJSON: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.assetType = assetType
        self.name = name
        self.sourceTool = sourceTool
        self.referenceID = referenceID
        self.filePath = filePath
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ProjectAssetLink: Codable, Identifiable {
    let id: String
    var projectID: String
    var fromAssetID: String
    var toAssetID: String
    var linkType: ProjectAssetLinkType
    var createdAt: Date

    init(
        projectID: String,
        fromAssetID: String,
        toAssetID: String,
        linkType: ProjectAssetLinkType
    ) {
        self.id = UUID().uuidString
        self.projectID = projectID
        self.fromAssetID = fromAssetID
        self.toAssetID = toAssetID
        self.linkType = linkType
        self.createdAt = Date()
    }

    init(
        id: String,
        projectID: String,
        fromAssetID: String,
        toAssetID: String,
        linkType: ProjectAssetLinkType,
        createdAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.fromAssetID = fromAssetID
        self.toAssetID = toAssetID
        self.linkType = linkType
        self.createdAt = createdAt
    }
}

struct ProjectCameraModeAssignment: Codable, Identifiable {
    let id: String
    var projectID: String
    var cameraModelID: String
    var cameraModelName: String
    var recordingModeID: String
    var recordingModeName: String
    var source: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        projectID: String,
        cameraModelID: String,
        cameraModelName: String,
        recordingModeID: String,
        recordingModeName: String,
        source: String? = nil,
        notes: String? = nil
    ) {
        self.id = UUID().uuidString
        self.projectID = projectID
        self.cameraModelID = cameraModelID
        self.cameraModelName = cameraModelName
        self.recordingModeID = recordingModeID
        self.recordingModeName = recordingModeName
        self.source = source
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(
        id: String,
        projectID: String,
        cameraModelID: String,
        cameraModelName: String,
        recordingModeID: String,
        recordingModeName: String,
        source: String?,
        notes: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.projectID = projectID
        self.cameraModelID = cameraModelID
        self.cameraModelName = cameraModelName
        self.recordingModeID = recordingModeID
        self.recordingModeName = recordingModeName
        self.source = source
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
