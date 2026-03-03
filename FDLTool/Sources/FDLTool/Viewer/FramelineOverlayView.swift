import SwiftUI

/// Multi-layer geometry overlay on a reference image.
/// Renders canvas boundary, effective area, protection, framing decisions,
/// dimension labels, anchor indicators, and optional grid.
struct FramelineOverlayView: View {
    let image: NSImage
    let document: FDLDocument?
    let computedGeometry: ComputedGeometry?

    var showCanvasLayer: Bool = true
    var showEffectiveLayer: Bool = true
    var showProtectionLayer: Bool = true
    var showFramingLayer: Bool = true
    var showDimensionLabels: Bool = true
    var showAnchorPoints: Bool = false
    var showGridOverlay: Bool = false
    var gridSpacing: Double = 500
    var showLabels: Bool = true
    var overlayOpacity: Double = 1.0

    private let framingColors: [Color] = [
        .red, .blue, .green, .purple, .cyan, .pink, .mint, .indigo,
    ]

    var body: some View {
        GeometryReader { geo in
            let imageSize = image.size
            guard imageSize.width > 0 && imageSize.height > 0 else {
                return AnyView(Text("Invalid image").foregroundStyle(.secondary))
            }

            let scale = min(geo.size.width / imageSize.width, geo.size.height / imageSize.height)
            let scaledW = imageSize.width * scale
            let scaledH = imageSize.height * scale
            let originX = (geo.size.width - scaledW) / 2
            let originY = (geo.size.height - scaledH) / 2

            return AnyView(
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: scaledW, height: scaledH)
                        .offset(x: originX, y: originY)

                    if let geometry = computedGeometry {
                        computedOverlay(
                            geometry: geometry,
                            imageWidth: imageSize.width,
                            imageHeight: imageSize.height,
                            scale: scale,
                            originX: originX,
                            originY: originY
                        )
                    } else if let doc = document {
                        fallbackOverlay(
                            document: doc,
                            imageWidth: imageSize.width,
                            imageHeight: imageSize.height,
                            scale: scale,
                            originX: originX,
                            originY: originY
                        )
                    }

                    infoBadge(imageSize: imageSize, originX: originX, originY: originY, scaledH: scaledH)
                }
            )
        }
    }

    // MARK: - Computed Geometry Overlay (uses Python-computed rects)

    @ViewBuilder
    private func computedOverlay(
        geometry: ComputedGeometry,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        scale: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> some View {
        ForEach(Array(geometry.contexts.enumerated()), id: \.offset) { _, ctx in
            ForEach(Array(ctx.canvases.enumerated()), id: \.offset) { _, canvas in
                let cw = CGFloat(canvas.canvasRect.width)
                let ch = CGFloat(canvas.canvasRect.height)
                guard cw > 0 && ch > 0 else { return AnyView(EmptyView()) }

                let sx = imageWidth / cw
                let sy = imageHeight / ch

                return AnyView(
                    canvasOverlayLayers(
                        canvas: canvas,
                        scaleX: sx,
                        scaleY: sy,
                        viewScale: scale,
                        originX: originX,
                        originY: originY
                    )
                )
            }
        }
    }

    @ViewBuilder
    private func canvasOverlayLayers(
        canvas: ComputedCanvas,
        scaleX: CGFloat,
        scaleY: CGFloat,
        viewScale: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> some View {
        let cr = canvas.canvasRect

        // Grid layer
        if showGridOverlay && gridSpacing > 0 {
            gridLayer(
                canvasWidth: cr.width,
                canvasHeight: cr.height,
                scaleX: scaleX,
                scaleY: scaleY,
                viewScale: viewScale,
                originX: originX,
                originY: originY
            )
        }

        // Canvas boundary
        if showCanvasLayer {
            rectOverlay(
                rect: cr,
                scaleX: scaleX, scaleY: scaleY,
                viewScale: viewScale,
                originX: originX, originY: originY,
                color: .gray.opacity(overlayOpacity),
                lineWidth: 1,
                dashed: false
            )
            if showDimensionLabels {
                dimensionLabel(
                    text: "\(Int(cr.width))\u{00D7}\(Int(cr.height))",
                    rect: cr,
                    scaleX: scaleX, scaleY: scaleY,
                    viewScale: viewScale,
                    originX: originX, originY: originY,
                    color: .gray,
                    position: .topRight
                )
            }
        }

        // Effective area
        if showEffectiveLayer, let eff = canvas.effectiveRect {
            rectOverlay(
                rect: eff,
                scaleX: scaleX, scaleY: scaleY,
                viewScale: viewScale,
                originX: originX, originY: originY,
                color: Color.teal.opacity(overlayOpacity),
                lineWidth: 1.5,
                dashed: false
            )
            if showDimensionLabels {
                dimensionLabel(
                    text: "Eff \(Int(eff.width))\u{00D7}\(Int(eff.height))",
                    rect: eff,
                    scaleX: scaleX, scaleY: scaleY,
                    viewScale: viewScale,
                    originX: originX, originY: originY,
                    color: .teal,
                    position: .bottomLeft
                )
            }
        }

        // Framing decisions
        if showFramingLayer || showProtectionLayer {
            ForEach(Array(canvas.framingDecisions.enumerated()), id: \.offset) { index, fd in
                let color = framingColors[index % framingColors.count]

                // Protection (behind framing)
                if showProtectionLayer, let prot = fd.protectionRect {
                    rectOverlay(
                        rect: prot,
                        scaleX: scaleX, scaleY: scaleY,
                        viewScale: viewScale,
                        originX: originX, originY: originY,
                        color: Color.orange.opacity(overlayOpacity * 0.8),
                        lineWidth: 1,
                        dashed: true
                    )
                }

                // Framing rect
                if showFramingLayer {
                    let fr = fd.framingRect
                    rectOverlay(
                        rect: fr,
                        scaleX: scaleX, scaleY: scaleY,
                        viewScale: viewScale,
                        originX: originX, originY: originY,
                        color: color.opacity(overlayOpacity),
                        lineWidth: 2,
                        dashed: false
                    )

                    // Crosshair at center
                    crosshair(
                        rect: fr,
                        scaleX: scaleX, scaleY: scaleY,
                        viewScale: viewScale,
                        originX: originX, originY: originY,
                        color: color.opacity(overlayOpacity * 0.6)
                    )

                    // Anchor indicator
                    if showAnchorPoints, let anchor = fd.anchorPoint {
                        anchorMarker(
                            x: anchor.x, y: anchor.y,
                            scaleX: scaleX, scaleY: scaleY,
                            viewScale: viewScale,
                            originX: originX, originY: originY,
                            color: color.opacity(overlayOpacity)
                        )
                    }

                    // Label
                    if showLabels && !fd.label.isEmpty {
                        let fx = originX + CGFloat(fr.x * scaleX) * viewScale
                        let fy = originY + CGFloat(fr.y * scaleY) * viewScale
                        let fw = CGFloat(fr.width * scaleX) * viewScale
                        Text(fd.label)
                            .font(.system(size: max(9, min(12, fw * 0.03))))
                            .foregroundStyle(color.opacity(overlayOpacity))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 2))
                            .offset(x: fx + 4, y: fy + 2)
                    }

                    // Dimension label
                    if showDimensionLabels {
                        dimensionLabel(
                            text: "\(Int(fr.width))\u{00D7}\(Int(fr.height))",
                            rect: fr,
                            scaleX: scaleX, scaleY: scaleY,
                            viewScale: viewScale,
                            originX: originX, originY: originY,
                            color: color,
                            position: .bottomRight
                        )
                    }
                }
            }
        }
    }

    // MARK: - Drawing Primitives

    @ViewBuilder
    private func rectOverlay(
        rect gr: GeometryRect,
        scaleX: CGFloat, scaleY: CGFloat,
        viewScale: CGFloat,
        originX: CGFloat, originY: CGFloat,
        color: Color,
        lineWidth: CGFloat,
        dashed: Bool
    ) -> some View {
        let x = originX + CGFloat(gr.x * scaleX) * viewScale
        let y = originY + CGFloat(gr.y * scaleY) * viewScale
        let w = CGFloat(gr.width * scaleX) * viewScale
        let h = CGFloat(gr.height * scaleY) * viewScale

        if dashed {
            Rectangle()
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: [6, 4]))
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
    private func crosshair(
        rect gr: GeometryRect,
        scaleX: CGFloat, scaleY: CGFloat,
        viewScale: CGFloat,
        originX: CGFloat, originY: CGFloat,
        color: Color
    ) -> some View {
        let cx = originX + CGFloat((gr.x + gr.width / 2) * scaleX) * viewScale
        let cy = originY + CGFloat((gr.y + gr.height / 2) * scaleY) * viewScale
        let arm: CGFloat = 8

        Path { path in
            path.move(to: CGPoint(x: cx - arm, y: cy))
            path.addLine(to: CGPoint(x: cx + arm, y: cy))
            path.move(to: CGPoint(x: cx, y: cy - arm))
            path.addLine(to: CGPoint(x: cx, y: cy + arm))
        }
        .stroke(color, lineWidth: 1)
    }

    @ViewBuilder
    private func anchorMarker(
        x: Double, y: Double,
        scaleX: CGFloat, scaleY: CGFloat,
        viewScale: CGFloat,
        originX: CGFloat, originY: CGFloat,
        color: Color
    ) -> some View {
        let px = originX + CGFloat(x * scaleX) * viewScale
        let py = originY + CGFloat(y * scaleY) * viewScale

        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .offset(x: px - 3, y: py - 3)
    }

    private enum LabelPosition { case topRight, bottomLeft, bottomRight }

    private func labelOffset(
        rect gr: GeometryRect,
        scaleX: CGFloat, scaleY: CGFloat,
        viewScale: CGFloat,
        originX: CGFloat, originY: CGFloat,
        position: LabelPosition
    ) -> CGPoint {
        let rx = originX + CGFloat(gr.x * scaleX) * viewScale
        let ry = originY + CGFloat(gr.y * scaleY) * viewScale
        let rw = CGFloat(gr.width * scaleX) * viewScale
        let rh = CGFloat(gr.height * scaleY) * viewScale

        switch position {
        case .topRight:
            return CGPoint(x: rx + rw - 4, y: ry + 2)
        case .bottomLeft:
            return CGPoint(x: rx + 4, y: ry + rh - 16)
        case .bottomRight:
            return CGPoint(x: rx + rw - 4, y: ry + rh - 16)
        }
    }

    @ViewBuilder
    private func dimensionLabel(
        text: String,
        rect gr: GeometryRect,
        scaleX: CGFloat, scaleY: CGFloat,
        viewScale: CGFloat,
        originX: CGFloat, originY: CGFloat,
        color: Color,
        position: LabelPosition
    ) -> some View {
        let offset = labelOffset(
            rect: gr, scaleX: scaleX, scaleY: scaleY,
            viewScale: viewScale, originX: originX, originY: originY,
            position: position
        )

        Text(text)
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(color.opacity(0.8))
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 2))
            .offset(x: offset.x, y: offset.y)
    }

    @ViewBuilder
    private func gridLayer(
        canvasWidth: Double,
        canvasHeight: Double,
        scaleX: CGFloat,
        scaleY: CGFloat,
        viewScale: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> some View {
        let color = Color.white.opacity(0.15)

        Path { path in
            var x = gridSpacing
            while x < canvasWidth {
                let px = originX + CGFloat(x * scaleX) * viewScale
                path.move(to: CGPoint(x: px, y: originY))
                path.addLine(to: CGPoint(x: px, y: originY + CGFloat(canvasHeight * scaleY) * viewScale))
                x += gridSpacing
            }

            var y = gridSpacing
            while y < canvasHeight {
                let py = originY + CGFloat(y * scaleY) * viewScale
                path.move(to: CGPoint(x: originX, y: py))
                path.addLine(to: CGPoint(x: originX + CGFloat(canvasWidth * scaleX) * viewScale, y: py))
                y += gridSpacing
            }
        }
        .stroke(color, lineWidth: 0.5)
    }

    // MARK: - Fallback (no computed geometry, use document directly)

    @ViewBuilder
    private func fallbackOverlay(
        document: FDLDocument,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        scale: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> some View {
        let allData = extractFramelines(from: document, imageWidth: imageWidth, imageHeight: imageHeight)

        ForEach(Array(allData.enumerated()), id: \.offset) { index, fl in
            let color = framingColors[index % framingColors.count].opacity(overlayOpacity)
            let rect = fl.rect
            let x = originX + rect.origin.x * scale
            let y = originY + rect.origin.y * scale
            let w = rect.width * scale
            let h = rect.height * scale

            if showFramingLayer {
                Rectangle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: w, height: h)
                    .offset(x: x, y: y)

                if showLabels && !fl.label.isEmpty {
                    Text(fl.label)
                        .font(.system(size: max(9, min(12, w * 0.03))))
                        .foregroundStyle(color)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 2))
                        .offset(x: x + 4, y: y + 2)
                }
            }
        }
    }

    private func extractFramelines(
        from document: FDLDocument,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [FallbackFramelineData] {
        var result: [FallbackFramelineData] = []
        for context in document.contexts {
            for canvas in context.canvases {
                let cw = CGFloat(canvas.dimensions.width)
                let ch = CGFloat(canvas.dimensions.height)
                guard cw > 0 && ch > 0 else { continue }
                let sx = imageWidth / cw
                let sy = imageHeight / ch

                for fd in canvas.framingDecisions {
                    let fw = CGFloat(fd.dimensions.width)
                    let fh = CGFloat(fd.dimensions.height)
                    let ax = fd.anchorPoint.map { CGFloat($0.x) } ?? (cw - fw) / 2
                    let ay = fd.anchorPoint.map { CGFloat($0.y) } ?? (ch - fh) / 2

                    result.append(FallbackFramelineData(
                        label: fd.label ?? "",
                        rect: CGRect(x: ax * sx, y: ay * sy, width: fw * sx, height: fh * sy)
                    ))
                }
            }
        }
        return result
    }

    // MARK: - Info Badge

    @ViewBuilder
    private func infoBadge(imageSize: CGSize, originX: CGFloat, originY: CGFloat, scaledH: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(Int(imageSize.width)) \u{00D7} \(Int(imageSize.height))")
                .font(.system(size: 10, design: .monospaced))
            if let doc = document {
                let fdCount = doc.contexts.flatMap(\.canvases).flatMap(\.framingDecisions).count
                Text(verbatim: "\(fdCount) frameline\(fdCount == 1 ? "" : "s")")
                    .font(.system(size: 9))
            }
        }
        .foregroundStyle(.white)
        .padding(4)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
        .offset(x: originX + 4, y: originY + scaledH - 36)
    }
}

private struct FallbackFramelineData {
    let label: String
    let rect: CGRect
}

// MARK: - Overlay Image View (from Python-generated base64 PNG)

struct OverlayImageView: View {
    let base64PNG: String

    var body: some View {
        if let data = Data(base64Encoded: base64PNG),
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            VStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Failed to decode overlay image")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
