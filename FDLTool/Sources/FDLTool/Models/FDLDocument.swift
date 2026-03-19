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
    let id: UUID
    var label: String?
    var contextCreator: String?
    var canvases: [FDLCanvas]

    enum CodingKeys: String, CodingKey {
        case label
        case contextCreator = "context_creator"
        case canvases
    }

    init(from decoder: Decoder) throws {
        self.id = UUID()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
        self.contextCreator = try container.decodeIfPresent(String.self, forKey: .contextCreator)
        self.canvases = try container.decode([FDLCanvas].self, forKey: .canvases)
    }

    init(id: UUID = UUID(), label: String? = nil, contextCreator: String? = nil, canvases: [FDLCanvas]) {
        self.id = id
        self.label = label
        self.contextCreator = contextCreator
        self.canvases = canvases
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
    var preserveFromSourceCanvas: String?
    var maximumDimensions: FDLDimensions?
    var padToMaximum: Bool?
    var round: FDLRoundConfig?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case targetDimensions = "target_dimensions"
        case targetAnamorphicSqueeze = "target_anamorphic_squeeze"
        case fitSource = "fit_source"
        case fitMethod = "fit_method"
        case alignmentMethodVertical = "alignment_method_vertical"
        case alignmentMethodHorizontal = "alignment_method_horizontal"
        case preserveFromSourceCanvas = "preserve_from_source_canvas"
        case maximumDimensions = "maximum_dimensions"
        case padToMaximum = "pad_to_maximum"
        case round
    }
}

struct FDLRoundConfig: Codable {
    var even: String?
    var mode: String?
}

// MARK: - Ordered JSON Serializer

/// Produces JSON strings with keys ordered to match the ASC FDL reference format.
/// JSONEncoder uses dictionary-backed containers that don't preserve insertion order,
/// so we encode → parse → re-serialize with explicit key ordering.
enum FDLJSONSerializer {

    static func string(from document: FDLDocument) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(document),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return serialize(obj, indent: 0)
    }

    private static let keyOrders: [[String]] = [
        // FDLDocument
        ["version", "uuid", "fdl_creator", "default_framing_intent",
         "framing_intents", "contexts", "canvas_templates"],
        // FDLContext
        ["label", "context_creator", "canvases"],
        // FDLCanvas
        ["label", "id", "source_canvas_id", "dimensions", "anamorphic_squeeze",
         "framing_decisions", "effective_dimensions", "effective_anchor_point",
         "photosite_dimensions", "physical_dimensions"],
        // FDLFramingDecision
        ["label", "id", "framing_intent_id", "dimensions", "anchor_point",
         "protection_dimensions", "protection_anchor_point"],
        // FDLCanvasTemplate
        ["label", "id", "target_dimensions", "target_anamorphic_squeeze",
         "fit_source", "fit_method", "alignment_method_vertical",
         "alignment_method_horizontal", "preserve_from_source_canvas",
         "maximum_dimensions", "pad_to_maximum", "round"],
        // FDLFramingIntent
        ["label", "id", "aspect_ratio", "protection"],
        // FDLDimensions / FDLDimensionsFloat / aspect_ratio
        ["width", "height"],
        // FDLPoint
        ["x", "y"],
    ]

    private static func orderedKeys(for keys: [String]) -> [String] {
        for order in keyOrders {
            let matched = order.filter { keys.contains($0) }
            if matched.count * 2 >= keys.count {
                let remaining = keys.filter { !order.contains($0) }.sorted()
                return matched + remaining
            }
        }
        return keys.sorted()
    }

    private static func serialize(_ value: Any, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)

        if let dict = value as? [String: Any] {
            let keys = orderedKeys(for: Array(dict.keys))
            var lines: [String] = []
            for key in keys {
                guard let val = dict[key] else { continue }
                lines.append("\(inner)\(escapeString(key)): \(serialize(val, indent: indent + 1))")
            }
            return lines.isEmpty ? "{}" : "{\n\(lines.joined(separator: ",\n"))\n\(pad)}"
        }

        if let arr = value as? [Any] {
            if arr.isEmpty { return "[]" }
            let items = arr.map { "\(inner)\(serialize($0, indent: indent + 1))" }
            return "[\n\(items.joined(separator: ",\n"))\n\(pad)]"
        }

        if let str = value as? String { return escapeString(str) }

        if let num = value as? NSNumber {
            if CFBooleanGetTypeID() == CFGetTypeID(num) {
                return num.boolValue ? "true" : "false"
            }
            let d = num.doubleValue
            if d == d.rounded(.towardZero) && !d.isInfinite && abs(d) < 1e15 {
                return "\(Int64(d))"
            }
            return "\(d)"
        }

        if value is NSNull { return "null" }
        return "\(value)"
    }

    private static func escapeString(_ s: String) -> String {
        var out = "\""
        for ch in s {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(ch)
            }
        }
        out += "\""
        return out
    }
}
