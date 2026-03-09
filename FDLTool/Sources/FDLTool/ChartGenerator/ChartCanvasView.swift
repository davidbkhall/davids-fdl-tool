import SwiftUI
import WebKit
import AppKit

/// Live-rendered chart preview. Displays SVG from Python backend or a native SwiftUI approximation.
struct ChartCanvasView: View {
    @ObservedObject var viewModel: ChartGeneratorViewModel
    @Environment(\.displayScale) private var displayScale
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var accumulatedPanOffset: CGSize = .zero
    @State private var pinchStartZoomScale: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Chart Preview")
                    .font(.headline)
                Spacer()

                Button(action: { zoomScale = max(zoomScale / 1.25, 0.05) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Text(verbatim: "\(Int(zoomScale * 100))%")
                    .font(.caption)
                    .frame(width: 36)
                Button(action: { zoomScale = min(zoomScale * 1.25, 48) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Button(action: {
                    zoomScale = 1.0
                    panOffset = .zero
                    accumulatedPanOffset = .zero
                    pinchStartZoomScale = nil
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Fit all")

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
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Canvas area
            if !viewModel.framelines.isEmpty {
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
        .onAppear {
            if viewModel.chartBackgroundTheme != .white {
                viewModel.chartBackgroundTheme = .white
                viewModel.previewSVG = nil
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
    private var nativePreview: some View {
        let cw = viewModel.canvasWidth
        let ch = viewModel.canvasHeight
        guard cw > 0 && ch > 0 else { return AnyView(emptyState) }

        return AnyView(
            GeometryReader { geo in
                let desqueezeFactor = (viewModel.previewDesqueezed && viewModel.anamorphicSqueeze > 1.0) ? viewModel.anamorphicSqueeze : 1.0
                let baseScale = min(geo.size.width / (cw * desqueezeFactor), geo.size.height / ch) * 0.85 * Double(zoomScale)
                let zoomFontFactor = max(0.6, min(8.0, Double(zoomScale)))
                let canvasLabelFont = max(7.0, (9.0 / sqrt(desqueezeFactor)) * zoomFontFactor)
                let detailFont = max(6.5, (8.0 / sqrt(desqueezeFactor)) * zoomFontFactor)
                let scaleX = baseScale * desqueezeFactor
                let scaleY = baseScale
                let scaledW = cw * scaleX
                let scaledH = ch * scaleY
                let originX = (geo.size.width - scaledW) / 2 + Double(panOffset.width)
                let originY = (geo.size.height - scaledH) / 2 + Double(panOffset.height)

                ZStack(alignment: .topLeading) {
                    Color(nsColor: NSColor(red: 0.24, green: 0.24, blue: 0.24, alpha: 1))

                    // Canvas boundary
                    if viewModel.showCanvasLayer {
                        if viewModel.chartBackgroundTheme == .white {
                            Rectangle()
                                .fill(Color(white: 0.68))
                                .frame(width: scaledW, height: scaledH)
                                .offset(x: originX, y: originY)
                        } else {
                            Rectangle()
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                                .frame(width: scaledW, height: scaledH)
                                .offset(x: originX, y: originY)
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

                    // Effective area
                    if viewModel.showEffectiveLayer,
                       let ew = viewModel.canvasEffectiveWidth,
                       let eh = viewModel.canvasEffectiveHeight {
                        let esw = ew * scaleX
                        let esh = eh * scaleY
                        let ex = originX + viewModel.canvasEffectiveAnchorX * scaleX
                        let ey = originY + viewModel.canvasEffectiveAnchorY * scaleY
                        let effectiveRectRaw = CGRect(x: ex, y: ey, width: esw, height: esh)
                        let effectiveRect = adjustedForInsideStroke(effectiveRectRaw, lineWidth: 1.5)
                        if viewModel.chartBackgroundTheme == .white {
                            Rectangle()
                                .fill(Color(white: 0.78))
                                .frame(width: esw, height: esh)
                                .offset(x: ex, y: ey)
                        } else {
                            Rectangle()
                                .stroke(Color.teal, lineWidth: 1.5)
                                .frame(width: effectiveRect.width, height: effectiveRect.height)
                                .offset(x: effectiveRect.minX, y: effectiveRect.minY)
                        }
                        if viewModel.chartBackgroundTheme == .white && viewModel.showBoundaryArrows {
                            boundaryArrows(for: effectiveRectRaw, color: .teal, insetScale: 0)
                        }

                        if viewModel.showDimensionLabels {
                            Text(verbatim: "Effective: \(Int(ew))\u{00D7}\(Int(eh))")
                                    .font(.system(size: detailFont, design: .monospaced))
                                .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.8) : .white.opacity(0.8))
                                .offset(x: ex + 4, y: ey + esh - 16)
                            Text(verbatim: "Anchor: \(Int(viewModel.canvasEffectiveAnchorX)), \(Int(viewModel.canvasEffectiveAnchorY))")
                                .font(.system(size: detailFont, design: .monospaced))
                                .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.8) : .white.opacity(0.8))
                                .offset(x: ex + 4, y: ey + esh - 30)
                        }
                    }

                    // Framelines (protection + framing)
                    ForEach(Array(viewModel.framelines.enumerated()), id: \.element.id) { idx, fl in
                        let color = Color(hex: fl.color) ?? .gray
                        let isPrimary = !viewModel.declutterMultipleFramelines || viewModel.framelines.count <= 1 || idx == 0
                        let layerOpacity = isPrimary ? 1.0 : 0.52
                        let labelLaneOffset = Double(idx) * 12.0
                        let pos = framelinePosition(fl, canvasW: cw, canvasH: ch, scaleX: scaleX, scaleY: scaleY, originX: originX, originY: originY)

                        if viewModel.showProtectionLayer,
                           let prot = viewModel.effectiveProtection(for: fl) {
                            let psw = prot.width * scaleX
                            let psh = prot.height * scaleY
                            let px = originX + (fl.protectionAnchorX.map { $0 * scaleX } ?? (scaledW - psw) / 2)
                            let py = originY + (fl.protectionAnchorY.map { $0 * scaleY } ?? (scaledH - psh) / 2)
                            let protectionRectRaw = CGRect(x: px, y: py, width: psw, height: psh)
                            let protectionRect = adjustedForInsideStroke(protectionRectRaw, lineWidth: 1)
                            if viewModel.chartBackgroundTheme == .white {
                                Rectangle()
                                    .fill(Color(white: 0.86))
                                    .frame(width: psw, height: psh)
                                    .offset(x: px, y: py)
                                    .opacity(layerOpacity)
                            } else {
                                Rectangle()
                                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                    .frame(width: protectionRect.width, height: protectionRect.height)
                                    .offset(x: protectionRect.minX, y: protectionRect.minY)
                                    .opacity(layerOpacity)
                            }
                            if viewModel.chartBackgroundTheme == .white && viewModel.showBoundaryArrows {
                                boundaryArrows(
                                    for: protectionRectRaw,
                                    color: .orange.opacity(layerOpacity),
                                    insetScale: 0
                                )
                            }

                            if viewModel.showDimensionLabels {
                                let protectionAnchorX = Int(
                                    fl.protectionAnchorX
                                        ?? (viewModel.canvasWidth - prot.width) / 2
                                )
                                let protectionAnchorY = Int(
                                    fl.protectionAnchorY
                                        ?? (viewModel.canvasHeight - prot.height) / 2
                                )
                                let dimText = "Protection: \(Int(prot.width))\u{00D7}\(Int(prot.height))"
                                let protectionAnchorText = "Anchor: \(protectionAnchorX), \(protectionAnchorY)"
                                let protectionFont = fittedProtectionFontSize(
                                    requested: detailFont,
                                    protectionRect: protectionRect,
                                    dimText: dimText,
                                    anchorText: protectionAnchorText
                                )
                                let protectionLabelPlacement = protectionLabelPositions(
                                    protectionRect: protectionRect,
                                    framingRect: pos,
                                    canvasRect: CGRect(x: originX, y: originY, width: scaledW, height: scaledH),
                                    dimText: dimText,
                                    anchorText: protectionAnchorText,
                                    fontSize: protectionFont
                                )
                                Text(verbatim: dimText)
                                    .font(.system(size: protectionFont, design: .monospaced))
                                    .foregroundStyle(
                                        viewModel.chartBackgroundTheme == .white
                                            ? Color.orange.opacity(0.9 * layerOpacity)
                                            : Color.white.opacity(0.8)
                                    )
                                    .rotationEffect(protectionLabelPlacement.dim.rotate ? .degrees(-90) : .zero)
                                    .position(
                                        x: protectionLabelPlacement.dim.rect.midX,
                                        y: protectionLabelPlacement.dim.rect.midY
                                    )
                                Text(verbatim: protectionAnchorText)
                                    .font(.system(size: protectionFont, design: .monospaced))
                                    .foregroundStyle(
                                        viewModel.chartBackgroundTheme == .white
                                            ? Color.orange.opacity(0.9 * layerOpacity)
                                            : Color.white.opacity(0.8)
                                    )
                                    .rotationEffect(protectionLabelPlacement.anchor.rotate ? .degrees(-90) : .zero)
                                    .position(
                                        x: protectionLabelPlacement.anchor.rect.midX,
                                        y: protectionLabelPlacement.anchor.rect.midY
                                    )
                            }
                        }

                        if viewModel.showFramingLayer {
                            let drawRect = adjustedForInsideStroke(pos, lineWidth: 2)
                            if viewModel.chartBackgroundTheme == .white {
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: pos.width, height: pos.height)
                                    .offset(x: pos.minX, y: pos.minY)
                                    .opacity(layerOpacity)
                            } else if fl.style == .corners {
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
                                .stroke(color.opacity(layerOpacity), lineWidth: 2)
                            } else if viewModel.chartBackgroundTheme != .white {
                                Rectangle()
                                    .stroke(color.opacity(layerOpacity), lineWidth: 2)
                                    .frame(width: drawRect.width, height: drawRect.height)
                                    .offset(x: drawRect.minX, y: drawRect.minY)
                            }
                            if viewModel.chartBackgroundTheme == .white && viewModel.showBoundaryArrows {
                                boundaryArrows(
                                    for: pos,
                                    color: color.opacity(layerOpacity),
                                    insetScale: 0
                                )
                            }

                            if viewModel.showLabels && !fl.label.isEmpty {
                                let labelSize = max(8.0, min(38.0, min(pos.width, pos.height) * 0.05))
                                let labelX = min(pos.maxX - 90, max(pos.minX + 6, pos.minX + 8))
                                let labelY = pos.minY + 2 + labelLaneOffset
                                Text(fl.label)
                                    .font(.system(size: labelSize))
                                    .foregroundStyle(color.opacity(layerOpacity))
                                    .offset(x: labelX, y: labelY)
                            }

                            if viewModel.showDimensionLabels {
                                let anchorX = Int(fl.anchorX ?? (fl.hAlign == .left ? 0 : (fl.hAlign == .right ? (viewModel.canvasWidth - fl.width) : (viewModel.canvasWidth - fl.width) / 2)))
                                let anchorY = Int(fl.anchorY ?? (fl.vAlign == .top ? 0 : (fl.vAlign == .bottom ? (viewModel.canvasHeight - fl.height) : (viewModel.canvasHeight - fl.height) / 2)))
                                let dimText = "Framing Decision: \(Int(fl.width))\u{00D7}\(Int(fl.height))"
                                let dimX = pos.minX + 4
                                let dimY = pos.maxY - 14
                                Text(verbatim: dimText)
                                    .font(.system(size: detailFont, design: .monospaced))
                                    .foregroundStyle(
                                        viewModel.chartBackgroundTheme == .white
                                            ? color.opacity(0.95 * layerOpacity)
                                            : Color.white.opacity(0.85)
                                    )
                                    .offset(
                                        x: max(originX + 4, min(originX + scaledW - 156, dimX)),
                                        y: max(originY + 4, min(originY + scaledH - 16, dimY + labelLaneOffset))
                                    )
                                    .help(dimText)
                                Text(verbatim: "Anchor: \(anchorX), \(anchorY)")
                                    .font(.system(size: detailFont, design: .monospaced))
                                    .foregroundStyle(
                                        viewModel.chartBackgroundTheme == .white
                                            ? color.opacity(0.95 * layerOpacity)
                                            : Color.white.opacity(0.85)
                                    )
                                    .offset(
                                        x: max(originX + 2, min(originX + scaledW - 126, pos.maxX - 126 - labelLaneOffset)),
                                        y: max(originY + 2, min(originY + scaledH - 16, pos.minY + 2 + labelLaneOffset))
                                    )
                            }
                        }
                    }

                    if viewModel.showSiemensStars {
                        let starRects = siemensStarRects(
                            originX: originX,
                            originY: originY,
                            canvasW: cw,
                            canvasH: ch,
                            scaleX: scaleX,
                            scaleY: scaleY
                        )
                        ForEach(Array(starRects.enumerated()), id: \.offset) { _, rect in
                            SiemensStarShape(theme: viewModel.chartBackgroundTheme)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }

                    // Title
                    if !viewModel.chartTitle.isEmpty {
                        Text(viewModel.chartTitle)
                            .font(.caption)
                            .foregroundStyle(
                                viewModel.chartBackgroundTheme == .white
                                    ? Color.black.opacity(0.8)
                                    : Color.white
                            )
                            .frame(maxWidth: .infinity)
                            .offset(y: 8)
                    }

                    // Metadata / burn-ins
                    if viewModel.metadataBurnInEnabled {
                        let zoomMetaFactor = max(0.6, min(8.0, Double(zoomScale)))
                        let metadataFont = max(
                            6.0,
                            viewModel.metadataFontSize * zoomMetaFactor * (viewModel.showLogoOverlay ? 0.88 : 1.0)
                        )
                        let metadataAutoYOffset = viewModel.showLogoOverlay
                            ? max(18.0, 28.0 * viewModel.logoScale)
                            : 0.0
                        let framingSummary = viewModel.framelines.first.map { "\(Int($0.width))x\(Int($0.height))" } ?? "N/A"
                        let aspectSummary = viewModel.framelines.first.map { $0.height > 0 ? String(format: "%.2f:1", $0.width / $0.height) : "N/A" } ?? "N/A"
                        let cameraModel = viewModel.selectedCamera.map { "\($0.manufacturer) \($0.model)" } ?? "Custom Canvas"
                        let recordingMode = viewModel.selectedRecordingMode?.name ?? "Custom Mode"
                        VStack(alignment: .center, spacing: 2) {
                            Text(viewModel.metadataShowName.isEmpty ? viewModel.chartTitle : viewModel.metadataShowName).font(.system(size: metadataFont))
                            if !viewModel.burnInDirector.isEmpty { Text("Dir: \(viewModel.burnInDirector)").font(.system(size: metadataFont)) }
                            Text("DP: \(viewModel.metadataDOP.isEmpty ? "—" : viewModel.metadataDOP)").font(.system(size: metadataFont))
                            Text("Camera: \(cameraModel)").font(.system(size: metadataFont))
                            Text("Mode: \(recordingMode)").font(.system(size: metadataFont))
                            Text("Framing Decision: \(framingSummary)").font(.system(size: metadataFont))
                            Text("Aspect Ratio: \(aspectSummary)").font(.system(size: metadataFont))
                            if !viewModel.burnInSampleText1.isEmpty { Text(viewModel.burnInSampleText1).font(.system(size: metadataFont)) }
                            if !viewModel.burnInSampleText2.isEmpty { Text(viewModel.burnInSampleText2).font(.system(size: metadataFont)) }
                        }
                        .multilineTextAlignment(.center)
                        .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.75) : .white.opacity(0.7))
                        .frame(width: scaledW, height: scaledH, alignment: .center)
                        .offset(
                            x: originX + viewModel.metadataOffsetX,
                            y: originY + viewModel.metadataOffsetY + metadataAutoYOffset
                        )
                    }

                    if viewModel.showCenterMarker {
                        let cx = originX + scaledW / 2
                        let cy = originY + scaledH / 2
                        let markerLen = 12.0 * max(0.6, min(8.0, Double(zoomScale)))
                        let markerWidth = max(1.0, 1.0 * max(0.6, min(8.0, Double(zoomScale))))
                        Path { p in
                            p.move(to: CGPoint(x: cx - markerLen, y: cy))
                            p.addLine(to: CGPoint(x: cx + markerLen, y: cy))
                            p.move(to: CGPoint(x: cx, y: cy - markerLen))
                            p.addLine(to: CGPoint(x: cx, y: cy + markerLen))
                        }
                        .stroke(
                            viewModel.chartBackgroundTheme == .white
                                ? Color.black.opacity(0.7)
                                : Color.white.opacity(0.8),
                            lineWidth: markerWidth
                        )
                    }

                    if viewModel.showLogoOverlay {
                        let centerX = originX + scaledW / 2
                        let centerY = originY + scaledH / 2
                        let squeeze = max(1.0, viewModel.anamorphicSqueeze)
                        let previewFactor = (viewModel.previewDesqueezed && squeeze > 1.0) ? squeeze : 1.0
                        let logoScaleX = previewFactor / squeeze
                        Group {
                            if let data = viewModel.logoImageData,
                               let nsImage = NSImage(data: data) {
                                let zoomLogoFactor = max(0.6, min(8.0, Double(zoomScale)))
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(
                                        width: 80 * viewModel.logoScale * zoomLogoFactor,
                                        height: 30 * viewModel.logoScale * zoomLogoFactor
                                    )
                            } else if !viewModel.logoText.isEmpty {
                                let zoomLogoFactor = max(0.6, min(8.0, Double(zoomScale)))
                                Text(viewModel.logoText)
                                    .font(.system(size: 10 * viewModel.logoScale * zoomLogoFactor))
                                    .foregroundStyle(viewModel.chartBackgroundTheme == .white ? .black.opacity(0.75) : .white.opacity(0.7))
                            }
                        }
                        .scaleEffect(x: logoScaleX, y: 1.0, anchor: .center)
                        .position(x: centerX + viewModel.logoOffsetX, y: centerY + viewModel.logoOffsetY)
                    }

                    // Canvas dimension label — drawn last so it's never
                    // covered by frameline fills, regardless of canvas width.
                    // Positioned at the bottom edge, right-aligned, horizontal.
                    if viewModel.showCanvasLayer && viewModel.showDimensionLabels {
                        let labelText = "Canvas: \(Int(ch))\u{00D7}\(Int(cw))"
                        Text(verbatim: labelText)
                            .font(.system(size: canvasLabelFont, design: .monospaced))
                            .foregroundStyle(
                                viewModel.chartBackgroundTheme == .white
                                    ? Color(white: 0.15).opacity(0.75)
                                    : Color.white.opacity(0.65)
                            )
                            .lineLimit(1)
                            .padding(.trailing, 5)
                            .frame(width: scaledW, alignment: .trailing)
                            .offset(x: originX, y: originY + scaledH - canvasLabelFont * 1.5)
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
        // Keep stars proportional to current visible chart geometry.
        let base = max(6.0, min(68.0, min(target.width, target.height) * 0.125))
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
        let insetX = (w / 2) + max(4.0, target.width * 0.12)
        let insetY = (h / 2) + max(4.0, target.height * 0.12)
        return [
            CGRect(x: target.minX + insetX - w / 2, y: target.minY + insetY - h / 2, width: w, height: h),
            CGRect(x: target.maxX - insetX - w / 2, y: target.minY + insetY - h / 2, width: w, height: h),
            CGRect(x: target.minX + insetX - w / 2, y: target.maxY - insetY - h / 2, width: w, height: h),
            CGRect(x: target.maxX - insetX - w / 2, y: target.maxY - insetY - h / 2, width: w, height: h),
        ]
    }

    private func adjustedForInsideStroke(_ rect: CGRect, lineWidth: Double) -> CGRect {
        let half = lineWidth / 2.0
        return rect.insetBy(dx: half, dy: half)
    }

    @ViewBuilder
    private func boundaryArrows(
        for rect: CGRect,
        color: Color,
        insetScale: Int
    ) -> some View {
        let size = max(0.72, min(1.5, viewModel.boundaryArrowScale))
        let zoomFactor = max(0.6, min(8.0, Double(zoomScale)))
        let arrow = 16.0 * size * zoomFactor
        let halfBase = 9.0 * size * zoomFactor
        let laneInset = Double(insetScale) * max(2.0, 2.0 * size)
        let minX = snap(rect.minX)
        let maxX = snap(rect.maxX)
        let minY = snap(rect.minY)
        let maxY = snap(rect.maxY)
        let midX = snap(rect.midX)
        let midY = snap(rect.midY)
        // Primary lane (insetScale = 0) has tips exactly on edge pixels.
        let topTip = CGPoint(x: midX, y: snap(minY + laneInset))
        let bottomTip = CGPoint(x: midX, y: snap(maxY - laneInset))
        let leftTip = CGPoint(x: snap(minX + laneInset), y: midY)
        let rightTip = CGPoint(x: snap(maxX - laneInset), y: midY)
        Path { p in
            // Top triangle: tip hits exact edge; triangle body stays inside rect.
            p.move(to: topTip)
            p.addLine(to: CGPoint(x: snap(topTip.x - halfBase), y: snap(topTip.y + arrow)))
            p.addLine(to: CGPoint(x: snap(topTip.x + halfBase), y: snap(topTip.y + arrow)))
            p.closeSubpath()

            // Bottom triangle: tip hits exact edge; triangle body stays inside rect.
            p.move(to: bottomTip)
            p.addLine(to: CGPoint(x: snap(bottomTip.x - halfBase), y: snap(bottomTip.y - arrow)))
            p.addLine(to: CGPoint(x: snap(bottomTip.x + halfBase), y: snap(bottomTip.y - arrow)))
            p.closeSubpath()

            // Left triangle: tip hits exact edge; triangle body stays inside rect.
            p.move(to: leftTip)
            p.addLine(to: CGPoint(x: snap(leftTip.x + arrow), y: snap(leftTip.y - halfBase)))
            p.addLine(to: CGPoint(x: snap(leftTip.x + arrow), y: snap(leftTip.y + halfBase)))
            p.closeSubpath()

            // Right triangle: tip hits exact edge; triangle body stays inside rect.
            p.move(to: rightTip)
            p.addLine(to: CGPoint(x: snap(rightTip.x - arrow), y: snap(rightTip.y - halfBase)))
            p.addLine(to: CGPoint(x: snap(rightTip.x - arrow), y: snap(rightTip.y + halfBase)))
            p.closeSubpath()
        }
        .fill(color.opacity(0.95))
    }

    private struct LabelPlacement {
        let origin: CGPoint
        let rect: CGRect
        let rotate: Bool
    }

    private func protectionLabelPositions(
        protectionRect: CGRect,
        framingRect: CGRect,
        canvasRect: CGRect,
        dimText: String,
        anchorText: String,
        fontSize: Double
    ) -> (dim: LabelPlacement, anchor: LabelPlacement) {
        let dim = bestProtectionLabelPlacement(
            text: dimText,
            fontSize: fontSize,
            protectionRect: protectionRect,
            canvasRect: canvasRect,
            avoidRects: [framingRect]
        )
        let anchor = bestProtectionLabelPlacement(
            text: anchorText,
            fontSize: fontSize,
            protectionRect: protectionRect,
            canvasRect: canvasRect,
            avoidRects: [framingRect, dim.rect.insetBy(dx: -2, dy: -2)]
        )
        return (dim: dim, anchor: anchor)
    }

    private func bestProtectionLabelPlacement(
        text: String,
        fontSize: Double,
        protectionRect: CGRect,
        canvasRect: CGRect,
        avoidRects: [CGRect]
    ) -> LabelPlacement {
        let pad = 14.0
        let textSize = measuredTextSize(text: text, fontSize: fontSize)
        let horizontalSize = CGSize(width: textSize.width, height: textSize.height)

        // Keep protection labels on the interior-left side to avoid right-edge clipping
        // in very small protection bands.
        let horizCandidates: [(CGPoint, CGSize, Bool)] = [
            (CGPoint(x: protectionRect.minX + pad, y: protectionRect.minY + pad), horizontalSize, false),
            (CGPoint(x: protectionRect.minX + pad, y: protectionRect.maxY - horizontalSize.height - pad), horizontalSize, false),
        ]
        let all = horizCandidates

        var best: LabelPlacement?
        var bestScore = Double.greatestFiniteMagnitude
        for (origin, size, rotate) in all {
            let rect = CGRect(origin: origin, size: size)
            let inProtection = protectionRect.contains(rect)
            let inCanvas = canvasRect.contains(rect)
            if !inProtection || !inCanvas { continue }

            var penalty = 0.0
            for avoid in avoidRects where rect.intersects(avoid) {
                penalty += 1000
            }
            if rotate { penalty += 12 } // (currently unused; all candidates horizontal)

            if penalty < bestScore {
                bestScore = penalty
                best = LabelPlacement(origin: origin, rect: rect, rotate: rotate)
            }
        }

        if let best {
            return best
        }

        // Last-resort clamp within protection and canvas (still inside protection box).
        let clampedX = max(
            protectionRect.minX + pad,
            min(
                protectionRect.maxX - horizontalSize.width - pad,
                canvasRect.maxX - horizontalSize.width - pad
            )
        )
        let clampedY = max(
            protectionRect.minY + pad,
            min(
                protectionRect.maxY - horizontalSize.height - pad,
                canvasRect.maxY - horizontalSize.height - pad
            )
        )
        let fallbackRect = CGRect(
            x: clampedX,
            y: clampedY,
            width: horizontalSize.width,
            height: horizontalSize.height
        )
        return LabelPlacement(origin: fallbackRect.origin, rect: fallbackRect, rotate: false)
    }

    private func measuredTextSize(text: String, fontSize: Double) -> CGSize {
        let font = NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        // Include safety margin for glyph overhang and antialiasing.
        return CGSize(width: ceil(size.width + 16), height: ceil(size.height + 4))
    }

    private func fittedProtectionFontSize(
        requested: Double,
        protectionRect: CGRect,
        dimText: String,
        anchorText: String
    ) -> Double {
        var font = requested
        for _ in 0..<10 {
            let dimSize = measuredTextSize(text: dimText, fontSize: font)
            let anchorSize = measuredTextSize(text: anchorText, fontSize: font)
            let maxWidth = max(24.0, protectionRect.width - 28.0)
            let totalHeight = dimSize.height + anchorSize.height + 6
            if dimSize.width <= maxWidth && anchorSize.width <= maxWidth && totalHeight <= (protectionRect.height - 8.0) {
                return font
            }
            font *= 0.88
        }
        return max(6.0, font)
    }

    private func snap(_ value: Double) -> Double {
        let scale = max(1.0, displayScale)
        return (value * scale).rounded() / scale
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
        .stroke(
            viewModel.chartBackgroundTheme == .white ? Color.black.opacity(0.15) : Color.white.opacity(0.1),
            lineWidth: max(0.5, 0.5 * max(0.6, min(8.0, Double(zoomScale))))
        )
    }

    private var previewGestures: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if pinchStartZoomScale == nil {
                        pinchStartZoomScale = zoomScale
                    }
                    let start = pinchStartZoomScale ?? zoomScale
                    zoomScale = min(max(start * value, 0.05), 48.0)
                }
                .onEnded { _ in
                    pinchStartZoomScale = nil
                },
            DragGesture()
                .onChanged { value in
                    panOffset = CGSize(
                        width: accumulatedPanOffset.width + value.translation.width,
                        height: accumulatedPanOffset.height + value.translation.height
                    )
                }
                .onEnded { value in
                    accumulatedPanOffset = CGSize(
                        width: accumulatedPanOffset.width + value.translation.width,
                        height: accumulatedPanOffset.height + value.translation.height
                    )
                }
        )
    }
}

// MARK: - SVG Web View (NSViewRepresentable)

struct SiemensStarShape: View {
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
