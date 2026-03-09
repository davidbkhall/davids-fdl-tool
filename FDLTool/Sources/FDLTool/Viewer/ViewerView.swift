import SwiftUI
import UniformTypeIdentifiers

struct ViewerView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var viewModel: ViewerViewModel
    @State private var showScenarioPackSheet = false
    @State private var showSourceJSON = false
    @State private var showOutputJSON = false

    var body: some View {
        VStack(spacing: 0) {
            viewerToolbar
            Divider()

            HSplitView {
                viewerSidebar
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

                viewerContent
            }
        }
        .navigationTitle("Framing Workspace")
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showScenarioPackSheet) {
            ScenarioPackExportSheet(
                scenarioNames: TemplatePresets.scenarioContexts.map(\.name),
                projects: appState.libraryViewModel.projects,
                onExport: { names, includeZip, projectID in
                    viewModel.exportScenarioPack(
                        presetNames: names,
                        pythonBridge: appState.pythonBridge,
                        defaultCreator: appState.defaultCreator,
                        includeZip: includeZip,
                        projectID: projectID,
                        libraryStore: appState.libraryStore
                    )
                }
            )
        }
        .onChange(of: appState.pendingOpenURL) { _, url in
            guard let url else { return }
            appState.pendingOpenURL = nil
            viewModel.loadFromURL(url, pythonBridge: appState.pythonBridge)
        }
        .onChange(of: appState.pendingFDLDocument?.id) { _, _ in
            guard let doc = appState.pendingFDLDocument else { return }
            let name = appState.pendingFDLFileName ?? "Chart FDL"
            appState.pendingFDLDocument = nil
            appState.pendingFDLFileName = nil
            viewModel.loadDocument(doc, fileName: name)
        }
        .task {
            await viewModel.refreshFramelineInterop(pythonBridge: appState.pythonBridge)
        }
        .onChange(of: appState.pythonBridgeStatus) { _, status in
            guard status == .running else { return }
            Task {
                await viewModel.refreshFramelineInterop(pythonBridge: appState.pythonBridge)
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var viewerToolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $viewModel.activeTab) {
                ForEach(ViewerViewModel.ViewerTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Spacer()

            HStack(spacing: 4) {
                Button(action: { viewModel.zoomOut() }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Text(verbatim: "\(Int(viewModel.zoomScale * 100))%")
                    .font(.caption)
                    .frame(width: 36)
                Button(action: { viewModel.zoomIn() }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Button(action: { viewModel.zoomToFit() }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Fit to view")
            }

            if viewModel.loadedDocument != nil {
                Divider().frame(height: 18)
                Button("Close") { viewModel.closeDocument() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Sidebar (always visible)

    @ViewBuilder
    private var viewerSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        if let fileName = viewModel.loadedFileName {
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(.blue)
                                Text(fileName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                Button(action: { viewModel.closeDocument() }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            if let doc = viewModel.loadedDocument {
                                Divider()
                                sourceDocumentSummary(doc)

                                if let val = viewModel.validationResult {
                                    HStack(spacing: 4) {
                                        Image(systemName: val.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                            .foregroundStyle(val.valid ? .green : .orange)
                                        Text(val.valid ? "Valid" : "\(val.errors.count) issue(s)")
                                            .font(.caption)
                                            .foregroundStyle(val.valid ? .green : .orange)
                                    }
                                }

                                Divider()
                                DisclosureGroup {
                                    FDLTreeView(document: doc)
                                } label: {
                                    Text("Document Structure")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            HStack(spacing: 4) {
                                Button(action: { viewModel.openFile(pythonBridge: appState.pythonBridge) }) {
                                    HStack {
                                        Image(systemName: "doc.text.magnifyingglass")
                                        Text("Open File...")
                                    }
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.bordered)

                                libraryBrowseMenu
                            }

                            Text("Or drag & drop an .fdl / .json file")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Source FDL", systemImage: "doc.text")
                        .font(.headline)
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleFDLDrop(providers)
                    return true
                }

                // Selection pickers (shown when document loaded)
                if viewModel.loadedDocument != nil {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            if viewModel.contextLabels.count > 1 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Context")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Context", selection: Binding(
                                        get: { viewModel.selectedContextIndex },
                                        set: { viewModel.selectContext($0) }
                                    )) {
                                        ForEach(Array(viewModel.contextLabels.enumerated()), id: \.offset) { i, label in
                                            Text(label).tag(i)
                                        }
                                    }
                                    .labelsHidden()
                                }
                            }

                            if viewModel.canvasLabels.count > 1 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Canvas")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Canvas", selection: Binding(
                                        get: { viewModel.selectedCanvasIndex },
                                        set: { viewModel.selectCanvas($0) }
                                    )) {
                                        ForEach(Array(viewModel.canvasLabels.enumerated()), id: \.offset) { i, label in
                                            Text(label).tag(i)
                                        }
                                    }
                                    .labelsHidden()
                                }
                            }

                            if !viewModel.framingLabels.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Framing Decision")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Framing", selection: Binding(
                                        get: { viewModel.selectedFramingIndex ?? -1 },
                                        set: { viewModel.selectedFramingIndex = $0 < 0 ? nil : $0 }
                                    )) {
                                        Text("All").tag(-1)
                                        ForEach(Array(viewModel.framingLabels.enumerated()), id: \.offset) { i, label in
                                            Text(label).tag(i)
                                        }
                                    }
                                    .labelsHidden()
                                }
                            }

                            // Canvas info summary
                            if let canvas = viewModel.selectedCanvas {
                                Divider()
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: "\(Int(canvas.dimensions.width)) \u{00D7} \(Int(canvas.dimensions.height))")
                                        .font(.system(.caption, design: .monospaced))
                                    if let eff = canvas.effectiveDimensions {
                                        Text(verbatim: "Effective: \(Int(eff.width)) \u{00D7} \(Int(eff.height))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let squeeze = canvas.anamorphicSqueeze, squeeze != 1.0 {
                                        Text(verbatim: "Squeeze: \(String(format: "%.2f\u{00D7}", squeeze))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    let fdCount = canvas.framingDecisions.count
                                    Text("\(fdCount) framing decision\(fdCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Label("Framing Decision", systemImage: "viewfinder.rectangular")
                            .font(.headline)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        if viewModel.referenceImage != nil {
                            HStack(spacing: 6) {
                                Image(systemName: "photo.fill")
                                    .foregroundStyle(.green)
                                Text(viewModel.referenceImagePath?.components(separatedBy: "/").last ?? "Loaded")
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Button(action: { viewModel.clearReferenceImage() }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 6) {
                                Text("Opacity")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Slider(value: $viewModel.imageOpacity, in: 0...1.0)
                            }
                        } else {
                            Button(action: { viewModel.openReferenceImage() }) {
                                HStack {
                                    Image(systemName: "photo.on.rectangle.angled")
                                    Text("Load Image...")
                                }
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)

                            Text("Or drag & drop an image here")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Reference Image", systemImage: "photo")
                        .font(.headline)
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleImageDrop(providers)
                    return true
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        if viewModel.templateIsConfigured {
                            templateSummaryView
                        } else {
                            templateEmptyView
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Template", systemImage: "square.resize")
                        .font(.headline)
                }

            }
            .padding(10)
        }
    }

    // MARK: - Content area (tabs)

    @ViewBuilder
    private var viewerContent: some View {
        switch viewModel.activeTab {
        case .source:
            sourceTabContent
        case .output:
            outputTab
        case .comparison:
            comparisonTab
        case .details:
            detailsTab
        }
    }

    // MARK: - Source Tab

    private var hasSourceContent: Bool {
        viewModel.loadedDocument != nil || viewModel.referenceImage != nil
    }

    @ViewBuilder
    private var sourceTabContent: some View {
        if hasSourceContent {
            VStack(spacing: 0) {
                CanvasVisualizationView(viewModel: viewModel)
                    .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
                layerToggleBar
            }
        } else {
            sourceEmptyState
        }
    }

    @ViewBuilder
    private var sourceEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)

            Text("Framing Workspace")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)

            Text(
                "Load a Source FDL or Reference Image from the sidebar\n"
                + "to visualize canvas geometry."
            )
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
    }

    // MARK: - Output Tab

    @ViewBuilder
    private var outputTab: some View {
        if viewModel.outputDocument != nil, viewModel.outputGeometry != nil {
            VStack(spacing: 0) {
                OutputCanvasView(viewModel: viewModel)
                    .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
                layerToggleBar
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "arrow.right.doc.on.clipboard")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("No Output Yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Configure a template in the sidebar and click TRANSFORM to see the output.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
        }
    }

    // MARK: - Comparison Tab

    @ViewBuilder
    private var comparisonTab: some View {
        if viewModel.outputDocument != nil, viewModel.outputGeometry != nil {
            VStack(spacing: 0) {
                HSplitView {
                    VStack(spacing: 0) {
                        Text("SOURCE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                        CanvasVisualizationView(viewModel: viewModel)
                            .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
                    }

                    VStack(spacing: 0) {
                        Text("OUTPUT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                        OutputCanvasView(viewModel: viewModel)
                            .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
                    }
                }
                layerToggleBar
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Comparison View")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Apply a template to compare source and output side-by-side.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
        }
    }

    // MARK: - Details Tab

    @ViewBuilder
    private var detailsTab: some View {
        if let doc = viewModel.loadedDocument {
            VStack(spacing: 0) {
                // Top section: document structure trees
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Document structure panels side by side
                        HStack(alignment: .top, spacing: 12) {
                            // Source Document Structure
                            GroupBox {
                                VStack(alignment: .leading, spacing: 6) {
                                    detailsDocSummary(doc, title: "Source FDL")
                                    Divider()
                                    FDLTreeView(document: doc)
                                }
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } label: {
                                Label("Source Document", systemImage: "doc.text")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.cyan)
                            }

                            // Output Document Structure (if available)
                            if let outDoc = viewModel.outputDocument {
                                GroupBox {
                                    VStack(alignment: .leading, spacing: 6) {
                                        detailsDocSummary(outDoc, title: "Output FDL")

                                        if let templates = outDoc.canvasTemplates, !templates.isEmpty {
                                            Divider()
                                            Text("Applied Template")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.purple)
                                            detailsTemplateSummary
                                        }

                                        Divider()
                                        FDLTreeView(document: outDoc)
                                    }
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                } label: {
                                    Label("Output Document", systemImage: "doc.text.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.yellow)
                                }
                            }
                        }

                        // Template info (if configured)
                        if viewModel.templateIsConfigured {
                            GroupBox {
                                detailsTemplateSummary
                            } label: {
                                Label("Template: \(viewModel.templateConfig.label)", systemImage: "rectangle.on.rectangle.angled")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.purple)
                            }
                        }

                        // Transform result summary
                        if let info = viewModel.transformInfo {
                            GroupBox {
                                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                                    GridRow {
                                        Text("Source Canvas").foregroundStyle(.secondary)
                                        Text(info.sourceCanvas)
                                    }
                                    GridRow {
                                        Text("Source Framing").foregroundStyle(.secondary)
                                        Text(info.sourceFraming)
                                    }
                                    if let outCanvas = info.outputCanvas {
                                        GridRow {
                                            Text("Output Canvas").foregroundStyle(.secondary)
                                            Text(outCanvas)
                                        }
                                    }
                                    if let outFD = info.outputFraming {
                                        GridRow {
                                            Text("Output Framing").foregroundStyle(.secondary)
                                            Text(outFD)
                                        }
                                    }
                                }
                                .font(.caption)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } label: {
                                Label("Transform Result", systemImage: "arrow.right.square")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Converter Availability")
                                    .secondarySectionHeader()

                                HStack(spacing: 8) {
                                    Label(
                                        viewModel.framelineStatus.arriAvailable ? "ARRI Ready" : "ARRI Unavailable",
                                        systemImage: viewModel.framelineStatus.arriAvailable ? "checkmark.circle.fill" : "xmark.circle"
                                    )
                                    .foregroundStyle(viewModel.framelineStatus.arriAvailable ? .green : .orange)
                                    .font(.caption)

                                    Label(
                                        viewModel.framelineStatus.sonyAvailable ? "Sony Ready" : "Sony Unavailable",
                                        systemImage: viewModel.framelineStatus.sonyAvailable ? "checkmark.circle.fill" : "xmark.circle"
                                    )
                                    .foregroundStyle(viewModel.framelineStatus.sonyAvailable ? .green : .orange)
                                    .font(.caption)
                                }

                                Divider()

                                if viewModel.framelineStatus.arriAvailable {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("ARRI XML")
                                            .font(.caption.weight(.semibold))
                                        HStack(spacing: 6) {
                                            Picker("Camera", selection: $viewModel.selectedArriCameraType) {
                                                ForEach(viewModel.arriCameras) { camera in
                                                    Text(camera.cameraType).tag(camera.cameraType)
                                                }
                                            }
                                            .controlSize(.small)
                                            .onChange(of: viewModel.selectedArriCameraType) { _, selected in
                                                viewModel.selectedArriSensorMode = viewModel.arriCameras
                                                    .first(where: { $0.cameraType == selected })?
                                                    .modes.first?.name ?? ""
                                            }

                                            Picker("Mode", selection: $viewModel.selectedArriSensorMode) {
                                                let modes = viewModel.arriCameras
                                                    .first(where: { $0.cameraType == viewModel.selectedArriCameraType })?
                                                    .modes ?? []
                                                ForEach(modes) { mode in
                                                    Text(mode.name).tag(mode.name)
                                                }
                                            }
                                            .controlSize(.small)
                                        }
                                        .font(.caption)

                                        HStack(spacing: 6) {
                                            Button("Export ARRI XML") {
                                                viewModel.exportCurrentFDLToArriXML(pythonBridge: appState.pythonBridge)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .disabled(viewModel.loadedDocument == nil)

                                            Button("Import ARRI XML") {
                                                viewModel.importArriXMLAsSourceFDL(pythonBridge: appState.pythonBridge)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }

                                if viewModel.framelineStatus.sonyAvailable {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Sony XML")
                                            .font(.caption.weight(.semibold))
                                        HStack(spacing: 6) {
                                            Picker("Camera", selection: $viewModel.selectedSonyCameraType) {
                                                ForEach(viewModel.sonyCameras) { camera in
                                                    Text(camera.cameraType).tag(camera.cameraType)
                                                }
                                            }
                                            .controlSize(.small)
                                            .onChange(of: viewModel.selectedSonyCameraType) { _, selected in
                                                viewModel.selectedSonyImagerMode = viewModel.sonyCameras
                                                    .first(where: { $0.cameraType == selected })?
                                                    .modes.first?.name ?? ""
                                            }

                                            Picker("Mode", selection: $viewModel.selectedSonyImagerMode) {
                                                let modes = viewModel.sonyCameras
                                                    .first(where: { $0.cameraType == viewModel.selectedSonyCameraType })?
                                                    .modes ?? []
                                                ForEach(modes) { mode in
                                                    Text(mode.name).tag(mode.name)
                                                }
                                            }
                                            .controlSize(.small)
                                        }
                                        .font(.caption)

                                        HStack(spacing: 6) {
                                            Button("Export Sony XML") {
                                                viewModel.exportCurrentFDLToSonyXML(pythonBridge: appState.pythonBridge)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            .disabled(viewModel.loadedDocument == nil)

                                            Button("Import Sony XML") {
                                                viewModel.importSonyXMLAsSourceFDL(pythonBridge: appState.pythonBridge)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                }

                                if let report = viewModel.framelineReport {
                                    Divider()
                                    FramelineReportCard(
                                        report: report,
                                        onCopy: {
                                            if let data = try? JSONEncoder().encode(report),
                                               let text = String(data: data, encoding: .utf8) {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(text, forType: .string)
                                            }
                                        },
                                        onExport: { viewModel.exportFramelineReportJSON() },
                                        onSave: nil,
                                        saveTitle: "Save"
                                    )

                                    Menu("Save Report to Project") {
                                        ForEach(appState.libraryViewModel.projects) { project in
                                            Button(project.name) {
                                                viewModel.saveFramelineReportToProject(
                                                    projectID: project.id,
                                                    libraryStore: appState.libraryStore
                                                )
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(appState.libraryViewModel.projects.isEmpty)
                                }
                            }
                            .padding(.vertical, 4)
                        } label: {
                            Label("Manufacturer XML Interop", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.mint)
                        }

                        if let result = viewModel.validationResult {
                            ValidationReportView(result: result)
                        }

                        // JSON panels side by side
                        HStack(alignment: .top, spacing: 12) {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let raw = viewModel.rawJSON {
                                        DisclosureGroup(isExpanded: $showSourceJSON) {
                                            ScrollView([.horizontal, .vertical]) {
                                                Text(raw)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .textSelection(.enabled)
                                            }
                                            .frame(maxHeight: 400)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                            Button("Copy") {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(raw, forType: .string)
                                            }
                                            .font(.caption)
                                            .buttonStyle(.bordered)
                                            .denseControl()
                                        } label: {
                                            Text("Show Source JSON (\(raw.count) chars)")
                                                .font(.caption)
                                        }
                                    } else {
                                        Text("No source loaded")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                            } label: {
                                Label("Source JSON", systemImage: "curlybraces")
                                    .font(.caption.weight(.semibold))
                            }

                            GroupBox {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let outJSON = viewModel.outputRawJSON {
                                        DisclosureGroup(isExpanded: $showOutputJSON) {
                                            ScrollView([.horizontal, .vertical]) {
                                                Text(outJSON)
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .textSelection(.enabled)
                                            }
                                            .frame(maxHeight: 400)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                            HStack(spacing: 6) {
                                                Button("Copy") {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(outJSON, forType: .string)
                                                }
                                                .font(.caption)
                                                .buttonStyle(.bordered)
                                                .denseControl()

                                                Button("Export...") {
                                                    let panel = NSSavePanel()
                                                    panel.allowedContentTypes = [.json]
                                                    panel.nameFieldStringValue = "output.fdl.json"
                                                    if panel.runModal() == .OK, let dest = panel.url {
                                                        try? outJSON.write(to: dest, atomically: true, encoding: .utf8)
                                                    }
                                                }
                                                .font(.caption)
                                                .buttonStyle(.bordered)
                                                .denseControl()
                                            }
                                        } label: {
                                            Text("Show Output JSON (\(outJSON.count) chars)")
                                                .font(.caption)
                                        }
                                    } else {
                                        Text("Apply a template to see output")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                            } label: {
                                Label("Output JSON", systemImage: "curlybraces")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Open an FDL to see document details")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    @ViewBuilder
    private func detailsDocSummary(_ doc: FDLDocument, title: String) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
            GridRow {
                Text("UUID").foregroundStyle(.secondary)
                Text(doc.id).textSelection(.enabled)
            }
            GridRow {
                Text("Version").foregroundStyle(.secondary)
                Text(doc.versionString)
            }
            if let creator = doc.fdlCreator {
                GridRow {
                    Text("Creator").foregroundStyle(.secondary)
                    Text(creator)
                }
            }
            GridRow {
                Text("Contexts").foregroundStyle(.secondary)
                Text(verbatim: "\(doc.contexts.count)")
            }
            GridRow {
                Text("Canvases").foregroundStyle(.secondary)
                Text(verbatim: "\(doc.contexts.flatMap(\.canvases).count)")
            }
            GridRow {
                Text("Framing Decisions").foregroundStyle(.secondary)
                Text(verbatim: "\(doc.contexts.flatMap(\.canvases).flatMap(\.framingDecisions).count)")
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var detailsTemplateSummary: some View {
        let tc = viewModel.templateConfig
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Label").foregroundStyle(.secondary)
                Text(tc.label)
            }
            GridRow {
                Text("ID").foregroundStyle(.secondary)
                Text(tc.id).textSelection(.enabled)
            }
            GridRow {
                Text("Target").foregroundStyle(.secondary)
                Text(verbatim: "\(tc.targetWidth) \u{00D7} \(tc.targetHeight)")
            }
            if tc.targetAnamorphicSqueeze != 1.0 {
                GridRow {
                    Text("Target Squeeze").foregroundStyle(.secondary)
                    Text(verbatim: String(format: "%.1fx", tc.targetAnamorphicSqueeze))
                }
            }
            GridRow {
                Text("Fit Source").foregroundStyle(.secondary)
                Text(tc.fitSource)
            }
            GridRow {
                Text("Fit Method").foregroundStyle(.secondary)
                Text(tc.fitMethod)
            }
            GridRow {
                Text("Alignment").foregroundStyle(.secondary)
                Text(verbatim: "\(tc.alignmentHorizontal) / \(tc.alignmentVertical)")
            }
            GridRow {
                Text("Rounding").foregroundStyle(.secondary)
                Text(verbatim: "\(tc.roundMode) to \(tc.roundEven)")
            }
            if let mw = tc.maximumWidth, let mh = tc.maximumHeight {
                GridRow {
                    Text("Maximum").foregroundStyle(.secondary)
                    Text(verbatim: "\(mw) \u{00D7} \(mh)")
                }
                GridRow {
                    Text("Pad to Max").foregroundStyle(.secondary)
                    Text(tc.padToMaximum ? "Yes" : "No")
                }
            }
            if let preserve = tc.preserveFromSourceCanvas {
                GridRow {
                    Text("Preserve").foregroundStyle(.secondary)
                    Text(preserve)
                }
            }
        }
        .font(.caption)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Layer Toggle Bar (bottom of canvas)

    @ViewBuilder
    private var layerToggleBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                layerPill("Canvas", color: ViewerColors.canvas, isOn: $viewModel.showCanvasLayer)
                layerPill("Effective", color: ViewerColors.effective, isOn: $viewModel.showEffectiveLayer)
                layerPill("Framing", color: ViewerColors.framing, isOn: $viewModel.showFramingLayer)
                layerPill("Protection", color: ViewerColors.protection, isOn: $viewModel.showProtectionLayer)
            }

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 8)

            HStack(spacing: 4) {
                iconPill("photo", label: "Reference Image", isOn: $viewModel.showReferenceImage,
                         tint: viewModel.referenceImage != nil ? .white : nil)
            }

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 8)

            HStack(spacing: 4) {
                iconPill("textformat.size", label: "Labels", isOn: $viewModel.showDimensionLabels)
                iconPill("diamond", label: "Anchors", isOn: $viewModel.showAnchorPoints)
                iconPill("plus", label: "Crosshairs", isOn: $viewModel.showCrosshairs)
                iconPill("info.square", label: "HUD", isOn: $viewModel.showHUD)
                gridPill
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private func layerPill(_ label: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isOn.wrappedValue ? color.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isOn.wrappedValue ? color.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .foregroundStyle(isOn.wrappedValue ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
    }

    private func iconPill(_ icon: String, label: String, isOn: Binding<Bool>, tint: Color? = nil) -> some View {
        let activeColor = tint ?? Color.accentColor
        return Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isOn.wrappedValue ? activeColor.opacity(0.2) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isOn.wrappedValue ? activeColor.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .foregroundStyle(isOn.wrappedValue ? .primary : .tertiary)
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private var gridPill: some View {
        Menu {
            Toggle("Show Grid", isOn: $viewModel.showGridOverlay)
            if viewModel.showGridOverlay {
                Divider()
                Picker("Spacing", selection: $viewModel.gridSpacing) {
                    Text("100px").tag(100.0)
                    Text("250px").tag(250.0)
                    Text("500px").tag(500.0)
                }
            }
        } label: {
            Image(systemName: "grid")
                .font(.system(size: 10))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(viewModel.showGridOverlay ? Color.accentColor.opacity(0.2) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(viewModel.showGridOverlay ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .foregroundStyle(viewModel.showGridOverlay ? .primary : .tertiary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Grid")
    }

    // MARK: - Source Document Summary

    @ViewBuilder
    private func sourceDocumentSummary(_ doc: FDLDocument) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let creator = doc.fdlCreator {
                HStack(spacing: 4) {
                    Text("Creator:").foregroundStyle(.secondary)
                    Text(creator)
                }
                .font(.caption2)
            }

            HStack(spacing: 4) {
                Text("Version:").foregroundStyle(.secondary)
                Text(doc.versionString)
            }
            .font(.caption2)

            let totalCtx = doc.contexts.count
            let totalCanvases = doc.contexts.flatMap(\.canvases).count
            let totalFDs = doc.contexts.flatMap(\.canvases).flatMap(\.framingDecisions).count
            HStack(spacing: 4) {
                Text(verbatim: "\(totalCtx) Context\(totalCtx == 1 ? "" : "s")").foregroundStyle(.secondary)
                Text("\u{00B7}").foregroundStyle(.quaternary)
                Text(verbatim: "\(totalCanvases) Canvas\(totalCanvases == 1 ? "" : "es")").foregroundStyle(.secondary)
                Text("\u{00B7}").foregroundStyle(.quaternary)
                Text(verbatim: "\(totalFDs) Framing Decision\(totalFDs == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
            .font(.caption2)

            if let canvas = viewModel.selectedCanvas {
                HStack(spacing: 4) {
                    Text("Canvas:").foregroundStyle(.secondary)
                    Text(verbatim: "\(Int(canvas.dimensions.width))\u{00D7}\(Int(canvas.dimensions.height))")
                        .font(.system(.caption2, design: .monospaced))
                }
                .font(.caption2)

                if let eff = canvas.effectiveDimensions {
                    HStack(spacing: 4) {
                        Text("Effective:").foregroundStyle(.secondary)
                        Text(verbatim: "\(Int(eff.width))\u{00D7}\(Int(eff.height))")
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .font(.caption2)
                }

                if let squeeze = canvas.anamorphicSqueeze, squeeze != 1.0 {
                    HStack(spacing: 4) {
                        Text("Squeeze:").foregroundStyle(.secondary)
                        Text(String(format: "%.2f\u{00D7}", squeeze))
                            .font(.system(.caption2, design: .monospaced))
                    }
                    .font(.caption2)
                }
            }

            if let intent = doc.defaultFramingIntent {
                HStack(spacing: 4) {
                    Text("Intent:").foregroundStyle(.secondary)
                    Text(intent)
                }
                .font(.caption2)
            }
        }
    }

    // MARK: - Template Views

    @ViewBuilder
    private var templateEmptyView: some View {
        templateSourceMenu
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

        Text("Select a preset, create custom, or import a template")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
    }

    private var templateSourceMenu: some View {
        HStack(spacing: 4) {
            Menu {
                Button("New Blank Template") {
                    viewModel.startCustomTemplate()
                }
                Divider()
                Section("Scenario Presets") {
                    ForEach(TemplatePresets.scenarioContexts, id: \.name) { preset in
                        Button(preset.name) {
                            viewModel.applyPreset(preset.name)
                        }
                    }
                }
                Section("Delivery Presets") {
                    ForEach(TemplatePresets.standardDeliverables, id: \.name) { preset in
                        Button(preset.name) {
                            viewModel.applyPreset(preset.name)
                        }
                    }
                }
                Divider()
                Button("Import Template...") {
                    viewModel.importTemplateJSON()
                }
                if !appState.libraryViewModel.canvasTemplates.isEmpty {
                    Divider()
                    Menu("From Library") {
                        ForEach(
                            appState.libraryViewModel.canvasTemplates
                        ) { tpl in
                            Button(tpl.name) {
                                viewModel.loadLibraryTemplate(tpl)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.on.rectangle.angled")
                    Text("Select Template...")
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .menuStyle(.borderlessButton)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3))
            )
        }
    }

    @ViewBuilder
    private var templateSummaryView: some View {
        HStack {
            Image(systemName: "rectangle.on.rectangle.angled")
                .foregroundStyle(.purple)
            Text(viewModel.templateConfig.label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer()
            templatePresetMenu
            Button(action: { viewModel.resetTemplateValues() }) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reset template to defaults")
            Button(action: { viewModel.resetTemplate() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear template")
        }

        if let presetName = viewModel.selectedPresetName,
           let description = TemplatePresets.scenarioDescription(for: presetName) {
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        Divider()

        templateConfigFields

        Button(action: {
            viewModel.applyTemplate(pythonBridge: appState.pythonBridge, defaultCreator: appState.defaultCreator)
        }) {
            HStack {
                if viewModel.isApplyingTemplate {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.right.square")
                }
                Text(
                    viewModel.outputDocument != nil
                        ? "REPROCESS" : "TRANSFORM"
                )
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            viewModel.isApplyingTemplate
                || viewModel.loadedDocument == nil
        )
        .help(
            viewModel.loadedDocument == nil
                ? "Load a Source FDL first"
                : "Apply template to generate output"
        )

        HStack(spacing: 6) {
            Menu {
                ForEach(TemplatePresets.scenarioContexts, id: \.name) { preset in
                    Button(preset.name) {
                        viewModel.applyScenarioPresetAndTransform(
                            preset.name,
                            pythonBridge: appState.pythonBridge,
                            defaultCreator: appState.defaultCreator
                        )
                    }
                }
            } label: {
                Label("Apply Scenario", systemImage: "bolt.fill")
                    .font(.caption)
            }
            .controlSize(.small)
            .disabled(viewModel.loadedDocument == nil || viewModel.isApplyingTemplate)

            Button(action: {
                viewModel.saveTemplateToLibrary(
                    libraryStore: appState.libraryStore,
                    libraryViewModel: appState.libraryViewModel
                )
            }) {
                Label("Save Template", systemImage: "building.columns")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu {
                Button("Export Template JSON") {
                    viewModel.exportTemplateJSON()
                }

                if !appState.libraryViewModel.projects.isEmpty {
                    Divider()
                    Menu("Add Template to Project") {
                        ForEach(appState.libraryViewModel.projects) { project in
                            Button(project.name) {
                                viewModel.assignTemplateToProject(
                                    projectID: project.id,
                                    libraryStore: appState.libraryStore,
                                    libraryViewModel: appState.libraryViewModel
                                )
                            }
                        }
                    }
                }

                if viewModel.outputDocument != nil, !appState.libraryViewModel.projects.isEmpty {
                    Menu("Save Output to Project") {
                        ForEach(appState.libraryViewModel.projects) { project in
                            Button(project.name) {
                                viewModel.saveOutputToProject(
                                    projectID: project.id,
                                    libraryStore: appState.libraryStore,
                                    libraryViewModel: appState.libraryViewModel
                                )
                            }
                        }
                    }
                }

                Divider()
                Button("Export Scenario Pack...") {
                    showScenarioPackSheet = true
                }
                .disabled(viewModel.loadedDocument == nil || viewModel.isApplyingTemplate)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .font(.caption)
            }
            .controlSize(.small)

            Spacer(minLength: 0)
        }
    }

    /// Dropdown on the template name to switch presets or import.
    private var templatePresetMenu: some View {
        Menu {
            Button("New Blank Template") {
                viewModel.startCustomTemplate()
            }
            Divider()
            Section("Scenario Presets") {
                ForEach(TemplatePresets.scenarioContexts, id: \.name) { preset in
                    Button(preset.name) {
                        viewModel.applyPreset(preset.name)
                    }
                }
            }
            Section("Delivery Presets") {
                ForEach(TemplatePresets.standardDeliverables, id: \.name) { preset in
                    Button(preset.name) {
                        viewModel.applyPreset(preset.name)
                    }
                }
            }
            Divider()
            Button("Import Template...") {
                viewModel.importTemplateJSON()
            }
            if !appState.libraryViewModel.canvasTemplates.isEmpty {
                Divider()
                Menu("From Library") {
                    ForEach(
                        appState.libraryViewModel.canvasTemplates
                    ) { tpl in
                        Button(tpl.name) {
                            viewModel.loadLibraryTemplate(tpl)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 9))
                Text("Load Template")
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var templateConfigFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("Label")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField(
                    "Template Label",
                    text: $viewModel.templateConfig.label
                )
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            }

            Text("Target Dimensions")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Width")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(
                        "W",
                        value: $viewModel.templateConfig.targetWidth,
                        format: .number.grouping(.never)
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 70)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Height")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(
                        "H",
                        value: $viewModel.templateConfig.targetHeight,
                        format: .number.grouping(.never)
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: 70)
                }
            }

            HStack(spacing: 4) {
                Text("Anamorphic Squeeze")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField(
                    "Squeeze",
                    value: $viewModel.templateConfig.targetAnamorphicSqueeze,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 60)
            }

            Picker(
                "Fit Source",
                selection: $viewModel.templateConfig.fitSource
            ) {
                ForEach(
                    TemplatePresets.fitSourceOptions, id: \.value
                ) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .font(.caption)

            Picker(
                "Fit Method",
                selection: $viewModel.templateConfig.fitMethod
            ) {
                ForEach(
                    TemplatePresets.fitMethodOptions, id: \.value
                ) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .font(.caption)

            Text("Alignment")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Picker(
                    "H",
                    selection: $viewModel.templateConfig.alignmentHorizontal
                ) {
                    ForEach(
                        TemplatePresets.alignmentHOptions, id: \.value
                    ) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .font(.caption)
                Picker(
                    "V",
                    selection: $viewModel.templateConfig.alignmentVertical
                ) {
                    ForEach(
                        TemplatePresets.alignmentVOptions, id: \.value
                    ) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .font(.caption)
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Maximum Dimensions")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Max W")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField(
                                "Max W",
                                value: $viewModel.templateConfig.maximumWidth,
                                format: .number.grouping(.never)
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 70)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Max H")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField(
                                "Max H",
                                value: $viewModel.templateConfig.maximumHeight,
                                format: .number.grouping(.never)
                            )
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 70)
                        }
                    }

                    Toggle(
                        "Pad to Maximum",
                        isOn: $viewModel.templateConfig.padToMaximum
                    )
                    .font(.caption)

                    Divider()

                    Text("Rounding")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker(
                        "Round To",
                        selection: $viewModel.templateConfig.roundEven
                    ) {
                        ForEach(
                            TemplatePresets.roundEvenOptions, id: \.value
                        ) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .font(.caption)

                    Picker(
                        "Mode",
                        selection: $viewModel.templateConfig.roundMode
                    ) {
                        ForEach(
                            TemplatePresets.roundModeOptions, id: \.value
                        ) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .font(.caption)

                    Divider()

                    Picker(
                        "Preserve from Source",
                        selection: Binding(
                            get: {
                                viewModel.templateConfig
                                    .preserveFromSourceCanvas ?? ""
                            },
                            set: {
                                viewModel.templateConfig
                                    .preserveFromSourceCanvas =
                                    $0.isEmpty ? nil : $0
                            }
                        )
                    ) {
                        Text("None").tag("")
                        Text("Framing Decision")
                            .tag("framing_decision.dimensions")
                        Text("Protection")
                            .tag("framing_decision.protection_dimensions")
                        Text("Effective Canvas")
                            .tag("canvas.effective_dimensions")
                        Text("Full Canvas")
                            .tag("canvas.dimensions")
                    }
                    .font(.caption)
                }
                .padding(.vertical, 2)
            } label: {
                Text("Advanced")
                    .font(.caption2.weight(.medium))
            }
            .font(.caption)
        }
    }

    // MARK: - Library Browse Menu

    @ViewBuilder
    private var libraryBrowseMenu: some View {
        let projects = appState.libraryViewModel.projects
        Menu {
            if projects.isEmpty {
                Text("No library projects")
            } else {
                ForEach(projects) { project in
                    Menu(project.name) {
                        LibraryEntryMenu(
                            project: project,
                            libraryStore: appState.libraryStore,
                            onSelect: { entry in
                                viewModel.loadFromEntry(entry, pythonBridge: appState.pythonBridge)
                            }
                        )
                    }
                }
            }
        } label: {
            Image(systemName: "building.columns")
                .help("Browse Library")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Drop Handlers

    private func extractURL(from provider: NSItemProvider, completion: @escaping (URL) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    completion(url)
                } else if let url = item as? URL {
                    completion(url)
                }
            }
        }
    }

    private func handleFDLDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            extractURL(from: provider) { url in
                let ext = url.pathExtension.lowercased()
                guard ["fdl", "json"].contains(ext) else { return }
                Task { @MainActor in
                    viewModel.loadFromURL(url, pythonBridge: appState.pythonBridge)
                }
            }
        }
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            extractURL(from: provider) { url in
                let ext = url.pathExtension.lowercased()
                guard ["png", "jpg", "jpeg", "tiff", "tif", "exr", "bmp"].contains(ext) else { return }
                Task { @MainActor in
                    viewModel.loadReferenceImage(from: url)
                }
            }
        }
    }
}

/// Fetches and displays FDL entries for a project so the user can select one.
struct LibraryEntryMenu: View {
    let project: Project
    let libraryStore: LibraryStore
    let onSelect: (FDLEntry) -> Void
    @State private var entries: [FDLEntry] = []

    var body: some View {
        ForEach(entries) { entry in
            Button(entry.name) {
                onSelect(entry)
            }
        }
        if entries.isEmpty {
            Text("No FDL entries")
        }
        // swiftlint:disable:next redundant_discardable_let
        let _ = loadEntries()
    }

    private func loadEntries() -> EmptyView {
        if entries.isEmpty {
            if let fetched = try? libraryStore.fdlEntries(forProject: project.id) {
                DispatchQueue.main.async { entries = fetched }
            }
        }
        return EmptyView()
    }
}

private struct ScenarioPackExportSheet: View {
    let scenarioNames: [String]
    let projects: [Project]
    let onExport: ([String], Bool, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [String: Bool]
    @State private var includeZip = true
    @State private var selectedProjectID: String?

    init(
        scenarioNames: [String],
        projects: [Project],
        onExport: @escaping ([String], Bool, String?) -> Void
    ) {
        self.scenarioNames = scenarioNames
        self.projects = projects
        self.onExport = onExport
        var initial: [String: Bool] = [:]
        for name in scenarioNames {
            initial[name] = true
        }
        _selections = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export Scenario Pack")
                .font(.headline)

            Text("Select one or more scenario templates to apply and export as a grouped package.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(scenarioNames, id: \.self) { name in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(name, isOn: Binding(
                        get: { selections[name] ?? false },
                        set: { selections[name] = $0 }
                    ))
                    if let desc = TemplatePresets.scenarioDescription(for: name) {
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 22)
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
            .frame(height: 180)

            Toggle("Also create ZIP archive", isOn: $includeZip)
                .font(.caption)

            if !projects.isEmpty {
                Picker("Save links to Project", selection: $selectedProjectID) {
                    Text("None").tag(nil as String?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id as String?)
                    }
                }
                .font(.caption)
                .pickerStyle(.menu)
            }

            HStack {
                Button("All") {
                    for name in scenarioNames {
                        selections[name] = true
                    }
                }
                .buttonStyle(.borderless)
                Button("None") {
                    for name in scenarioNames {
                        selections[name] = false
                    }
                }
                .buttonStyle(.borderless)
                Text("\(scenarioNames.filter { selections[$0] ?? false }.count) selected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Export") {
                    let selected = scenarioNames.filter { selections[$0] ?? false }
                    onExport(selected, includeZip, selectedProjectID)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!scenarioNames.contains(where: { selections[$0] ?? false }))
            }
        }
        .padding()
        .frame(width: 520, height: 360)
    }
}
