import SwiftUI

/// Layer colors matching the ASC FDL Viewer reference application.
enum ViewerColors {
    static let canvas = Color(red: 0.5, green: 0.5, blue: 0.5)          // Gray #808080
    static let effective = Color(red: 0.0, green: 0.4, blue: 0.8)       // Blue #0066CC
    static let protection = Color(red: 1.0, green: 0.6, blue: 0.0)      // Orange #FF9900
    static let framing = Color(red: 0.0, green: 0.8, blue: 0.4)         // Green #00CC66
    static let grid = Color(red: 0.31, green: 0.31, blue: 0.31)         // Dark gray #505050
    static let crosshair = Color.white.opacity(0.5)
}

/// Interactive canvas visualization with geometry overlays.
/// Renders geometry layers on a dark background, with optional image underlay.
/// Supports zoom (scroll wheel) and pan (drag).
struct CanvasVisualizationView: View {
    @ObservedObject var viewModel: ViewerViewModel

    var body: some View {
        GeometryReader { geo in
            let dims = viewModel.canvasDimensions ?? (width: 1920, height: 1080)
            let canvasW = dims.width
            let canvasH = dims.height
            guard canvasW > 0 && canvasH > 0 else {
                return AnyView(Text("No canvas data").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity))
            }

            let fitScale = min(geo.size.width / canvasW, geo.size.height / canvasH) * 0.9
            let totalScale = fitScale * viewModel.zoomScale
            let scaledW = canvasW * totalScale
            let scaledH = canvasH * totalScale
            let baseX = (geo.size.width - scaledW) / 2 + viewModel.panOffset.width
            let baseY = (geo.size.height - scaledH) / 2 + viewModel.panOffset.height

            return AnyView(
                ZStack(alignment: .topLeading) {
                    Color.clear

                    // Image underlay
                    if let image = viewModel.referenceImage {
                        Image(nsImage: image)
                            .resizable()
                            .frame(width: scaledW, height: scaledH)
                            .opacity(viewModel.imageOpacity)
                            .offset(x: baseX, y: baseY)
                    }

                    // Geometry layers
                    if let computedCanvas = viewModel.selectedComputedCanvas {
                        geometryOverlay(
                            canvas: computedCanvas,
                            canvasW: canvasW, canvasH: canvasH,
                            totalScale: totalScale,
                            baseX: baseX, baseY: baseY
                        )
                    }

                    // Anamorphic squeeze indicator
                    if let squeeze = viewModel.selectedCanvas?.anamorphicSqueeze, squeeze != 1.0 {
                        anamorphicIndicator(
                            squeeze: squeeze,
                            canvasW: canvasW, canvasH: canvasH,
                            totalScale: totalScale,
                            baseX: baseX, baseY: baseY
                        )
                    }

                    // HUD
                    if viewModel.showHUD {
                        hudOverlay(canvasW: canvasW, canvasH: canvasH)
                    }
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            viewModel.zoomScale = max(0.1, min(10, value))
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            viewModel.panOffset = value.translation
                        }
                )
                .onTapGesture(count: 2) {
                    viewModel.zoomToFit()
                }
            )
        }
        .background(ScrollWheelZoomView(zoomScale: Binding(
            get: { viewModel.zoomScale },
            set: { viewModel.zoomScale = $0 }
        )))
    }

    // MARK: - Geometry Overlay

    @ViewBuilder
    private func geometryOverlay(
        canvas: ComputedCanvas,
        canvasW: Double, canvasH: Double,
        totalScale: CGFloat,
        baseX: CGFloat, baseY: CGFloat
    ) -> some View {
        let cr = canvas.canvasRect

        // Grid
        if viewModel.showGridOverlay {
            gridLayer(canvasW: canvasW, canvasH: canvasH, totalScale: totalScale, baseX: baseX, baseY: baseY)
        }

        // Canvas boundary
        if viewModel.showCanvasLayer {
            drawRect(cr, scale: totalScale, baseX: baseX, baseY: baseY,
                     color: ViewerColors.canvas, lineWidth: 2, dashed: false, fill: 0.08)
            if viewModel.showDimensionLabels {
                dimLabel("\(Int(cr.width))\u{00D7}\(Int(cr.height))", rect: cr,
                         scale: totalScale, baseX: baseX, baseY: baseY,
                         color: ViewerColors.canvas, position: .topRight)
            }
        }

        // Effective area
        if viewModel.showEffectiveLayer, let eff = canvas.effectiveRect {
            drawRect(eff, scale: totalScale, baseX: baseX, baseY: baseY,
                     color: ViewerColors.effective, lineWidth: 1.5, dashed: false, fill: 0.08)
            if viewModel.showDimensionLabels {
                dimLabel("Eff \(Int(eff.width))\u{00D7}\(Int(eff.height))", rect: eff,
                         scale: totalScale, baseX: baseX, baseY: baseY,
                         color: ViewerColors.effective, position: .bottomLeft)
            }
        }

        // Framing decisions + protection
        let fds = filteredFramingDecisions(canvas)
        ForEach(Array(fds.enumerated()), id: \.offset) { _, fd in
            // Protection (behind framing)
            if viewModel.showProtectionLayer, let prot = fd.protectionRect {
                drawRect(prot, scale: totalScale, baseX: baseX, baseY: baseY,
                         color: ViewerColors.protection, lineWidth: 1.5, dashed: true, fill: 0.05)
            }

            // Framing rect
            if viewModel.showFramingLayer {
                let fr = fd.framingRect
                drawRect(fr, scale: totalScale, baseX: baseX, baseY: baseY,
                         color: ViewerColors.framing, lineWidth: 2, dashed: false, fill: 0.08)

                // Crosshair
                if viewModel.showCrosshairs {
                    crosshair(rect: fr, scale: totalScale, baseX: baseX, baseY: baseY)
                }

                // Anchor
                if viewModel.showAnchorPoints, let anchor = fd.anchorPoint {
                    anchorMarker(x: anchor.x, y: anchor.y, scale: totalScale, baseX: baseX, baseY: baseY)
                }

                // Label
                if viewModel.showLabels && !fd.label.isEmpty {
                    let fx = baseX + CGFloat(fr.x) * totalScale
                    let fy = baseY + CGFloat(fr.y) * totalScale
                    Text(fd.label)
                        .font(.system(size: max(9, min(13, CGFloat(fr.width) * totalScale * 0.025))))
                        .foregroundStyle(ViewerColors.framing)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: fx + 4, y: fy + 4)
                }

                // Dimension label
                if viewModel.showDimensionLabels {
                    dimLabel("\(Int(fr.width))\u{00D7}\(Int(fr.height))", rect: fr,
                             scale: totalScale, baseX: baseX, baseY: baseY,
                             color: ViewerColors.framing, position: .bottomRight)
                }
            }
        }
    }

    private func filteredFramingDecisions(_ canvas: ComputedCanvas) -> [ComputedFramingDecision] {
        if let idx = viewModel.selectedFramingIndex, idx < canvas.framingDecisions.count {
            return [canvas.framingDecisions[idx]]
        }
        return canvas.framingDecisions
    }

    // MARK: - Drawing Primitives

    @ViewBuilder
    private func drawRect(
        _ gr: GeometryRect,
        scale: CGFloat, baseX: CGFloat, baseY: CGFloat,
        color: Color, lineWidth: CGFloat, dashed: Bool, fill: Double
    ) -> some View {
        let x = baseX + CGFloat(gr.x) * scale
        let y = baseY + CGFloat(gr.y) * scale
        let w = CGFloat(gr.width) * scale
        let h = CGFloat(gr.height) * scale

        // Fill
        Rectangle()
            .fill(color.opacity(fill))
            .frame(width: w, height: h)
            .offset(x: x, y: y)

        // Stroke
        if dashed {
            Rectangle()
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: [8, 5]))
                .frame(width: w, height: h)
                .offset(x: x, y: y)
        } else {
            Rectangle()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: w, height: h)
                .offset(x: x, y: y)
        }
    }

    @ViewBuilder
    private func crosshair(rect gr: GeometryRect, scale: CGFloat, baseX: CGFloat, baseY: CGFloat) -> some View {
        let cx = baseX + CGFloat(gr.x + gr.width / 2) * scale
        let cy = baseY + CGFloat(gr.y + gr.height / 2) * scale
        let arm: CGFloat = 10

        Path { path in
            path.move(to: CGPoint(x: cx - arm, y: cy))
            path.addLine(to: CGPoint(x: cx + arm, y: cy))
            path.move(to: CGPoint(x: cx, y: cy - arm))
            path.addLine(to: CGPoint(x: cx, y: cy + arm))
        }
        .stroke(ViewerColors.crosshair, lineWidth: 1)
    }

    @ViewBuilder
    private func anchorMarker(x: Double, y: Double, scale: CGFloat, baseX: CGFloat, baseY: CGFloat) -> some View {
        let px = baseX + CGFloat(x) * scale
        let py = baseY + CGFloat(y) * scale

        Circle()
            .fill(ViewerColors.framing)
            .frame(width: 6, height: 6)
            .offset(x: px - 3, y: py - 3)
    }

    private enum LabelPosition { case topRight, bottomLeft, bottomRight }

    @ViewBuilder
    private func dimLabel(
        _ text: String,
        rect gr: GeometryRect,
        scale: CGFloat, baseX: CGFloat, baseY: CGFloat,
        color: Color, position: LabelPosition
    ) -> some View {
        let rx = baseX + CGFloat(gr.x) * scale
        let ry = baseY + CGFloat(gr.y) * scale
        let rw = CGFloat(gr.width) * scale
        let rh = CGFloat(gr.height) * scale

        let offset: CGPoint = {
            switch position {
            case .topRight: return CGPoint(x: rx + rw - 4, y: ry + 2)
            case .bottomLeft: return CGPoint(x: rx + 4, y: ry + rh - 16)
            case .bottomRight: return CGPoint(x: rx + rw - 4, y: ry + rh - 16)
            }
        }()

        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(color.opacity(0.9))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 2))
            .offset(x: offset.x, y: offset.y)
    }

    @ViewBuilder
    private func gridLayer(canvasW: Double, canvasH: Double, totalScale: CGFloat, baseX: CGFloat, baseY: CGFloat) -> some View {
        let spacing = viewModel.gridSpacing
        Path { path in
            var x = spacing
            while x < canvasW {
                let px = baseX + CGFloat(x) * totalScale
                path.move(to: CGPoint(x: px, y: baseY))
                path.addLine(to: CGPoint(x: px, y: baseY + canvasH * totalScale))
                x += spacing
            }
            var y = spacing
            while y < canvasH {
                let py = baseY + CGFloat(y) * totalScale
                path.move(to: CGPoint(x: baseX, y: py))
                path.addLine(to: CGPoint(x: baseX + canvasW * totalScale, y: py))
                y += spacing
            }
        }
        .stroke(ViewerColors.grid, lineWidth: 0.5)
    }

    // MARK: - HUD

    @ViewBuilder
    private func hudOverlay(canvasW: Double, canvasH: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let canvas = viewModel.selectedCanvas {
                Text("Canvas: \(Int(canvasW))\u{00D7}\(Int(canvasH))")
                    .foregroundStyle(ViewerColors.canvas)
                if let eff = canvas.effectiveDimensions {
                    Text("Effective: \(Int(eff.width))\u{00D7}\(Int(eff.height))")
                        .foregroundStyle(ViewerColors.effective)
                }
                if let squeeze = canvas.anamorphicSqueeze, squeeze != 1.0 {
                    Text("Squeeze: \(String(format: "%.2f\u{00D7}", squeeze))")
                }
                ForEach(Array(canvas.framingDecisions.enumerated()), id: \.offset) { _, fd in
                    Text("\(fd.label ?? "FD"): \(Int(fd.dimensions.width))\u{00D7}\(Int(fd.dimensions.height))")
                        .foregroundStyle(ViewerColors.framing)
                }
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white.opacity(0.8))
        .padding(8)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Anamorphic Indicator

    @ViewBuilder
    private func anamorphicIndicator(
        squeeze: Double,
        canvasW: Double, canvasH: Double,
        totalScale: CGFloat, baseX: CGFloat, baseY: CGFloat
    ) -> some View {
        let cx = baseX + canvasW * totalScale / 2
        let cy = baseY + canvasH * totalScale / 2
        let radius = min(canvasW, canvasH) * totalScale * 0.3
        let rx = radius * squeeze
        let ry = radius

        Ellipse()
            .stroke(Color.yellow.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .frame(width: rx * 2, height: ry * 2)
            .offset(x: cx - rx, y: cy - ry)

        Text("\(String(format: "%.1f", squeeze))\u{00D7} squeeze")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.yellow.opacity(0.6))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
            .offset(x: cx + rx + 4, y: cy - 8)
    }
}

// MARK: - Scroll Wheel Zoom (macOS native)

/// NSView wrapper that captures scroll wheel events for zoom.
struct ScrollWheelZoomView: NSViewRepresentable {
    @Binding var zoomScale: CGFloat

    func makeNSView(context: Context) -> ScrollWheelCaptureNSView {
        let view = ScrollWheelCaptureNSView()
        view.onScroll = { delta in
            let factor = 1.0 + delta * 0.03
            zoomScale = max(0.05, min(20, zoomScale * factor))
        }
        return view
    }

    func updateNSView(_ nsView: ScrollWheelCaptureNSView, context: Context) {}
}

class ScrollWheelCaptureNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let delta = event.deltaY
        if abs(delta) > 0.01 {
            onScroll?(delta)
        }
    }
}
