import SwiftUI
import WebKit

/// Live-rendered chart preview. Displays SVG from Python backend or a native SwiftUI approximation.
struct ChartCanvasView: View {
    @ObservedObject var viewModel: ChartGeneratorViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Chart Preview")
                    .font(.headline)
                Spacer()

                if viewModel.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: { viewModel.generatePreview() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isGenerating)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Canvas area
            if let svg = viewModel.previewSVG {
                SVGWebView(svg: svg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.framelines.isEmpty {
                // Native SwiftUI preview fallback
                nativePreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Add framelines to generate a chart preview")
                .foregroundStyle(.secondary)
            Text("Use the configuration panel to select a camera and add framing intents.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    /// Native SwiftUI approximation of the framing chart with all geometry layers.
    @ViewBuilder
    private var nativePreview: some View {
        let cw = viewModel.canvasWidth
        let ch = viewModel.canvasHeight
        guard cw > 0 && ch > 0 else { return AnyView(emptyState) }

        return AnyView(
            GeometryReader { geo in
                let scale = min(geo.size.width / cw, geo.size.height / ch) * 0.85
                let scaledW = cw * scale
                let scaledH = ch * scale
                let originX = (geo.size.width - scaledW) / 2
                let originY = (geo.size.height - scaledH) / 2

                ZStack(alignment: .topLeading) {
                    Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))

                    // Grid
                    if viewModel.showGridOverlay && viewModel.gridSpacing > 0 {
                        chartGrid(
                            canvasW: cw, canvasH: ch, scale: scale,
                            originX: originX, originY: originY,
                            scaledW: scaledW, scaledH: scaledH
                        )
                    }

                    // Canvas boundary
                    if viewModel.showCanvasLayer {
                        Rectangle()
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            .frame(width: scaledW, height: scaledH)
                            .offset(x: originX, y: originY)

                        if viewModel.showDimensionLabels {
                            Text(verbatim: "\(Int(cw))\u{00D7}\(Int(ch))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.gray)
                                .offset(x: originX + scaledW - 80, y: originY + scaledH - 16)
                        }
                    }

                    // Effective area
                    if viewModel.showEffectiveLayer,
                       let ew = viewModel.canvasEffectiveWidth,
                       let eh = viewModel.canvasEffectiveHeight {
                        let esw = ew * scale
                        let esh = eh * scale
                        let ex = originX + viewModel.canvasEffectiveAnchorX * scale
                        let ey = originY + viewModel.canvasEffectiveAnchorY * scale

                        Rectangle()
                            .stroke(Color.teal, lineWidth: 1.5)
                            .frame(width: esw, height: esh)
                            .offset(x: ex, y: ey)

                        if viewModel.showDimensionLabels {
                            Text(verbatim: "Eff \(Int(ew))\u{00D7}\(Int(eh))")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.teal.opacity(0.8))
                                .padding(.horizontal, 2)
                                .padding(.vertical, 1)
                                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 2))
                                .offset(x: ex + 4, y: ey + esh - 16)
                        }
                    }

                    // Framelines (protection + framing)
                    ForEach(viewModel.framelines) { fl in
                        let color = Color(hex: fl.color) ?? .gray
                        let pos = framelinePosition(fl, canvasW: cw, canvasH: ch, scale: scale, originX: originX, originY: originY)

                        if viewModel.showProtectionLayer,
                           let prot = viewModel.effectiveProtection(for: fl) {
                            let psw = prot.width * scale
                            let psh = prot.height * scale
                            let px = originX + (fl.protectionAnchorX.map { $0 * scale } ?? (scaledW - psw) / 2)
                            let py = originY + (fl.protectionAnchorY.map { $0 * scale } ?? (scaledH - psh) / 2)

                            Rectangle()
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                .frame(width: psw, height: psh)
                                .offset(x: px, y: py)

                            if viewModel.showDimensionLabels {
                                Text(verbatim: "Prot \(Int(prot.width))\u{00D7}\(Int(prot.height))")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.orange.opacity(0.7))
                                    .padding(.horizontal, 2)
                                    .padding(.vertical, 1)
                                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 2))
                                    .offset(x: px + 4, y: py + 2)
                            }
                        }

                        if viewModel.showFramingLayer {
                            Rectangle()
                                .stroke(color, lineWidth: 2)
                                .frame(width: pos.width, height: pos.height)
                                .offset(x: pos.minX, y: pos.minY)

                            // Crosshair
                            if viewModel.showCrosshairs {
                                let cx = pos.midX
                                let cy = pos.midY
                                Path { p in
                                    p.move(to: CGPoint(x: cx - 8, y: cy))
                                    p.addLine(to: CGPoint(x: cx + 8, y: cy))
                                    p.move(to: CGPoint(x: cx, y: cy - 8))
                                    p.addLine(to: CGPoint(x: cx, y: cy + 8))
                                }
                                .stroke(color.opacity(0.6), lineWidth: 1)
                            }

                            if viewModel.showLabels && !fl.label.isEmpty {
                                Text(fl.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(color)
                                    .offset(x: pos.minX + 4, y: pos.minY + 2)
                            }

                            if viewModel.showDimensionLabels {
                                Text(verbatim: "\(Int(fl.width))\u{00D7}\(Int(fl.height))")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(color.opacity(0.7))
                                    .padding(.horizontal, 2)
                                    .padding(.vertical, 1)
                                    .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 2))
                                    .offset(x: pos.maxX - 60, y: pos.maxY - 16)
                            }
                        }
                    }

                    // Squeeze reference ellipse
                    if viewModel.showSqueezeCircle && viewModel.anamorphicSqueeze != 1.0 {
                        let centerX = originX + scaledW / 2
                        let centerY = originY + scaledH / 2
                        let radius = min(scaledW, scaledH) * 0.4
                        let rx = radius / viewModel.anamorphicSqueeze
                        let ry = radius

                        Path { p in
                            p.addEllipse(in: CGRect(
                                x: centerX - rx,
                                y: centerY - ry,
                                width: rx * 2,
                                height: ry * 2
                            ))
                        }
                        .stroke(Color.gray.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }

                    // Title
                    if !viewModel.chartTitle.isEmpty {
                        Text(viewModel.chartTitle)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .offset(y: 8)
                    }

                    // Metadata overlay
                    if viewModel.metadataOverlayShow {
                        VStack(alignment: .leading, spacing: 2) {
                            if !viewModel.metadataShowName.isEmpty {
                                Text(viewModel.metadataShowName)
                                    .font(.system(size: 9))
                            }
                            if !viewModel.metadataDOP.isEmpty {
                                Text("DP: \(viewModel.metadataDOP)")
                                    .font(.system(size: 9))
                            }
                        }
                        .foregroundStyle(.white.opacity(0.6))
                        .offset(x: originX + 4, y: originY + 4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        )
    }

    private func framelinePosition(
        _ fl: Frameline,
        canvasW: Double, canvasH: Double,
        scale: Double,
        originX: Double, originY: Double
    ) -> CGRect {
        let fw = fl.width * scale
        let fh = fl.height * scale
        let scaledW = canvasW * scale
        let scaledH = canvasH * scale

        if let ax = fl.anchorX, let ay = fl.anchorY {
            return CGRect(x: originX + ax * scale, y: originY + ay * scale, width: fw, height: fh)
        }

        let fx: Double
        switch fl.hAlign {
        case .left: fx = originX
        case .right: fx = originX + scaledW - fw
        case .center: fx = originX + (scaledW - fw) / 2
        }

        let fy: Double
        switch fl.vAlign {
        case .top: fy = originY
        case .bottom: fy = originY + scaledH - fh
        case .center: fy = originY + (scaledH - fh) / 2
        }

        return CGRect(x: fx, y: fy, width: fw, height: fh)
    }

    @ViewBuilder
    private func chartGrid(
        canvasW: Double, canvasH: Double, scale: Double,
        originX: Double, originY: Double,
        scaledW: Double, scaledH: Double
    ) -> some View {
        let spacing = viewModel.gridSpacing
        Path { p in
            var x = spacing
            while x < canvasW {
                let px = originX + x * scale
                p.move(to: CGPoint(x: px, y: originY))
                p.addLine(to: CGPoint(x: px, y: originY + scaledH))
                x += spacing
            }
            var y = spacing
            while y < canvasH {
                let py = originY + y * scale
                p.move(to: CGPoint(x: originX, y: py))
                p.addLine(to: CGPoint(x: originX + scaledW, y: py))
                y += spacing
            }
        }
        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
    }
}

// MARK: - SVG Web View (NSViewRepresentable)

/// Renders SVG content using a WKWebView.
struct SVGWebView: NSViewRepresentable {
    let svg: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
            body { margin: 0; display: flex; justify-content: center; align-items: center;
                   min-height: 100vh; background: transparent; }
            svg { max-width: 100%; max-height: 100vh; }
        </style>
        </head>
        <body>\(svg)</body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
