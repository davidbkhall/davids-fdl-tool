import Foundation

/// Response model from the `geometry.compute_rects` JSON-RPC call.
/// Represents all geometry layers for an FDL document, pre-computed by the Python backend.
struct ComputedGeometry: Codable {
    let contexts: [ComputedContext]
}

struct ComputedContext: Codable {
    let label: String?
    let canvases: [ComputedCanvas]
}

struct ComputedCanvas: Codable {
    let label: String?
    let canvasRect: GeometryRect
    let effectiveRect: GeometryRect?
    let framingDecisions: [ComputedFramingDecision]

    enum CodingKeys: String, CodingKey {
        case label
        case canvasRect = "canvas_rect"
        case effectiveRect = "effective_rect"
        case framingDecisions = "framing_decisions"
    }
}

struct GeometryRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct ComputedFramingDecision: Codable {
    let label: String
    let framingIntent: String
    let framingRect: GeometryRect
    let protectionRect: GeometryRect?
    let anchorPoint: GeometryPoint?

    enum CodingKeys: String, CodingKey {
        case label
        case framingIntent = "framing_intent"
        case framingRect = "framing_rect"
        case protectionRect = "protection_rect"
        case anchorPoint = "anchor_point"
    }
}

struct GeometryPoint: Codable {
    let x: Double
    let y: Double
}
