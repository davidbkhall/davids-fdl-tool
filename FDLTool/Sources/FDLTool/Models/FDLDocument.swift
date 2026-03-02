import Foundation

/// Swift representation of an ASC FDL document structure.
/// Maps to the JSON schema at https://github.com/ascmitc/fdl
struct FDLDocument: Codable, Identifiable {
    let id: String  // FDL UUID from header
    var header: FDLHeader
    var contexts: [FDLContext]

    enum CodingKeys: String, CodingKey {
        case id = "uuid"
        case header
        case contexts = "fdl_contexts"
    }
}

struct FDLHeader: Codable {
    var uuid: String
    var version: String
    var fdlCreator: String?
    var defaultFramingIntent: String?
    var description: String?

    enum CodingKeys: String, CodingKey {
        case uuid
        case version
        case fdlCreator = "fdl_creator"
        case defaultFramingIntent = "default_framing_intent"
        case description
    }
}

struct FDLContext: Codable, Identifiable {
    var id: String { contextUUID }
    var contextUUID: String
    var label: String?
    var contextCreator: String?
    var canvases: [FDLCanvas]

    enum CodingKeys: String, CodingKey {
        case contextUUID = "context_uuid"
        case label
        case contextCreator = "context_creator"
        case canvases
    }
}

struct FDLCanvas: Codable, Identifiable {
    var id: String { canvasUUID }
    var canvasUUID: String
    var label: String?
    var sourceFdlUUID: String?
    var dimensions: FDLDimensions
    var effectiveAnchor: FDLPoint?
    var effectiveDimensions: FDLDimensions?
    var photosite: FDLDimensions?
    var photositeAnchor: FDLPoint?
    var framingDecisions: [FDLFramingDecision]

    enum CodingKeys: String, CodingKey {
        case canvasUUID = "canvas_uuid"
        case label
        case sourceFdlUUID = "source_fdl_uuid"
        case dimensions
        case effectiveAnchor = "effective_anchor"
        case effectiveDimensions = "effective_dimensions"
        case photosite
        case photositeAnchor = "photosite_anchor"
        case framingDecisions = "framing_decisions"
    }
}

struct FDLDimensions: Codable {
    var width: Double
    var height: Double
}

struct FDLPoint: Codable {
    var x: Double
    var y: Double
}

struct FDLFramingDecision: Codable, Identifiable {
    var id: String { fdUUID }
    var fdUUID: String
    var label: String?
    var framingIntent: String?
    var dimensions: FDLDimensions
    var anchor: FDLPoint?
    var protectionDimensions: FDLDimensions?
    var protectionAnchor: FDLPoint?

    enum CodingKeys: String, CodingKey {
        case fdUUID = "fd_uuid"
        case label
        case framingIntent = "framing_intent"
        case dimensions
        case anchor
        case protectionDimensions = "protection_dimensions"
        case protectionAnchor = "protection_anchor"
    }
}
