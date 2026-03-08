import Foundation

/// A canvas template configuration matching ASC fdl CanvasTemplate fields.
struct CanvasTemplateConfig: Equatable {
    var id: String = UUID().uuidString
    var label: String = "Custom"
    var targetWidth: Int = 1920
    var targetHeight: Int = 1080
    var targetAnamorphicSqueeze: Double = 1.0
    var fitSource: String = "framing_decision.dimensions"
    var fitMethod: String = "fit_all"
    var alignmentHorizontal: String = "center"
    var alignmentVertical: String = "center"
    var preserveFromSourceCanvas: String?
    var maximumWidth: Int?
    var maximumHeight: Int?
    var padToMaximum: Bool = false
    var roundEven: String = "even"
    var roundMode: String = "up"

    func toDict() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "label": label,
            "target_dimensions": ["width": targetWidth, "height": targetHeight],
            "target_anamorphic_squeeze": targetAnamorphicSqueeze,
            "fit_source": fitSource,
            "fit_method": fitMethod,
            "alignment_method_horizontal": alignmentHorizontal,
            "alignment_method_vertical": alignmentVertical,
            "pad_to_maximum": padToMaximum,
            "round": ["even": roundEven, "mode": roundMode],
        ]
        if let preserve = preserveFromSourceCanvas {
            dict["preserve_from_source_canvas"] = preserve
        }
        if let mw = maximumWidth, let mh = maximumHeight {
            dict["maximum_dimensions"] = ["width": mw, "height": mh]
        }
        return dict
    }
}

enum TemplatePresets {
    static let standardDeliverables: [(name: String, config: CanvasTemplateConfig)] = [
        ("HD 1080p", CanvasTemplateConfig(id: "preset_hd_1080p", label: "HD 1080p", targetWidth: 1920, targetHeight: 1080)),
        ("UHD 4K", CanvasTemplateConfig(id: "preset_uhd_4k", label: "UHD 4K", targetWidth: 3840, targetHeight: 2160)),
        ("DCI 2K", CanvasTemplateConfig(id: "preset_dci_2k", label: "DCI 2K", targetWidth: 2048, targetHeight: 1080)),
        ("DCI 4K", CanvasTemplateConfig(id: "preset_dci_4k", label: "DCI 4K", targetWidth: 4096, targetHeight: 2160)),
        ("DCI 2K Flat", CanvasTemplateConfig(id: "preset_dci_2k_flat", label: "DCI 2K Flat", targetWidth: 1998, targetHeight: 1080)),
        ("DCI 4K Flat", CanvasTemplateConfig(id: "preset_dci_4k_flat", label: "DCI 4K Flat", targetWidth: 3996, targetHeight: 2160)),
        ("DCI 2K Scope", CanvasTemplateConfig(id: "preset_dci_2k_scope", label: "DCI 2K Scope", targetWidth: 2048, targetHeight: 858)),
        ("DCI 4K Scope", CanvasTemplateConfig(id: "preset_dci_4k_scope", label: "DCI 4K Scope", targetWidth: 4096, targetHeight: 1716)),
    ]

    static let scenarioContexts: [(name: String, config: CanvasTemplateConfig)] = [
        (
            "Scenario: Dailies",
            CanvasTemplateConfig(
                id: "scenario_dailies",
                label: "Scenario - Dailies",
                targetWidth: 1920,
                targetHeight: 1080,
                targetAnamorphicSqueeze: 1.0,
                fitSource: "framing_decision.dimensions",
                fitMethod: "fit_all",
                alignmentHorizontal: "center",
                alignmentVertical: "center",
                preserveFromSourceCanvas: "canvas.effective_dimensions",
                maximumWidth: nil,
                maximumHeight: nil,
                padToMaximum: false,
                roundEven: "even",
                roundMode: "round"
            )
        ),
        (
            "Scenario: On-set",
            CanvasTemplateConfig(
                id: "scenario_onset",
                label: "Scenario - On-set",
                targetWidth: 2048,
                targetHeight: 1152,
                targetAnamorphicSqueeze: 1.0,
                fitSource: "framing_decision.dimensions",
                fitMethod: "fit_all",
                alignmentHorizontal: "center",
                alignmentVertical: "center",
                preserveFromSourceCanvas: "canvas.dimensions",
                maximumWidth: nil,
                maximumHeight: nil,
                padToMaximum: false,
                roundEven: "even",
                roundMode: "round"
            )
        ),
        (
            "Scenario: VFX Pull",
            CanvasTemplateConfig(
                id: "scenario_vfx_pull",
                label: "Scenario - VFX Pull",
                targetWidth: 4096,
                targetHeight: 2160,
                targetAnamorphicSqueeze: 1.0,
                fitSource: "framing_decision.protection_dimensions",
                fitMethod: "fit_all",
                alignmentHorizontal: "center",
                alignmentVertical: "center",
                preserveFromSourceCanvas: "canvas.effective_dimensions",
                maximumWidth: 4096,
                maximumHeight: 2160,
                padToMaximum: true,
                roundEven: "even",
                roundMode: "round"
            )
        ),
        (
            "Scenario: Editorial",
            CanvasTemplateConfig(
                id: "scenario_editorial",
                label: "Scenario - Editorial",
                targetWidth: 1920,
                targetHeight: 1080,
                targetAnamorphicSqueeze: 1.0,
                fitSource: "framing_decision.dimensions",
                fitMethod: "height",
                alignmentHorizontal: "center",
                alignmentVertical: "center",
                preserveFromSourceCanvas: nil,
                maximumWidth: nil,
                maximumHeight: nil,
                padToMaximum: false,
                roundEven: "even",
                roundMode: "round"
            )
        ),
    ]

    static let all: [(name: String, config: CanvasTemplateConfig)] = standardDeliverables + scenarioContexts

    static func scenarioDescription(for name: String) -> String? {
        switch name {
        case "Scenario: Dailies":
            return "Fast review output: fit framing decision to HD/UHD deliverable, centered, preserving effective canvas context."
        case "Scenario: On-set":
            return "Monitoring/output assist: fit framing decision into on-set friendly raster while preserving full canvas context."
        case "Scenario: VFX Pull":
            return "VFX-safe extraction: fit protection dimensions, then pad to target maximum for consistent pulls."
        case "Scenario: Editorial":
            return "Editorial framing normalization: fit by height into editorial raster with centered alignment."
        default:
            return nil
        }
    }

    static let fitSourceOptions: [(value: String, label: String)] = [
        ("framing_decision.dimensions", "Framing Decision"),
        ("framing_decision.protection_dimensions", "Protection Dimensions"),
        ("canvas.effective_dimensions", "Effective Canvas"),
        ("canvas.dimensions", "Full Canvas"),
    ]

    static let fitMethodOptions: [(value: String, label: String)] = [
        ("fit_all", "Fit All (letterbox/pillarbox)"),
        ("fill", "Fill (may crop)"),
        ("width", "Fit Width"),
        ("height", "Fit Height"),
    ]

    static let alignmentHOptions: [(value: String, label: String)] = [
        ("left", "Left"), ("center", "Center"), ("right", "Right"),
    ]

    static let alignmentVOptions: [(value: String, label: String)] = [
        ("top", "Top"), ("center", "Center"), ("bottom", "Bottom"),
    ]

    static let roundEvenOptions: [(value: String, label: String)] = [
        ("whole", "Whole Numbers"), ("even", "Even Numbers"),
    ]

    static let roundModeOptions: [(value: String, label: String)] = [
        ("up", "Round Up"), ("down", "Round Down"), ("round", "Round Nearest"),
    ]
}
