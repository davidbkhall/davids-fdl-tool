import SwiftUI

/// Hierarchical visualization of an FDL document structure.
/// Shows Header → Contexts → Canvases → Framing Decisions as a disclosure tree.
struct FDLTreeView: View {
    let document: FDLDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup {
                headerDetails
            } label: {
                Label("Header", systemImage: "doc.text")
                    .font(.caption.weight(.medium))
            }
            .padding(.vertical, 2)

            ForEach(document.contexts) { context in
                DisclosureGroup {
                    contextDetails(context)

                    ForEach(context.canvases) { canvas in
                        DisclosureGroup {
                            canvasDetails(canvas)

                            ForEach(canvas.framingDecisions) { fd in
                                DisclosureGroup {
                                    framingDecisionDetails(fd)
                                } label: {
                                    Label {
                                        Text(fd.label ?? fd.id)
                                    } icon: {
                                        Image(systemName: "viewfinder")
                                            .foregroundStyle(.purple)
                                    }
                                }
                                .padding(.leading, 16)
                                .padding(.vertical, 1)
                            }
                        } label: {
                            Label {
                                HStack(spacing: 6) {
                                    Text(canvas.label ?? canvas.id)
                                    if let dims = Optional(canvas.dimensions) {
                                        AspectRatioLabel(width: dims.width, height: dims.height)
                                    }
                                }
                            } icon: {
                                Image(systemName: "rectangle.on.rectangle")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.leading, 8)
                        .padding(.vertical, 1)
                    }
                } label: {
                    Label {
                        Text(context.label ?? "Context")
                    } icon: {
                        Image(systemName: "folder")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption.weight(.medium))
                }
                .padding(.vertical, 2)
            }

            if let templates = document.canvasTemplates, !templates.isEmpty {
                ForEach(templates) { tmpl in
                    DisclosureGroup {
                        canvasTemplateDetails(tmpl)
                    } label: {
                        Label {
                            Text(tmpl.label ?? tmpl.id)
                        } icon: {
                            Image(systemName: "rectangle.on.rectangle.angled")
                                .foregroundStyle(.purple)
                        }
                        .font(.caption.weight(.medium))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var headerDetails: some View {
        DetailGrid {
            DetailRow(label: "UUID", value: document.id)
            DetailRow(label: "Version", value: document.versionString)
            if let creator = document.fdlCreator {
                DetailRow(label: "Creator", value: creator)
            }
            if let intent = document.defaultFramingIntent {
                DetailRow(label: "Default Intent", value: intent)
            }
        }
    }

    @ViewBuilder
    private func contextDetails(_ context: FDLContext) -> some View {
        DetailGrid {
            if let label = context.label {
                DetailRow(label: "Label", value: label)
            }
            if let creator = context.contextCreator {
                DetailRow(label: "Creator", value: creator)
            }
            DetailRow(label: "Canvases", value: "\(context.canvases.count)")
        }
    }

    @ViewBuilder
    private func canvasDetails(_ canvas: FDLCanvas) -> some View {
        DetailGrid {
            DetailRow(label: "ID", value: canvas.id)
            DetailRow(label: "Dimensions",
                      value: "\(Int(canvas.dimensions.width)) \u{00D7} \(Int(canvas.dimensions.height))")
            if let eff = canvas.effectiveDimensions {
                DetailRow(label: "Effective",
                          value: "\(Int(eff.width)) \u{00D7} \(Int(eff.height))")
            }
            if let anchor = canvas.effectiveAnchorPoint {
                DetailRow(label: "Eff. Anchor",
                          value: "(\(Int(anchor.x)), \(Int(anchor.y)))")
            }
            if let squeeze = canvas.anamorphicSqueeze, squeeze != 1.0 {
                DetailRow(label: "Squeeze", value: String(format: "%.2fx", squeeze))
            }
            if let ps = canvas.photositeDimensions {
                DetailRow(label: "Photosites",
                          value: "\(Int(ps.width)) \u{00D7} \(Int(ps.height))")
            }
            DetailRow(label: "FDs", value: "\(canvas.framingDecisions.count)")
        }
    }

    @ViewBuilder
    private func framingDecisionDetails(_ fd: FDLFramingDecision) -> some View {
        DetailGrid {
            DetailRow(label: "ID", value: fd.id)
            DetailRow(label: "Dimensions",
                      value: "\(Int(fd.dimensions.width)) \u{00D7} \(Int(fd.dimensions.height))")
            if let intent = fd.framingIntentId, !intent.isEmpty {
                DetailRow(label: "Intent", value: intent)
            }
            if let anchor = fd.anchorPoint {
                DetailRow(label: "Anchor",
                          value: "(\(Int(anchor.x)), \(Int(anchor.y)))")
            }
            if let protDims = fd.protectionDimensions {
                DetailRow(label: "Protection",
                          value: "\(Int(protDims.width)) \u{00D7} \(Int(protDims.height))")
            }
        }
    }

    @ViewBuilder
    private func canvasTemplateDetails(_ tmpl: FDLCanvasTemplate) -> some View {
        DetailGrid {
            DetailRow(label: "ID", value: tmpl.id)
            if let label = tmpl.label {
                DetailRow(label: "Label", value: label)
            }
            if let dims = tmpl.targetDimensions {
                DetailRow(label: "Target", value: "\(Int(dims.width)) \u{00D7} \(Int(dims.height))")
            }
            if let squeeze = tmpl.targetAnamorphicSqueeze {
                DetailRow(label: "Target Squeeze", value: String(format: "%.1fx", squeeze))
            }
            if let src = tmpl.fitSource {
                DetailRow(label: "Fit Source", value: src)
            }
            if let method = tmpl.fitMethod {
                DetailRow(label: "Fit Method", value: method)
            }
            if let h = tmpl.alignmentMethodHorizontal {
                DetailRow(label: "H Alignment", value: h)
            }
            if let v = tmpl.alignmentMethodVertical {
                DetailRow(label: "V Alignment", value: v)
            }
            if let preserve = tmpl.preserveFromSourceCanvas {
                DetailRow(label: "Preserve", value: preserve)
            }
            if let maxDims = tmpl.maximumDimensions {
                DetailRow(label: "Maximum", value: "\(Int(maxDims.width)) \u{00D7} \(Int(maxDims.height))")
            }
            if let pad = tmpl.padToMaximum {
                DetailRow(label: "Pad to Max", value: pad ? "Yes" : "No")
            }
            if let rnd = tmpl.round {
                let roundStr = [rnd.mode, rnd.even.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
                DetailRow(label: "Rounding", value: roundStr)
            }
        }
    }
}

/// Grid container for detail rows
struct DetailGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
            content()
        }
        .font(.caption)
        .padding(.leading, 24)
        .padding(.vertical, 4)
    }
}

/// A single label-value row in the detail grid
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .gridColumnAlignment(.leading)
        }
    }
}
