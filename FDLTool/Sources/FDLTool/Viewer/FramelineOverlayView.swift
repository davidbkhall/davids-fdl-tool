import SwiftUI

/// Displays a reference image with FDL frameline rectangles overlaid.
/// Uses native SwiftUI Canvas rendering for interactive, real-time display.
struct FramelineOverlayView: View {
    let image: NSImage
    let document: FDLDocument?
    var showLabels: Bool = true
    var overlayOpacity: Double = 1.0

    private let framlineColors: [Color] = [
        .red, .blue, .green, .orange, .purple, .yellow, .cyan, .pink,
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
                    // Reference image
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: scaledW, height: scaledH)
                        .offset(x: originX, y: originY)

                    // Frameline overlays
                    if let doc = document {
                        framelinesOverlay(
                            document: doc,
                            imageWidth: imageSize.width,
                            imageHeight: imageSize.height,
                            scale: scale,
                            originX: originX,
                            originY: originY
                        )
                    }

                    // Image info badge
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(imageSize.width)) \u{00D7} \(Int(imageSize.height))")
                            .font(.system(size: 10, design: .monospaced))
                        if let doc = document {
                            let fdCount = doc.contexts.flatMap(\.canvases).flatMap(\.framingDecisions).count
                            Text("\(fdCount) frameline\(fdCount == 1 ? "" : "s")")
                                .font(.system(size: 9))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    .offset(x: originX + 4, y: originY + scaledH - 36)
                }
            )
        }
    }

    @ViewBuilder
    private func framelinesOverlay(
        document: FDLDocument,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        scale: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> some View {
        let allFramelineData = extractFramelines(from: document, imageWidth: imageWidth, imageHeight: imageHeight)

        ForEach(Array(allFramelineData.enumerated()), id: \.offset) { index, fl in
            let color = framlineColors[index % framlineColors.count].opacity(overlayOpacity)
            let rect = fl.rect
            let x = originX + rect.origin.x * scale
            let y = originY + rect.origin.y * scale
            let w = rect.width * scale
            let h = rect.height * scale

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

    /// Extract frameline rectangles from the FDL document, mapped to image coordinates.
    private func extractFramelines(
        from document: FDLDocument,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [FramelineData] {
        var result: [FramelineData] = []

        for context in document.contexts {
            for canvas in context.canvases {
                let cw = CGFloat(canvas.dimensions.width)
                let ch = CGFloat(canvas.dimensions.height)
                guard cw > 0 && ch > 0 else { continue }

                let scaleX = imageWidth / cw
                let scaleY = imageHeight / ch

                for fd in canvas.framingDecisions {
                    let fw = CGFloat(fd.dimensions.width)
                    let fh = CGFloat(fd.dimensions.height)

                    // Use anchor if provided, otherwise center
                    let ax: CGFloat
                    let ay: CGFloat
                    if let anchor = fd.anchor {
                        ax = CGFloat(anchor.x)
                        ay = CGFloat(anchor.y)
                    } else {
                        ax = (cw - fw) / 2
                        ay = (ch - fh) / 2
                    }

                    let rect = CGRect(
                        x: ax * scaleX,
                        y: ay * scaleY,
                        width: fw * scaleX,
                        height: fh * scaleY
                    )

                    result.append(FramelineData(
                        label: fd.label ?? "",
                        intent: fd.framingIntent ?? "",
                        rect: rect,
                        canvasLabel: canvas.label ?? ""
                    ))
                }
            }
        }

        return result
    }
}

/// Data for a single frameline overlay rectangle.
private struct FramelineData {
    let label: String
    let intent: String
    let rect: CGRect
    let canvasLabel: String
}

// MARK: - Overlay Image View (from Python-generated base64 PNG)

/// Displays a base64-encoded PNG overlay image from the Python backend.
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
