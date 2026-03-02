import SwiftUI
import UniformTypeIdentifiers

struct ViewerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ViewerViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if viewModel.loadedDocument != nil {
                documentView
            } else {
                emptyState
            }
        }
        .navigationTitle("FDL Viewer")
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("FDL Viewer & Validator")
                .font(.title2)

            Spacer()

            if viewModel.loadedDocument != nil {
                // Reference image controls
                if viewModel.referenceImage != nil {
                    HStack(spacing: 6) {
                        Toggle("Labels", isOn: $viewModel.showLabels)
                            .toggleStyle(.checkbox)
                            .font(.caption)

                        Slider(value: $viewModel.overlayOpacity, in: 0.2...1.0)
                            .frame(width: 60)

                        Button("Clear Image") {
                            viewModel.clearReferenceImage()
                        }
                        .font(.caption)
                    }

                    Divider()
                        .frame(height: 20)
                }

                Button(action: { viewModel.openReferenceImage() }) {
                    Label("Reference Image", systemImage: "photo")
                }

                if viewModel.referenceImage != nil {
                    Button(action: { viewModel.exportOverlay(pythonBridge: appState.pythonBridge) }) {
                        Label("Export Overlay", systemImage: "square.and.arrow.up")
                    }
                }

                Divider()
                    .frame(height: 20)

                Button("Close") {
                    viewModel.closeDocument()
                }
            }

            Button("Open FDL...") {
                viewModel.openFile(pythonBridge: appState.pythonBridge)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Document View (3 panes)

    @ViewBuilder
    private var documentView: some View {
        HSplitView {
            // Left: FDL tree
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let fileName = viewModel.loadedFileName {
                        Label(fileName, systemImage: "doc.text")
                            .font(.headline)
                    }

                    if let doc = viewModel.loadedDocument {
                        FDLTreeView(document: doc)
                    }
                }
                .padding()
            }
            .frame(minWidth: 280, idealWidth: 350)

            // Center: Image overlay or placeholder
            centerPane
                .frame(minWidth: 300, idealWidth: 450)

            // Right: Validation + raw JSON
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result = viewModel.validationResult {
                        ValidationReportView(result: result)
                    }

                    documentSummary

                    if let raw = viewModel.rawJSON {
                        GroupBox("Raw JSON") {
                            ScrollView(.horizontal) {
                                Text(raw)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 300)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 260, idealWidth: 300)
        }
    }

    // MARK: - Center Pane (Image or Placeholder)

    @ViewBuilder
    private var centerPane: some View {
        if let image = viewModel.referenceImage {
            VStack(spacing: 0) {
                // Overlay mode toggle
                HStack {
                    Picker("Renderer", selection: $viewModel.useNativeOverlay) {
                        Text("Native").tag(true)
                        Text("Python").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)

                    if !viewModel.useNativeOverlay && viewModel.overlayPNGBase64 == nil {
                        Button("Generate") {
                            viewModel.generatePythonOverlay(pythonBridge: appState.pythonBridge)
                        }
                        .disabled(viewModel.isGeneratingOverlay)

                        if viewModel.isGeneratingOverlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                Divider()

                // The overlay view
                if viewModel.useNativeOverlay {
                    FramelineOverlayView(
                        image: image,
                        document: viewModel.loadedDocument,
                        showLabels: viewModel.showLabels,
                        overlayOpacity: viewModel.overlayOpacity
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else if let b64 = viewModel.overlayPNGBase64 {
                    OverlayImageView(base64PNG: b64)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Click \"Generate\" to create Python overlay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.9))
                }
            }
        } else {
            // No image loaded — show drop zone
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Load a reference image to see frameline overlays")
                    .foregroundStyle(.secondary)
                Text("Use the \"Reference Image\" button above, or drag and drop an image here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Button("Load Image...") {
                    viewModel.openReferenceImage()
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                handleImageDrop(providers)
                return true
            }
        }
    }

    // MARK: - Document Summary

    @ViewBuilder
    private var documentSummary: some View {
        if let doc = viewModel.loadedDocument {
            GroupBox("Summary") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow {
                        Text("UUID")
                            .foregroundStyle(.secondary)
                        Text(doc.header.uuid)
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text("Version")
                            .foregroundStyle(.secondary)
                        Text(doc.header.version)
                    }
                    if let creator = doc.header.fdlCreator {
                        GridRow {
                            Text("Creator")
                                .foregroundStyle(.secondary)
                            Text(creator)
                        }
                    }
                    GridRow {
                        Text("Contexts")
                            .foregroundStyle(.secondary)
                        Text("\(doc.contexts.count)")
                    }
                    GridRow {
                        Text("Canvases")
                            .foregroundStyle(.secondary)
                        Text("\(doc.contexts.flatMap(\.canvases).count)")
                    }
                    GridRow {
                        Text("Framing Decisions")
                            .foregroundStyle(.secondary)
                        Text("\(doc.contexts.flatMap(\.canvases).flatMap(\.framingDecisions).count)")
                    }
                }
                .font(.caption)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open an FDL file to view and validate")
                .foregroundStyle(.secondary)
            Text("Drag and drop a .fdl.json file, or use the Open button above.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFDLDrop(providers)
            return true
        }
    }

    // MARK: - Drop Handlers

    private func handleFDLDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    Task { @MainActor in
                        viewModel.loadFromURL(url, pythonBridge: appState.pythonBridge)
                    }
                }
            }
        }
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url") { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    Task { @MainActor in
                        viewModel.loadReferenceImage(from: url)
                    }
                }
            }
        }
    }
}
