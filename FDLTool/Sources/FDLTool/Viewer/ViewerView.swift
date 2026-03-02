import SwiftUI
import UniformTypeIdentifiers

struct ViewerView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ViewerViewModel()

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
        .navigationTitle("FDL Viewer")
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: appState.pendingOpenURL) { _, url in
            guard let url else { return }
            appState.pendingOpenURL = nil
            viewModel.loadFromURL(url, pythonBridge: appState.pythonBridge)
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
                Text("\(Int(viewModel.zoomScale * 100))%")
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

            Divider().frame(height: 18)

            layerToggleMenu

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
                GroupBox("Source FDL") {
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
                            }

                            if let val = viewModel.validationResult {
                                HStack(spacing: 4) {
                                    Image(systemName: val.valid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(val.valid ? .green : .orange)
                                    Text(val.valid ? "Valid" : "\(val.errors.count) issue(s)")
                                        .font(.caption2)
                                        .foregroundStyle(val.valid ? .green : .orange)
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
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleFDLDrop(providers)
                    return true
                }

                // Selection pickers (shown when document loaded)
                if viewModel.loadedDocument != nil {
                    GroupBox("Selection") {
                        VStack(alignment: .leading, spacing: 8) {
                            if viewModel.contextLabels.count > 1 {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Context")
                                        .font(.caption2)
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
                                        .font(.caption2)
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
                                        .font(.caption2)
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
                                    Text("\(Int(canvas.dimensions.width)) \u{00D7} \(Int(canvas.dimensions.height))")
                                        .font(.system(.caption, design: .monospaced))
                                    if let eff = canvas.effectiveDimensions {
                                        Text("Effective: \(Int(eff.width)) \u{00D7} \(Int(eff.height))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let squeeze = canvas.anamorphicSqueeze, squeeze != 1.0 {
                                        Text("Squeeze: \(String(format: "%.2f\u{00D7}", squeeze))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    let fdCount = canvas.framingDecisions.count
                                    Text("\(fdCount) framing decision\(fdCount == 1 ? "" : "s")")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                GroupBox("Reference Image") {
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
                                    .font(.caption2)
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
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleImageDrop(providers)
                    return true
                }

                GroupBox("Template") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Picker("Preset", selection: Binding(
                                get: { viewModel.selectedPresetName ?? "" },
                                set: { if !$0.isEmpty { viewModel.applyPreset($0) } }
                            )) {
                                Text("Custom").tag("")
                                ForEach(TemplatePresets.all, id: \.name) { preset in
                                    Text(preset.name).tag(preset.name)
                                }
                            }
                            .font(.caption)

                            Menu {
                                Button("Import Template JSON...") {
                                    viewModel.importTemplateJSON()
                                }
                                Button("Export Template JSON...") {
                                    viewModel.exportTemplateJSON()
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        Text("Target Dimensions")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Width").font(.caption2).foregroundStyle(.secondary)
                                TextField("W", value: $viewModel.templateConfig.targetWidth, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .frame(width: 70)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Height").font(.caption2).foregroundStyle(.secondary)
                                TextField("H", value: $viewModel.templateConfig.targetHeight, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .frame(width: 70)
                            }
                        }

                        Picker("Fit Source", selection: $viewModel.templateConfig.fitSource) {
                            ForEach(TemplatePresets.fitSourceOptions, id: \.value) { opt in
                                Text(opt.label).tag(opt.value)
                            }
                        }
                        .font(.caption)

                        Picker("Fit Method", selection: $viewModel.templateConfig.fitMethod) {
                            ForEach(TemplatePresets.fitMethodOptions, id: \.value) { opt in
                                Text(opt.label).tag(opt.value)
                            }
                        }
                        .font(.caption)

                        Text("Alignment")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 4) {
                            Picker("H", selection: $viewModel.templateConfig.alignmentHorizontal) {
                                ForEach(TemplatePresets.alignmentHOptions, id: \.value) { opt in
                                    Text(opt.label).tag(opt.value)
                                }
                            }
                            .font(.caption)
                            Picker("V", selection: $viewModel.templateConfig.alignmentVertical) {
                                ForEach(TemplatePresets.alignmentVOptions, id: \.value) { opt in
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
                                        Text("Max W").font(.caption2).foregroundStyle(.secondary)
                                        TextField("Max W", value: $viewModel.templateConfig.maximumWidth, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.caption)
                                            .frame(width: 70)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Max H").font(.caption2).foregroundStyle(.secondary)
                                        TextField("Max H", value: $viewModel.templateConfig.maximumHeight, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.caption)
                                            .frame(width: 70)
                                    }
                                }

                                Toggle("Pad to Maximum", isOn: $viewModel.templateConfig.padToMaximum)
                                    .font(.caption)

                                Divider()

                                Text("Rounding")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)

                                Picker("Round To", selection: $viewModel.templateConfig.roundEven) {
                                    ForEach(TemplatePresets.roundEvenOptions, id: \.value) { opt in
                                        Text(opt.label).tag(opt.value)
                                    }
                                }
                                .font(.caption)

                                Picker("Mode", selection: $viewModel.templateConfig.roundMode) {
                                    ForEach(TemplatePresets.roundModeOptions, id: \.value) { opt in
                                        Text(opt.label).tag(opt.value)
                                    }
                                }
                                .font(.caption)

                                Divider()

                                Picker("Preserve from Source", selection: Binding(
                                    get: { viewModel.templateConfig.preserveFromSourceCanvas ?? "" },
                                    set: { viewModel.templateConfig.preserveFromSourceCanvas = $0.isEmpty ? nil : $0 }
                                )) {
                                    Text("None (omit)").tag("")
                                    Text("Framing Decision").tag("framing_decision.dimensions")
                                    Text("Protection").tag("framing_decision.protection_dimensions")
                                    Text("Effective Canvas").tag("canvas.effective_dimensions")
                                    Text("Full Canvas").tag("canvas.dimensions")
                                }
                                .font(.caption)
                            }
                            .padding(.vertical, 2)
                        } label: {
                            Text("Advanced")
                                .font(.caption2.weight(.medium))
                        }
                        .font(.caption)

                        Button(action: { viewModel.applyTemplate(pythonBridge: appState.pythonBridge) }) {
                            HStack {
                                if viewModel.isApplyingTemplate {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.right.square")
                                }
                                Text(viewModel.outputDocument != nil ? "REPROCESS" : "TRANSFORM")
                                    .font(.caption.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isApplyingTemplate || viewModel.loadedDocument == nil)
                    }
                    .padding(.vertical, 4)
                }

                // Layer visibility
                GroupBox("Layers") {
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle("Canvas", isOn: $viewModel.showCanvasLayer)
                        Toggle("Effective", isOn: $viewModel.showEffectiveLayer)
                        Toggle("Framing", isOn: $viewModel.showFramingLayer)
                        Toggle("Protection", isOn: $viewModel.showProtectionLayer)
                        Divider()
                        Toggle("Dimension Labels", isOn: $viewModel.showDimensionLabels)
                        Toggle("Anchor Points", isOn: $viewModel.showAnchorPoints)
                        Toggle("Crosshairs", isOn: $viewModel.showCrosshairs)
                        Toggle("HUD", isOn: $viewModel.showHUD)
                        Toggle("Grid", isOn: $viewModel.showGridOverlay)
                        if viewModel.showGridOverlay {
                            Picker("Spacing", selection: $viewModel.gridSpacing) {
                                Text("100").tag(100.0)
                                Text("250").tag(250.0)
                                Text("500").tag(500.0)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }

                // Document tree (when loaded)
                if let doc = viewModel.loadedDocument {
                    FDLTreeView(document: doc)
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

    @ViewBuilder
    private var sourceTabContent: some View {
        if viewModel.loadedDocument != nil {
            CanvasVisualizationView(viewModel: viewModel)
                .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
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

            Text("FDL Viewer")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Load a Source FDL from the sidebar to visualize\ncanvas geometry, apply templates, and compare results.")
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
            OutputCanvasView(viewModel: viewModel)
                .background(Color(nsColor: NSColor(white: 0.12, alpha: 1)))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let doc = viewModel.loadedDocument {
                    GroupBox("Document") {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
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
                                Text("\(doc.contexts.count)")
                            }
                            GridRow {
                                Text("Canvases").foregroundStyle(.secondary)
                                Text("\(doc.contexts.flatMap(\.canvases).count)")
                            }
                            GridRow {
                                Text("Framing Decisions").foregroundStyle(.secondary)
                                Text("\(doc.contexts.flatMap(\.canvases).flatMap(\.framingDecisions).count)")
                            }
                        }
                        .font(.caption)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let result = viewModel.validationResult {
                        ValidationReportView(result: result)
                    }

                    if let canvas = viewModel.selectedCanvas {
                        GroupBox("Selected Canvas") {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                                GridRow {
                                    Text("ID").foregroundStyle(.secondary)
                                    Text(canvas.id).textSelection(.enabled)
                                }
                                GridRow {
                                    Text("Dimensions").foregroundStyle(.secondary)
                                    Text("\(Int(canvas.dimensions.width)) \u{00D7} \(Int(canvas.dimensions.height))")
                                }
                                if let eff = canvas.effectiveDimensions {
                                    GridRow {
                                        Text("Effective").foregroundStyle(.secondary)
                                        Text("\(Int(eff.width)) \u{00D7} \(Int(eff.height))")
                                    }
                                }
                                if let squeeze = canvas.anamorphicSqueeze, squeeze != 1.0 {
                                    GridRow {
                                        Text("Squeeze").foregroundStyle(.secondary)
                                        Text(String(format: "%.2f\u{00D7}", squeeze))
                                    }
                                }
                            }
                            .font(.caption)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let info = viewModel.transformInfo {
                        GroupBox("Transform Result") {
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
                                GridRow {
                                    Text("Template").foregroundStyle(.secondary)
                                    Text(viewModel.templateConfig.label)
                                }
                                GridRow {
                                    Text("Target").foregroundStyle(.secondary)
                                    Text("\(viewModel.templateConfig.targetWidth)\u{00D7}\(viewModel.templateConfig.targetHeight)")
                                }
                            }
                            .font(.caption)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    GroupBox("Source JSON") {
                        if let raw = viewModel.rawJSON {
                            ScrollView(.horizontal) {
                                Text(raw)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 300)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack {
                            Button("Copy JSON") {
                                if let raw = viewModel.rawJSON {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(raw, forType: .string)
                                }
                            }
                            .font(.caption)
                        }
                        .padding(.top, 4)
                    }

                    if let outJSON = viewModel.outputRawJSON {
                        GroupBox("Output JSON") {
                            ScrollView(.horizontal) {
                                Text(outJSON)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 300)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack {
                                Button("Copy Output JSON") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(outJSON, forType: .string)
                                }
                                .font(.caption)

                                Button("Export Output FDL...") {
                                    let panel = NSSavePanel()
                                    panel.allowedContentTypes = [.json]
                                    panel.nameFieldStringValue = "output.fdl.json"
                                    if panel.runModal() == .OK, let dest = panel.url {
                                        try? outJSON.write(to: dest, atomically: true, encoding: .utf8)
                                    }
                                }
                                .font(.caption)
                            }
                            .padding(.top, 4)
                        }
                    }
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
                    .padding(.top, 80)
                }
            }
            .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Layer Toggle Menu

    @ViewBuilder
    private var layerToggleMenu: some View {
        Menu {
            Toggle("Canvas", isOn: $viewModel.showCanvasLayer)
            Toggle("Effective", isOn: $viewModel.showEffectiveLayer)
            Toggle("Framing", isOn: $viewModel.showFramingLayer)
            Toggle("Protection", isOn: $viewModel.showProtectionLayer)
            Divider()
            Toggle("Labels", isOn: $viewModel.showDimensionLabels)
            Toggle("Anchors", isOn: $viewModel.showAnchorPoints)
            Toggle("Crosshairs", isOn: $viewModel.showCrosshairs)
            Toggle("HUD", isOn: $viewModel.showHUD)
            Toggle("Grid", isOn: $viewModel.showGridOverlay)
        } label: {
            Label("Layers", systemImage: "square.3.layers.3d")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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

            let totalCanvases = doc.contexts.flatMap(\.canvases).count
            let totalFDs = doc.contexts.flatMap(\.canvases).flatMap(\.framingDecisions).count
            HStack(spacing: 4) {
                Text("\(doc.contexts.count) ctx").foregroundStyle(.secondary)
                Text("\u{00B7}").foregroundStyle(.quaternary)
                Text("\(totalCanvases) canvas").foregroundStyle(.secondary)
                Text("\u{00B7}").foregroundStyle(.quaternary)
                Text("\(totalFDs) FD").foregroundStyle(.secondary)
            }
            .font(.caption2)

            if let canvas = viewModel.selectedCanvas {
                HStack(spacing: 4) {
                    Text("Canvas:").foregroundStyle(.secondary)
                    Text("\(Int(canvas.dimensions.width))\u{00D7}\(Int(canvas.dimensions.height))")
                        .font(.system(.caption2, design: .monospaced))
                }
                .font(.caption2)

                if let eff = canvas.effectiveDimensions {
                    HStack(spacing: 4) {
                        Text("Effective:").foregroundStyle(.secondary)
                        Text("\(Int(eff.width))\u{00D7}\(Int(eff.height))")
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
