import SwiftUI
import WebKit

/// Live-rendered chart preview. Displays SVG from Python backend or a native SwiftUI approximation.
struct ChartCanvasView: View {
    @ObservedObject var viewModel: ChartGeneratorViewModel
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Chart Preview")
                    .font(.headline)
                Spacer()

                Picker("", selection: $viewModel.chartBackgroundTheme) {
                    Text("Dark").tag(ChartBackgroundTheme.dark)
                    Text("White").tag(ChartBackgroundTheme.white)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 140)
                .onChange(of: viewModel.chartBackgroundTheme) { _, _ in
                    viewModel.previewSVG = nil
                }

                Button(action: { zoomScale = max(zoomScale / 1.25, 0.1) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Text(verbatim: "\(Int(zoomScale * 100))%")
                    .font(.caption)
                    .frame(width: 36)
                Button(action: { zoomScale = min(zoomScale * 1.25, 10) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Button(action: { zoomScale = 1.0; panOffset = .zero }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Fit to view")

                Group {
                    if viewModel.previewDesqueezed {
                        Button(action: {
                            guard viewModel.anamorphicSqueeze > 1.0 else { return }
                            viewModel.previewDesqueezed.toggle()
                            viewModel.previewSVG = nil
                        }) {
                            Label("De-squeeze", systemImage: "checkmark.rectangle.expand.vertical")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: {
                            guard viewModel.anamorphicSqueeze > 1.0 else { return }
                            viewModel.previewDesqueezed.toggle()
                            viewModel.previewSVG = nil
                        }) {
                            Label("De-squeeze", systemImage: "rectangle.expand.vertical")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .disabled(viewModel.anamorphicSqueeze <= 1.0 || viewModel.isGenerating)
                .help("Preview source desqueezed display without changing chart values")

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
                    .gesture(previewGestures)
                    .clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.framelines.isEmpty {
                // Native SwiftUI preview fallback
                nativePreview
                    .gesture(previewGestures)
                    .clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: viewModel.anamorphicSqueeze) { _, newValue in
            if newValue <= 1.0 {
                viewModel.previewDesqueezed = false
            }
        }
        .onChange(of: viewModel.showSiemensStars) { _, _ in
            viewModel.previewSVG = nil
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
    private var nativePreview: some View {
        let cw = viewModel.canvasWidth
        let ch = viewModel.canvasHeight
        guard cw > 0 && ch > 0 else { return AnyView(emptyState) }

        return AnyView(
            GeometryReader { geo in
                let desqueezeFactor = (viewModel.previewDesqueezed && viewModel.anamorphicSqueeze > 1.0) ? viewModel.anamorphicSqueeze : 1.0
                let baseScale = min(geo.size.width / (cw * desqueezeFactor), geo.size.height / ch) * 0.85 * Double(zoomScale)
                let scaleX = baseScale * desqueezeFactor
                let scaleY = baseScale
                let scaledW = cw * scaleX
                let scaledH = ch * scaleY
                let originX = (geo.size.width - scaledW) / 2 + Double(panOffset.width)
                let originY = (geo.size.height - scaledH) / 2 + Double(panOffset.height)

                ZStack(alignment: .topLeading) {
                    Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))

                    // Canvas boundary
                    if viewModel.showCanvasLayer {
                        if viewModel.chartBackgroundTheme == .white {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: scaledW, height: scaledH)
                                .offset(x: originX, y: originY)
                        }

                        Rectangle()
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            .frame(width: scaledW, height: scaledH)
                            .offset(x: originX, y: originY)

                        if viewModel.showDimensionLabels {
                            let labelPos = canvasDimensionLabelPosition(
                                originX: originX,
                                originY: originY,
                                scaledW: scaledW,
                                scaledH: scaledH,
                                canvasW: cw,
                                canvasH: ch,
                                scaleX: scaleX,
                                scaleY: scaleY
                            )
                            Text(verbatim: "Canvas: \(Int(cw))\u{00D7}\(Int(ch))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.7) : .gray)
                                .offset(x: labelPos.x, y: labelPos.y)
                        }
                    }

                    // Grid (draw after canvas fill so it is visible in white mode)
                    if viewModel.showGridOverlay && viewModel.gridSpacing > 0 {
                        chartGrid(
                            canvasW: cw, canvasH: ch, scaleX: scaleX, scaleY: scaleY,
                            originX: originX, originY: originY,
                            scaledW: scaledW, scaledH: scaledH
                        )
                    }

                    if viewModel.showChartMarkers {
                        let markerColor: Color = viewModel.chartBackgroundTheme == .white ? .black.opacity(0.65) : .white.opacity(0.65)
                        Path { p in
                            p.move(to: CGPoint(x: originX + scaledW / 2, y: originY))
                            p.addLine(to: CGPoint(x: originX + scaledW / 2, y: originY + 14))
                            p.move(to: CGPoint(x: originX + scaledW / 2, y: originY + scaledH))
                            p.addLine(to: CGPoint(x: originX + scaledW / 2, y: originY + scaledH - 14))
                            p.move(to: CGPoint(x: originX, y: originY + scaledH / 2))
                            p.addLine(to: CGPoint(x: originX + 14, y: originY + scaledH / 2))
                            p.move(to: CGPoint(x: originX + scaledW, y: originY + scaledH / 2))
                            p.addLine(to: CGPoint(x: originX + scaledW - 14, y: originY + scaledH / 2))
                        }
                        .stroke(markerColor, lineWidth: 1)
                    }

                    if viewModel.showSiemensStars {
                        let starRects = siemensStarRects(originX: originX, originY: originY, canvasW: cw, canvasH: ch, scaleX: scaleX, scaleY: scaleY)
                        ForEach(Array(starRects.enumerated()), id: \.offset) { _, rect in
                            SiemensStarShape(theme: viewModel.chartBackgroundTheme)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }

                    // Effective area
                    if viewModel.showEffectiveLayer,
                       let ew = viewModel.canvasEffectiveWidth,
                       let eh = viewModel.canvasEffectiveHeight {
                        let esw = ew * scaleX
                        let esh = eh * scaleY
                        let ex = originX + viewModel.canvasEffectiveAnchorX * scaleX
                        let ey = originY + viewModel.canvasEffectiveAnchorY * scaleY
                        let effectiveRect = adjustedForInsideStroke(CGRect(x: ex, y: ey, width: esw, height: esh), lineWidth: 1.5)

                        Rectangle()
                            .stroke(Color.teal, lineWidth: 1.5)
                            .frame(width: effectiveRect.width, height: effectiveRect.height)
                            .offset(x: effectiveRect.minX, y: effectiveRect.minY)

                        if viewModel.showDimensionLabels {
                            Text(verbatim: "Effective: \(Int(ew))\u{00D7}\(Int(eh))")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.8) : .white.opacity(0.8))
                                .offset(x: ex + 4, y: ey + esh - 16)
                            Text(verbatim: "Anchor: \(Int(viewModel.canvasEffectiveAnchorX)), \(Int(viewModel.canvasEffectiveAnchorY))")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.8) : .white.opacity(0.8))
                                .offset(x: ex + 4, y: ey + esh - 30)
                        }
                    }

                    // Framelines (protection + framing)
                    ForEach(viewModel.framelines) { fl in
                        let color = Color(hex: fl.color) ?? .gray
                        let pos = framelinePosition(fl, canvasW: cw, canvasH: ch, scaleX: scaleX, scaleY: scaleY, originX: originX, originY: originY)

                        if viewModel.showProtectionLayer,
                           let prot = viewModel.effectiveProtection(for: fl) {
                            let psw = prot.width * scaleX
                            let psh = prot.height * scaleY
                            let px = originX + (fl.protectionAnchorX.map { $0 * scaleX } ?? (scaledW - psw) / 2)
                            let py = originY + (fl.protectionAnchorY.map { $0 * scaleY } ?? (scaledH - psh) / 2)
                            let protectionRect = adjustedForInsideStroke(CGRect(x: px, y: py, width: psw, height: psh), lineWidth: 1)

                            Rectangle()
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                .frame(width: protectionRect.width, height: protectionRect.height)
                                .offset(x: protectionRect.minX, y: protectionRect.minY)

                            if viewModel.showDimensionLabels {
                                let protectionAnchorX = Int(
                                    fl.protectionAnchorX
                                        ?? (viewModel.canvasWidth - prot.width) / 2
                                )
                                let protectionAnchorY = Int(
                                    fl.protectionAnchorY
                                        ?? (viewModel.canvasHeight - prot.height) / 2
                                )
                                Text(verbatim: "Protection: \(Int(prot.width))\u{00D7}\(Int(prot.height))")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.8) : .white.opacity(0.8))
                                    .offset(x: protectionRect.minX + 4, y: protectionRect.minY + 2)
                                let protectionAnchorText = "Anchor: \(protectionAnchorX), \(protectionAnchorY)"
                                Text(verbatim: protectionAnchorText)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.8) : .white.opacity(0.8))
                                    .offset(x: max(originX + 2, protectionRect.maxX - 126), y: max(originY + 2, protectionRect.maxY - 16))
                            }
                        }

                        if viewModel.showFramingLayer {
                            let drawRect = adjustedForInsideStroke(pos, lineWidth: 2)
                            if fl.style == .corners {
                                let c = max(6, min(drawRect.width, drawRect.height) * fl.styleLength)
                                Path { p in
                                    // top-left
                                    p.move(to: CGPoint(x: drawRect.minX, y: drawRect.minY))
                                    p.addLine(to: CGPoint(x: drawRect.minX + c, y: drawRect.minY))
                                    p.move(to: CGPoint(x: drawRect.minX, y: drawRect.minY))
                                    p.addLine(to: CGPoint(x: drawRect.minX, y: drawRect.minY + c))
                                    // top-right
                                    p.move(to: CGPoint(x: drawRect.maxX, y: drawRect.minY))
                                    p.addLine(to: CGPoint(x: drawRect.maxX - c, y: drawRect.minY))
                                    p.move(to: CGPoint(x: drawRect.maxX, y: drawRect.minY))
                                    p.addLine(to: CGPoint(x: drawRect.maxX, y: drawRect.minY + c))
                                    // bottom-left
                                    p.move(to: CGPoint(x: drawRect.minX, y: drawRect.maxY))
                                    p.addLine(to: CGPoint(x: drawRect.minX + c, y: drawRect.maxY))
                                    p.move(to: CGPoint(x: drawRect.minX, y: drawRect.maxY))
                                    p.addLine(to: CGPoint(x: drawRect.minX, y: drawRect.maxY - c))
                                    // bottom-right
                                    p.move(to: CGPoint(x: drawRect.maxX, y: drawRect.maxY))
                                    p.addLine(to: CGPoint(x: drawRect.maxX - c, y: drawRect.maxY))
                                    p.move(to: CGPoint(x: drawRect.maxX, y: drawRect.maxY))
                                    p.addLine(to: CGPoint(x: drawRect.maxX, y: drawRect.maxY - c))
                                }
                                .stroke(color, lineWidth: 2)
                            } else {
                                Rectangle()
                                    .stroke(color, lineWidth: 2)
                                    .frame(width: drawRect.width, height: drawRect.height)
                                    .offset(x: drawRect.minX, y: drawRect.minY)
                            }

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
                                let labelSize = max(8.0, min(14.0, min(pos.width, pos.height) * 0.05))
                                let labelX = pos.midX - 40
                                let labelY = pos.minY + 2
                                Text(fl.label)
                                    .font(.system(size: labelSize))
                                    .foregroundStyle(color)
                                    .offset(x: labelX, y: labelY)
                            }

                            if viewModel.showDimensionLabels {
                                let anchorX = Int(fl.anchorX ?? (fl.hAlign == .left ? 0 : (fl.hAlign == .right ? (viewModel.canvasWidth - fl.width) : (viewModel.canvasWidth - fl.width) / 2)))
                                let anchorY = Int(fl.anchorY ?? (fl.vAlign == .top ? 0 : (fl.vAlign == .bottom ? (viewModel.canvasHeight - fl.height) : (viewModel.canvasHeight - fl.height) / 2)))
                                let dimText = "Framing Decision: \(Int(fl.width))\u{00D7}\(Int(fl.height))"
                                let dimX = pos.midX - 72
                                let dimY = pos.maxY - 14
                                Text(verbatim: dimText)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.85) : .white.opacity(0.85))
                                    .offset(x: dimX, y: dimY)
                                    .help(dimText)
                                Text(verbatim: "Anchor: \(anchorX), \(anchorY)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.85) : .white.opacity(0.85))
                                    .offset(x: max(originX + 2, pos.maxX - 126), y: max(originY + 2, pos.maxY - 16))
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

                    if viewModel.showCenterMarker {
                        let cx = originX + scaledW / 2
                        let cy = originY + scaledH / 2
                        Path { p in
                            p.move(to: CGPoint(x: cx - 12, y: cy))
                            p.addLine(to: CGPoint(x: cx + 12, y: cy))
                            p.move(to: CGPoint(x: cx, y: cy - 12))
                            p.addLine(to: CGPoint(x: cx, y: cy + 12))
                        }
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    }

                    // Title
                    if !viewModel.chartTitle.isEmpty {
                        Text(viewModel.chartTitle)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .offset(y: 8)
                    }

                    // Metadata / burn-ins
                    if viewModel.metadataBurnInEnabled {
                        let framingSummary = viewModel.framelines.first.map { "\(Int($0.width))x\(Int($0.height))" } ?? "N/A"
                        let aspectSummary = viewModel.framelines.first.map { $0.height > 0 ? String(format: "%.2f:1", $0.width / $0.height) : "N/A" } ?? "N/A"
                        let cameraModel = viewModel.selectedCamera.map { "\($0.manufacturer) \($0.model)" } ?? "Custom Canvas"
                        let recordingMode = viewModel.selectedRecordingMode?.name ?? "Custom Mode"
                        VStack(alignment: .center, spacing: 2) {
                            Text(viewModel.metadataShowName.isEmpty ? viewModel.chartTitle : viewModel.metadataShowName).font(.system(size: viewModel.metadataFontSize))
                            if !viewModel.burnInDirector.isEmpty { Text("Dir: \(viewModel.burnInDirector)").font(.system(size: viewModel.metadataFontSize)) }
                            Text("DP: \(viewModel.metadataDOP.isEmpty ? "—" : viewModel.metadataDOP)").font(.system(size: viewModel.metadataFontSize))
                            Text("Camera: \(cameraModel)").font(.system(size: viewModel.metadataFontSize))
                            Text("Mode: \(recordingMode)").font(.system(size: viewModel.metadataFontSize))
                            Text("Framing Decision: \(framingSummary)").font(.system(size: viewModel.metadataFontSize))
                            Text("Aspect Ratio: \(aspectSummary)").font(.system(size: viewModel.metadataFontSize))
                            if !viewModel.burnInSampleText1.isEmpty { Text(viewModel.burnInSampleText1).font(.system(size: viewModel.metadataFontSize)) }
                            if !viewModel.burnInSampleText2.isEmpty { Text(viewModel.burnInSampleText2).font(.system(size: viewModel.metadataFontSize)) }
                        }
                        .multilineTextAlignment(.center)
                        .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.75) : .white.opacity(0.7))
                        .frame(width: scaledW, height: scaledH, alignment: .center)
                        .offset(x: originX + viewModel.metadataOffsetX, y: originY + viewModel.metadataOffsetY)
                    }

                    if viewModel.showLogoOverlay {
                        let centerX = originX + scaledW / 2
                        let centerY = originY + scaledH / 2
                        Group {
                            if let data = viewModel.logoImageData,
                               let nsImage = NSImage(data: data) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80 * viewModel.logoScale, height: 30 * viewModel.logoScale)
                            } else if !viewModel.logoText.isEmpty {
                                Text(viewModel.logoText)
                                    .font(.system(size: 10 * viewModel.logoScale))
                                    .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.75) : .white.opacity(0.7))
                            }
                        }
                        .position(x: centerX + viewModel.logoOffsetX, y: centerY + viewModel.logoOffsetY)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        )
    }

    private func framelinePosition(
        _ fl: Frameline,
        canvasW: Double, canvasH: Double,
        scaleX: Double, scaleY: Double,
        originX: Double, originY: Double
    ) -> CGRect {
        let fw = fl.width * scaleX
        let fh = fl.height * scaleY
        let scaledW = canvasW * scaleX
        let scaledH = canvasH * scaleY

        if let ax = fl.anchorX, let ay = fl.anchorY {
            return CGRect(x: originX + ax * scaleX, y: originY + ay * scaleY, width: fw, height: fh)
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

    private func siemensStarRects(originX: Double, originY: Double, canvasW: Double, canvasH: Double, scaleX: Double, scaleY: Double) -> [CGRect] {
        let target: CGRect = {
            guard let first = viewModel.framelines.first else {
                return CGRect(x: originX, y: originY, width: canvasW * scaleX, height: canvasH * scaleY)
            }
            return framelinePosition(first, canvasW: canvasW, canvasH: canvasH, scaleX: scaleX, scaleY: scaleY, originX: originX, originY: originY)
        }()
        let base = max(34.0, min(68.0, min(target.width, target.height) * 0.125))
        let factor: Double
        switch viewModel.siemensStarSize {
        case .small: factor = 1.15
        case .medium: factor = 1.60
        case .large: factor = 2.05
        }
        let h = base * factor
        let squeeze = max(1.0, viewModel.anamorphicSqueeze)
        let previewFactor = (viewModel.previewDesqueezed && squeeze > 1.0) ? squeeze : 1.0
        // In sensor/squeezed view stars follow source anamorphic squeeze.
        // In de-squeezed preview they morph with canvas back to 1:1.
        let w = (h / squeeze) * previewFactor
        let insetX = (w / 2) + max(18.0, target.width * 0.12)
        let insetY = (h / 2) + max(18.0, target.height * 0.12)
        return [
            CGRect(x: target.minX + insetX - w / 2, y: target.minY + insetY - h / 2, width: w, height: h),
            CGRect(x: target.maxX - insetX - w / 2, y: target.minY + insetY - h / 2, width: w, height: h),
            CGRect(x: target.minX + insetX - w / 2, y: target.maxY - insetY - h / 2, width: w, height: h),
            CGRect(x: target.maxX - insetX - w / 2, y: target.maxY - insetY - h / 2, width: w, height: h),
        ]
    }

    private func canvasDimensionLabelPosition(
        originX: Double,
        originY: Double,
        scaledW: Double,
        scaledH: Double,
        canvasW: Double,
        canvasH: Double,
        scaleX: Double,
        scaleY: Double
    ) -> (x: Double, y: Double) {
        var x = originX + scaledW - 150
        var y = originY + scaledH - 16
        for fl in viewModel.framelines {
            let rect = framelinePosition(fl, canvasW: canvasW, canvasH: canvasH, scaleX: scaleX, scaleY: scaleY, originX: originX, originY: originY)
            let overlaps = x + 146 > rect.minX && x < rect.maxX && y + 12 > rect.minY && y < rect.maxY
            if overlaps {
                y = max(originY + 4, rect.minY - 14)
                x = min(x, rect.minX - 150)
            }
        }
        x = min(max(x, originX + 4), originX + scaledW - 146)
        y = min(max(y, originY + 10), originY + scaledH - 4)
        return (x, y)
    }

    private func adjustedForInsideStroke(_ rect: CGRect, lineWidth: Double) -> CGRect {
        let half = lineWidth / 2.0
        return rect.insetBy(dx: half, dy: half)
    }

    @ViewBuilder
    private func chartGrid(
        canvasW: Double, canvasH: Double, scaleX: Double, scaleY: Double,
        originX: Double, originY: Double,
        scaledW: Double, scaledH: Double
    ) -> some View {
        let spacing = viewModel.gridSpacing
        Path { p in
            var x = spacing
            while x < canvasW {
                let px = originX + x * scaleX
                p.move(to: CGPoint(x: px, y: originY))
                p.addLine(to: CGPoint(x: px, y: originY + scaledH))
                x += spacing
            }
            var y = spacing
            while y < canvasH {
                let py = originY + y * scaleY
                p.move(to: CGPoint(x: originX, y: py))
                p.addLine(to: CGPoint(x: originX + scaledW, y: py))
                y += spacing
            }
        }
        .stroke(viewModel.chartBackgroundTheme == .white ? Color.black.opacity(0.15) : Color.white.opacity(0.1), lineWidth: 0.5)
    }

    private var previewGestures: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    zoomScale = min(max(value, 0.1), 10.0)
                },
            DragGesture()
                .onChanged { value in
                    panOffset = value.translation
                }
        )
    }
}

// MARK: - SVG Web View (NSViewRepresentable)

private struct SiemensStarShape: View {
    let theme: ChartBackgroundTheme

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let rx = geo.size.width / 2
            let ry = geo.size.height / 2
            ZStack {
                ForEach(0..<32, id: \.self) { idx in
                    Path { path in
                        let start = Double(idx) * (Double.pi / 16.0)
                        let end = start + (Double.pi / 16.0)
                        path.move(to: CGPoint(x: cx, y: cy))
                        path.addLine(to: CGPoint(x: cx + CGFloat(cos(start)) * rx, y: cy + CGFloat(sin(start)) * ry))
                        path.addLine(to: CGPoint(x: cx + CGFloat(cos(end)) * rx, y: cy + CGFloat(sin(end)) * ry))
                        path.closeSubpath()
                    }
                    .fill(idx % 2 == 0 ? Color.black : Color.white.opacity(theme == .white ? 1.0 : 0.06))
                }
            }
        }
    }
}

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
