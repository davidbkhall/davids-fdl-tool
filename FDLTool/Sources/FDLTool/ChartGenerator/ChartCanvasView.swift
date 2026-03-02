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

    /// Native SwiftUI approximation of the framing chart.
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
                    // Background
                    Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))

                    // Canvas outline
                    Rectangle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                        .frame(width: scaledW, height: scaledH)
                        .offset(x: originX, y: originY)

                    // Framelines
                    ForEach(viewModel.framelines) { fl in
                        let fw = fl.width * scale
                        let fh = fl.height * scale
                        let fx = originX + (scaledW - fw) / 2
                        let fy = originY + (scaledH - fh) / 2
                        let color = Color(hex: fl.color) ?? .gray

                        Rectangle()
                            .stroke(color, lineWidth: 2)
                            .frame(width: fw, height: fh)
                            .offset(x: fx, y: fy)

                        if viewModel.showLabels && !fl.label.isEmpty {
                            Text(fl.label)
                                .font(.system(size: 10))
                                .foregroundStyle(color)
                                .offset(x: fx + 4, y: fy + 2)
                        }
                    }

                    // Title
                    if !viewModel.chartTitle.isEmpty {
                        Text(viewModel.chartTitle)
                            .font(.caption)
                            .foregroundStyle(.white)
                            .offset(x: geo.size.width / 2 - 40, y: 8)
                    }

                    // Dimensions label
                    Text("\(Int(cw)) \u{00D7} \(Int(ch))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.gray)
                        .offset(x: originX + scaledW - 80, y: originY + scaledH - 16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        )
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
