import Foundation

/// Swift representation of an ASC FDL document (v2.0.1 schema).
/// Schema: https://github.com/ascmitc/fdl/blob/dev/schema/v2.0.1/ascfdl.schema.json
struct FDLDocument: Codable, Identifiable {
    let id: String
    var version: FDLVersion
    var fdlCreator: String?
    var defaultFramingIntent: String?
    var framingIntents: [FDLFramingIntent]?
    var contexts: [FDLContext]
    var canvasTemplates: [FDLCanvasTemplate]?

    enum CodingKeys: String, CodingKey {
        case id = "uuid"
        case version
        case fdlCreator = "fdl_creator"
        case defaultFramingIntent = "default_framing_intent"
        case framingIntents = "framing_intents"
        case contexts
        case canvasTemplates = "canvas_templates"
    }

    var versionString: String {
        "\(version.major).\(version.minor)"
    }
}

struct FDLVersion: Codable {
    var major: Int
    var minor: Int
}

struct FDLFramingIntent: Codable, Identifiable {
    var id: String
    var label: String?
    var aspectRatio: FDLDimensions?
    var protection: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case aspectRatio = "aspect_ratio"
        case protection
    }
}

struct FDLContext: Codable, Identifiable {
    var id: UUID { UUID() }
    var label: String?
    var contextCreator: String?
    var canvases: [FDLCanvas]

    enum CodingKeys: String, CodingKey {
        case label
        case contextCreator = "context_creator"
        case canvases
    }
}

struct FDLCanvas: Codable, Identifiable {
    var id: String
    var label: String?
    var sourceCanvasId: String?
    var dimensions: FDLDimensions
    var effectiveDimensions: FDLDimensions?
    var effectiveAnchorPoint: FDLPoint?
    var photositeDimensions: FDLDimensions?
    var physicalDimensions: FDLDimensionsFloat?
    var anamorphicSqueeze: Double?
    var framingDecisions: [FDLFramingDecision]

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case sourceCanvasId = "source_canvas_id"
        case dimensions
        case effectiveDimensions = "effective_dimensions"
        case effectiveAnchorPoint = "effective_anchor_point"
        case photositeDimensions = "photosite_dimensions"
        case physicalDimensions = "physical_dimensions"
        case anamorphicSqueeze = "anamorphic_squeeze"
        case framingDecisions = "framing_decisions"
    }
}

struct FDLDimensions: Codable {
    var width: Double
    var height: Double
}

struct FDLDimensionsFloat: Codable {
    var width: Double
    var height: Double
}

struct FDLPoint: Codable {
    var x: Double
    var y: Double
}

struct FDLFramingDecision: Codable, Identifiable {
    var id: String
    var label: String?
    var framingIntentId: String?
    var dimensions: FDLDimensions
    var anchorPoint: FDLPoint?
    var protectionDimensions: FDLDimensions?
    var protectionAnchorPoint: FDLPoint?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case framingIntentId = "framing_intent_id"
        case dimensions
        case anchorPoint = "anchor_point"
        case protectionDimensions = "protection_dimensions"
        case protectionAnchorPoint = "protection_anchor_point"
    }
}

struct FDLCanvasTemplate: Codable, Identifiable {
    var id: String
    var label: String?
    var targetDimensions: FDLDimensions?
    var targetAnamorphicSqueeze: Double?
    var fitSource: String?
    var fitMethod: String?
    var alignmentMethodVertical: String?
    var alignmentMethodHorizontal: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case targetDimensions = "target_dimensions"
        case targetAnamorphicSqueeze = "target_anamorphic_squeeze"
        case fitSource = "fit_source"
        case fitMethod = "fit_method"
        case alignmentMethodVertical = "alignment_method_vertical"
        case alignmentMethodHorizontal = "alignment_method_horizontal"
    }
}
