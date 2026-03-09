import SwiftUI
import CoreGraphics

// MARK: - ChartExportContentView
/// Standalone chart rendering view used for image export (PNG, TIFF, PDF).
///
/// Renders at native canvas pixel resolution (scale=1) so the output matches
/// the Chart Preview exactly. Use with `ImageRenderer` to produce images.
struct ChartExportContentView: View {
    let viewModel: ChartGeneratorViewModel

    private var cw: Double { viewModel.canvasWidth }
    private var ch: Double { viewModel.canvasHeight }
    /// Proportional font scale so labels are readable at full canvas resolution.
    var fontScale: Double { max(1.0, cw / 480.0) }
    private var canvasLabelFont: Double { max(12.0, 9.0 * fontScale) }
    var detailFont: Double { max(10.0, 8.0 * fontScale) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            canvasBackground
            gridLayer
            effectiveAreaLayer
            framelineStack
            siemensStarLayer
            titleLayer
            metadataLayer
            centerMarkerLayer
            logoLayer
            canvasDimensionLabel
        }
        .frame(width: cw, height: ch)
        .clipped()
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var canvasBackground: some View {
        if viewModel.showCanvasLayer {
            if viewModel.chartBackgroundTheme == .white {
                Color(white: 0.68).frame(width: cw, height: ch)
            } else {
                Color.black.frame(width: cw, height: ch)
            }

        }
    }

    @ViewBuilder
    private var gridLayer: some View {
        if viewModel.showGridOverlay && viewModel.gridSpacing > 0 {
            let sp = viewModel.gridSpacing
            Path { p in
                var x = sp
                while x < cw {
                    p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: ch))
                    x += sp
                }
                var y = sp
                while y < ch {
                    p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: cw, y: y))
                    y += sp
                }
            }
            .stroke(viewModel.chartBackgroundTheme == .white
                ? Color.black.opacity(0.15) : Color.white.opacity(0.1),
                    lineWidth: fontScale * 0.5)
        }
    }

    @ViewBuilder
    private var effectiveAreaLayer: some View {
        if viewModel.showEffectiveLayer,
           let ew = viewModel.canvasEffectiveWidth,
           let eh = viewModel.canvasEffectiveHeight {
            let ex = viewModel.canvasEffectiveAnchorX
            let ey = viewModel.canvasEffectiveAnchorY
            let effRaw = CGRect(x: ex, y: ey, width: ew, height: eh)
            let effRect = effRaw.insetBy(dx: 0.75, dy: 0.75)
            if viewModel.chartBackgroundTheme == .white {
                Color(white: 0.78).frame(width: ew, height: eh).offset(x: ex, y: ey)
            } else {
                Rectangle()
                    .stroke(Color.teal, lineWidth: 1.5)
                    .frame(width: effRect.width, height: effRect.height)
                    .offset(x: effRect.minX, y: effRect.minY)
            }
            if viewModel.chartBackgroundTheme == .white && viewModel.showBoundaryArrows {
                exportBoundaryArrows(for: effRaw, color: .teal)
            }
            if viewModel.showDimensionLabels {
                Text(verbatim: "Effective: \(Int(ew))\u{00D7}\(Int(eh))")
                    .font(.system(size: detailFont, design: .monospaced))
                    .foregroundStyle(viewModel.chartBackgroundTheme == .white
                        ? Color.black.opacity(0.8) : Color.white.opacity(0.8))
                    .offset(x: ex + 4, y: ey + eh - detailFont * 2)
            }
        }
    }

    @ViewBuilder
    private var framelineStack: some View {
        ForEach(Array(viewModel.framelines.enumerated()), id: \.element.id) { idx, fl in
            ExportFramelineView(
                fl: fl, idx: idx,
                viewModel: viewModel,
                cw: cw, ch: ch,
                fontScale: fontScale, detailFont: detailFont
            )
        }
    }

    @ViewBuilder
    private var siemensStarLayer: some View {
        if viewModel.showSiemensStars {
            let rects = exportSiemensStarRects()
            ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                SiemensStarShape(theme: viewModel.chartBackgroundTheme)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    @ViewBuilder
    private var titleLayer: some View {
        if !viewModel.chartTitle.isEmpty {
            Text(viewModel.chartTitle)
                .font(.system(size: max(14.0, 11.0 * fontScale)))
                .foregroundStyle(viewModel.chartBackgroundTheme == .white
                    ? Color.black.opacity(0.8) : Color.white)
                .frame(width: cw, alignment: .center)
                .offset(x: 0, y: 8 * fontScale)
        }
    }

    @ViewBuilder
    private var metadataLayer: some View {
        if viewModel.metadataBurnInEnabled {
            ExportMetadataView(viewModel: viewModel, cw: cw, ch: ch, fontScale: fontScale)
        }
    }

    @ViewBuilder
    private var centerMarkerLayer: some View {
        if viewModel.showCenterMarker {
            let cx = cw / 2, cy = ch / 2, ml = 12.0 * fontScale
            Path { p in
                p.move(to: .init(x: cx - ml, y: cy)); p.addLine(to: .init(x: cx + ml, y: cy))
                p.move(to: .init(x: cx, y: cy - ml)); p.addLine(to: .init(x: cx, y: cy + ml))
            }
            .stroke(viewModel.chartBackgroundTheme == .white
                ? Color.black.opacity(0.7) : Color.white.opacity(0.8),
                    lineWidth: fontScale)
        }
    }

    @ViewBuilder
    private var logoLayer: some View {
        if viewModel.showLogoOverlay {
            Group {
                if let data = viewModel.logoImageData, let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(width: 80 * viewModel.logoScale * fontScale,
                               height: 30 * viewModel.logoScale * fontScale)
                } else if !viewModel.logoText.isEmpty {
                    Text(viewModel.logoText)
                        .font(.system(size: 10 * viewModel.logoScale * fontScale))
                        .foregroundStyle(viewModel.chartBackgroundTheme == .white
                            ? Color.black.opacity(0.75) : Color.white.opacity(0.7))
                }
            }
            .position(x: cw / 2 + viewModel.logoOffsetX * fontScale,
                      y: ch / 2 + viewModel.logoOffsetY * fontScale)
        }
    }

    @ViewBuilder
    private var canvasDimensionLabel: some View {
        if viewModel.showCanvasLayer && viewModel.showDimensionLabels {
            Text(verbatim: "Canvas: \(Int(ch))\u{00D7}\(Int(cw))")
                .font(.system(size: canvasLabelFont, design: .monospaced))
                .foregroundStyle(
                    viewModel.chartBackgroundTheme == .white
                        ? Color(white: 0.15).opacity(0.75)
                        : Color.white.opacity(0.65)
                )
                .lineLimit(1)
                .padding(.trailing, fontScale * 5)
                .frame(width: cw, alignment: .trailing)
                .offset(x: 0, y: ch - canvasLabelFont * 1.5)
        }
    }

    // MARK: - Geometry helpers

    func exportFramelinePosition(_ fl: Frameline) -> CGRect {
        if let ax = fl.anchorX, let ay = fl.anchorY {
            return CGRect(x: ax, y: ay, width: fl.width, height: fl.height)
        }
        let fx: Double
        switch fl.hAlign {
        case .left:   fx = 0
        case .right:  fx = cw - fl.width
        case .center: fx = (cw - fl.width) / 2
        }
        let fy: Double
        switch fl.vAlign {
        case .top:    fy = 0
        case .bottom: fy = ch - fl.height
        case .center: fy = (ch - fl.height) / 2
        }
        return CGRect(x: fx, y: fy, width: fl.width, height: fl.height)
    }

    private func exportSiemensStarRects() -> [CGRect] {
        let target: CGRect = viewModel.framelines.first.map { exportFramelinePosition($0) }
            ?? CGRect(x: 0, y: 0, width: cw, height: ch)
        let base = max(20.0, min(200.0, min(target.width, target.height) * 0.125))
        let factor: Double
        switch viewModel.siemensStarSize {
        case .small:  factor = 1.15
        case .medium: factor = 1.60
        case .large:  factor = 2.05
        }
        let h = base * factor
        let w = h / max(1.0, viewModel.anamorphicSqueeze)
        let insetX = (w / 2) + max(4.0, target.width * 0.12)
        let insetY = (h / 2) + max(4.0, target.height * 0.12)
        return [
            CGRect(x: target.minX + insetX - w / 2, y: target.minY + insetY - h / 2, width: w, height: h),
            CGRect(x: target.maxX - insetX - w / 2, y: target.minY + insetY - h / 2, width: w, height: h),
            CGRect(x: target.minX + insetX - w / 2, y: target.maxY - insetY - h / 2, width: w, height: h),
            CGRect(x: target.maxX - insetX - w / 2, y: target.maxY - insetY - h / 2, width: w, height: h),
        ]
    }

    @ViewBuilder
    func exportBoundaryArrows(for rect: CGRect, color: Color) -> some View {
        let s = max(0.72, min(1.5, viewModel.boundaryArrowScale))
        let a = 16.0 * s * fontScale
        let h = 9.0 * s * fontScale
        Path { p in
            p.move(to: .init(x: rect.midX, y: rect.minY))
            p.addLine(to: .init(x: rect.midX - h, y: rect.minY + a))
            p.addLine(to: .init(x: rect.midX + h, y: rect.minY + a))
            p.closeSubpath()
            p.move(to: .init(x: rect.midX, y: rect.maxY))
            p.addLine(to: .init(x: rect.midX - h, y: rect.maxY - a))
            p.addLine(to: .init(x: rect.midX + h, y: rect.maxY - a))
            p.closeSubpath()
            p.move(to: .init(x: rect.minX, y: rect.midY))
            p.addLine(to: .init(x: rect.minX + a, y: rect.midY - h))
            p.addLine(to: .init(x: rect.minX + a, y: rect.midY + h))
            p.closeSubpath()
            p.move(to: .init(x: rect.maxX, y: rect.midY))
            p.addLine(to: .init(x: rect.maxX - a, y: rect.midY - h))
            p.addLine(to: .init(x: rect.maxX - a, y: rect.midY + h))
            p.closeSubpath()
        }
        .fill(color.opacity(0.95))
    }
}

// MARK: - ExportFramelineView
/// Renders a single frameline (protection + framing + labels) for export.
private struct ExportFramelineView: View {
    let fl: Frameline
    let idx: Int
    let viewModel: ChartGeneratorViewModel
    let cw: Double, ch: Double
    let fontScale: Double, detailFont: Double

    private var parent: ChartExportContentView {
        ChartExportContentView(viewModel: viewModel)
    }
    private var isWhite: Bool { viewModel.chartBackgroundTheme == .white }
    private var isPrimary: Bool {
        !viewModel.declutterMultipleFramelines || viewModel.framelines.count <= 1 || idx == 0
    }
    private var alpha: Double { isPrimary ? 1.0 : 0.52 }
    private var laneY: Double { Double(idx) * 12.0 * fontScale }
    private var pos: CGRect { parent.exportFramelinePosition(fl) }
    private var color: Color { Color(hex: fl.color) ?? .gray }

    var body: some View {
        protectionLayer
        framingLayer
    }

    @ViewBuilder
    private var protectionLayer: some View {
        if viewModel.showProtectionLayer,
           let prot = viewModel.effectiveProtection(for: fl) {
            let psw = prot.width, psh = prot.height
            let px = fl.protectionAnchorX ?? ((cw - psw) / 2)
            let py = fl.protectionAnchorY ?? ((ch - psh) / 2)
            let protRaw = CGRect(x: px, y: py, width: psw, height: psh)
            let lw = fontScale
            let protRect = protRaw.insetBy(dx: lw / 2, dy: lw / 2)
            if isWhite {
                Color(white: 0.86).frame(width: psw, height: psh).offset(x: px, y: py).opacity(alpha)
            } else {
                Rectangle()
                    .stroke(Color.orange,
                            style: StrokeStyle(lineWidth: lw, dash: [6 * fontScale, 4 * fontScale]))
                    .frame(width: protRect.width, height: protRect.height)
                    .offset(x: protRect.minX, y: protRect.minY).opacity(alpha)
            }
            if isWhite && viewModel.showBoundaryArrows {
                parent.exportBoundaryArrows(for: protRaw, color: .orange.opacity(alpha))
            }
            if viewModel.showDimensionLabels {
                Text(verbatim: "Protection: \(Int(psw))\u{00D7}\(Int(psh))")
                    .font(.system(size: detailFont, design: .monospaced))
                    .foregroundStyle(isWhite ? Color.orange.opacity(0.9 * alpha) : Color.white.opacity(0.8))
                    .offset(x: max(px + 4, 4), y: max(py + 4, 4))
            }
        }
    }

    @ViewBuilder
    private var framingLayer: some View {
        if viewModel.showFramingLayer {
            let lw = 2.0 * fontScale
            let drawRect = pos.insetBy(dx: lw / 2, dy: lw / 2)
            if isWhite {
                Color.white.frame(width: pos.width, height: pos.height)
                    .offset(x: pos.minX, y: pos.minY).opacity(alpha)
            } else if fl.style == .corners {
                let c = max(6 * fontScale, min(drawRect.width, drawRect.height) * fl.styleLength)
                Path { p in
                    p.move(to: .init(x: drawRect.minX, y: drawRect.minY))
                    p.addLine(to: .init(x: drawRect.minX + c, y: drawRect.minY))
                    p.move(to: .init(x: drawRect.minX, y: drawRect.minY))
                    p.addLine(to: .init(x: drawRect.minX, y: drawRect.minY + c))
                    p.move(to: .init(x: drawRect.maxX, y: drawRect.minY))
                    p.addLine(to: .init(x: drawRect.maxX - c, y: drawRect.minY))
                    p.move(to: .init(x: drawRect.maxX, y: drawRect.minY))
                    p.addLine(to: .init(x: drawRect.maxX, y: drawRect.minY + c))
                    p.move(to: .init(x: drawRect.minX, y: drawRect.maxY))
                    p.addLine(to: .init(x: drawRect.minX + c, y: drawRect.maxY))
                    p.move(to: .init(x: drawRect.minX, y: drawRect.maxY))
                    p.addLine(to: .init(x: drawRect.minX, y: drawRect.maxY - c))
                    p.move(to: .init(x: drawRect.maxX, y: drawRect.maxY))
                    p.addLine(to: .init(x: drawRect.maxX - c, y: drawRect.maxY))
                    p.move(to: .init(x: drawRect.maxX, y: drawRect.maxY))
                    p.addLine(to: .init(x: drawRect.maxX, y: drawRect.maxY - c))
                }
                .stroke(color.opacity(alpha), lineWidth: lw)
            } else {
                Rectangle().stroke(color.opacity(alpha), lineWidth: lw)
                    .frame(width: drawRect.width, height: drawRect.height)
                    .offset(x: drawRect.minX, y: drawRect.minY)
            }
            if isWhite && viewModel.showBoundaryArrows {
                parent.exportBoundaryArrows(for: pos, color: color.opacity(alpha))
            }
            framingLabels
        }
    }

    @ViewBuilder
    private var framingLabels: some View {
        if viewModel.showLabels && !fl.label.isEmpty {
            let sz = max(12.0 * fontScale, min(80.0, min(pos.width, pos.height) * 0.05))
            Text(fl.label)
                .font(.system(size: sz))
                .foregroundStyle(color.opacity(alpha))
                .offset(x: pos.minX + 8, y: pos.minY + 2 + laneY)
        }
        if viewModel.showDimensionLabels {
            let ax = Int(fl.anchorX ?? (fl.hAlign == .left ? 0
                : (fl.hAlign == .right ? cw - fl.width : (cw - fl.width) / 2)))
            let ay = Int(fl.anchorY ?? (fl.vAlign == .top ? 0
                : (fl.vAlign == .bottom ? ch - fl.height : (ch - fl.height) / 2)))
            let dimTxt = "Framing Decision: \(Int(fl.width))\u{00D7}\(Int(fl.height))"
            Text(verbatim: dimTxt)
                .font(.system(size: detailFont, design: .monospaced))
                .foregroundStyle(isWhite ? color.opacity(0.95 * alpha) : Color.white.opacity(0.85))
                .offset(
                    x: max(4, min(cw - 300 * fontScale, pos.minX + 4)),
                    y: max(4, min(ch - detailFont * 2, pos.maxY - detailFont * 2 + laneY)))
            Text(verbatim: "Anchor: \(ax), \(ay)")
                .font(.system(size: detailFont, design: .monospaced))
                .foregroundStyle(isWhite ? color.opacity(0.95 * alpha) : Color.white.opacity(0.85))
                .offset(
                    x: max(2, min(cw - 200 * fontScale, pos.maxX - 200 * fontScale - laneY)),
                    y: max(2, min(ch - detailFont * 2, pos.minY + 2 + laneY)))
        }
    }
}

// MARK: - ExportMetadataView
private struct ExportMetadataView: View {
    let viewModel: ChartGeneratorViewModel
    let cw: Double, ch: Double
    let fontScale: Double

    var body: some View {
        let mf = max(8.0, viewModel.metadataFontSize * fontScale
            * (viewModel.showLogoOverlay ? 0.88 : 1.0))
        let autoYOff = viewModel.showLogoOverlay
            ? max(18.0, 28.0 * viewModel.logoScale) * fontScale : 0.0
        let framingSum = viewModel.framelines.first
            .map { "\(Int($0.width))x\(Int($0.height))" } ?? "N/A"
        let aspectSum = viewModel.framelines.first
            .map { $0.height > 0 ? String(format: "%.2f:1", $0.width / $0.height) : "N/A" } ?? "N/A"
        let camModel = viewModel.selectedCamera.map { "\($0.manufacturer) \($0.model)" } ?? "Custom Canvas"
        let camMode = viewModel.selectedRecordingMode?.name ?? "Custom Mode"
        let isWhite = viewModel.chartBackgroundTheme == .white

        VStack(alignment: .center, spacing: 2 * fontScale) {
            Text(viewModel.metadataShowName.isEmpty ? viewModel.chartTitle : viewModel.metadataShowName)
                .font(.system(size: mf))
            if !viewModel.burnInDirector.isEmpty {
                Text("Dir: \(viewModel.burnInDirector)").font(.system(size: mf))
            }
            Text("DP: \(viewModel.metadataDOP.isEmpty ? "—" : viewModel.metadataDOP)").font(.system(size: mf))
            Text("Camera: \(camModel)").font(.system(size: mf))
            Text("Mode: \(camMode)").font(.system(size: mf))
            Text("Framing Decision: \(framingSum)").font(.system(size: mf))
            Text("Aspect Ratio: \(aspectSum)").font(.system(size: mf))
            if !viewModel.burnInSampleText1.isEmpty { Text(viewModel.burnInSampleText1).font(.system(size: mf)) }
            if !viewModel.burnInSampleText2.isEmpty { Text(viewModel.burnInSampleText2).font(.system(size: mf)) }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(isWhite ? Color.black.opacity(0.75) : Color.white.opacity(0.7))
        .frame(width: cw, height: ch, alignment: .center)
        .offset(x: viewModel.metadataOffsetX * fontScale,
                y: viewModel.metadataOffsetY * fontScale + autoYOff)
    }
}
