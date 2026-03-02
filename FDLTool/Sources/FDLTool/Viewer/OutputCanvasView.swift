import SwiftUI

/// Renders the output canvas after template application.
/// Mirrors CanvasVisualizationView but uses outputGeometry and outputDocument.
struct OutputCanvasView: View {
    @ObservedObject var viewModel: ViewerViewModel

    var body: some View {
        GeometryReader { geo in
            let dims = viewModel.outputCanvasDimensions ?? (width: 1920, height: 1080)
            let canvasW = dims.width
            let canvasH = dims.height
            guard canvasW > 0 && canvasH > 0 else {
                return AnyView(Text("No output data").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity))
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

                    if let computedCanvas = viewModel.outputComputedCanvas {
                        outputGeometryOverlay(
                            canvas: computedCanvas,
                            canvasW: canvasW, canvasH: canvasH,
                            totalScale: totalScale,
                            baseX: baseX, baseY: baseY
                        )
                    }

                    if viewModel.showHUD {
                        outputHUD(canvasW: canvasW, canvasH: canvasH)
                    }
                }
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

    @ViewBuilder
    private func outputGeometryOverlay(
        canvas: ComputedCanvas,
        canvasW: Double, canvasH: Double,
        totalScale: CGFloat,
        baseX: CGFloat, baseY: CGFloat
    ) -> some View {
        let cr = canvas.canvasRect

        if viewModel.showGridOverlay {
            gridLayer(canvasW: canvasW, canvasH: canvasH, totalScale: totalScale, baseX: baseX, baseY: baseY)
        }

        if viewModel.showCanvasLayer {
            drawRect(cr, scale: totalScale, baseX: baseX, baseY: baseY,
                     color: ViewerColors.canvas, lineWidth: 2, dashed: false, fill: 0.08)
            if viewModel.showDimensionLabels {
                dimLabel("\(Int(cr.width))\u{00D7}\(Int(cr.height))", rect: cr,
                         scale: totalScale, baseX: baseX, baseY: baseY,
                         color: ViewerColors.canvas, position: .topRight)
            }
        }

        if viewModel.showEffectiveLayer, let eff = canvas.effectiveRect {
            drawRect(eff, scale: totalScale, baseX: baseX, baseY: baseY,
                     color: ViewerColors.effective, lineWidth: 1.5, dashed: false, fill: 0.08)
            if viewModel.showDimensionLabels {
                dimLabel("Eff \(Int(eff.width))\u{00D7}\(Int(eff.height))", rect: eff,
                         scale: totalScale, baseX: baseX, baseY: baseY,
                         color: ViewerColors.effective, position: .bottomLeft)
            }
        }

        ForEach(Array(canvas.framingDecisions.enumerated()), id: \.offset) { _, fd in
            if viewModel.showProtectionLayer, let prot = fd.protectionRect {
                drawRect(prot, scale: totalScale, baseX: baseX, baseY: baseY,
                         color: ViewerColors.protection, lineWidth: 1.5, dashed: true, fill: 0.05)
            }

            if viewModel.showFramingLayer {
                let fr = fd.framingRect
                drawRect(fr, scale: totalScale, baseX: baseX, baseY: baseY,
                         color: ViewerColors.framing, lineWidth: 2, dashed: false, fill: 0.08)

                if viewModel.showCrosshairs {
                    crosshair(rect: fr, scale: totalScale, baseX: baseX, baseY: baseY)
                }

                if viewModel.showAnchorPoints, let anchor = fd.anchorPoint {
                    anchorMarker(x: anchor.x, y: anchor.y, scale: totalScale, baseX: baseX, baseY: baseY)
                }

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

                if viewModel.showDimensionLabels {
                    dimLabel("\(Int(fr.width))\u{00D7}\(Int(fr.height))", rect: fr,
                             scale: totalScale, baseX: baseX, baseY: baseY,
                             color: ViewerColors.framing, position: .bottomRight)
                }
            }
        }
    }

    // MARK: - Drawing Primitives (shared with CanvasVisualizationView)

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

        Rectangle()
            .fill(color.opacity(fill))
            .frame(width: w, height: h)
            .offset(x: x, y: y)

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
        _ text: String, rect gr: GeometryRect,
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
    private func outputHUD(canvasW: Double, canvasH: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("OUTPUT")
                .foregroundStyle(.yellow)

            if let info = viewModel.transformInfo {
                Text("Source: \(info.sourceCanvas)")
                    .foregroundStyle(ViewerColors.canvas)
                if let outCanvas = info.outputCanvas {
                    Text("Output: \(outCanvas)")
                        .foregroundStyle(ViewerColors.effective)
                }
                if let outFD = info.outputFraming {
                    Text("Framing: \(outFD)")
                        .foregroundStyle(ViewerColors.framing)
                }
            }

            Text("Template: \(viewModel.templateConfig.label)")
                .foregroundStyle(.white.opacity(0.6))
            Text("\(viewModel.templateConfig.targetWidth)\u{00D7}\(viewModel.templateConfig.targetHeight)")
                .foregroundStyle(.white.opacity(0.6))
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white.opacity(0.8))
        .padding(8)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
