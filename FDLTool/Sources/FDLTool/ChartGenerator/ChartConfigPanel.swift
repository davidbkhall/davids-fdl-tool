import SwiftUI

private enum SqueezeChoice: Hashable {
    case preset(Double)
    case custom
}

/// Left panel: camera picker, recording mode, frameline management.
struct ChartConfigPanel: View {
    @ObservedObject var viewModel: ChartGeneratorViewModel
    @ObservedObject var cameraDB: CameraDBStore

    @State private var selectedMake: String?
    @State private var squeezeChoice: SqueezeChoice = .preset(1.0)
    @State private var customSqueezeValue: Double = 1.33

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    TextField("Title", text: $viewModel.chartTitle)
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 2)
                } label: {
                    Label("Chart Title", systemImage: "textformat")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Use custom canvas", isOn: $viewModel.useCustomCanvas)
                            .font(.caption)

                        if viewModel.useCustomCanvas {
                            customCanvasFields
                        } else {
                            cameraCascadingPickers
                        }

                        // Canvas summary
                        canvasSummary
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Camera & Mode", systemImage: "camera")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Spacer()
                            addFramingIntentMenu
                        }

                        if viewModel.framingIntents.isEmpty {
                            Text("No framing intents. Add from presets or create custom.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(viewModel.framingIntents.enumerated()), id: \.element.id) { index, intent in
                                FramingIntentRow(
                                    intent: Binding(
                                        get: {
                                            guard index < viewModel.framingIntents.count else { return intent }
                                            return viewModel.framingIntents[index]
                                        },
                                        set: { newIntent in
                                            guard index < viewModel.framingIntents.count else { return }
                                            viewModel.framingIntents[index] = newIntent
                                            viewModel.recalculateFramelinesForIntent(newIntent.id)
                                        }
                                    ),
                                    onDelete: { viewModel.removeFramingIntent(intent) }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Framing Intents", systemImage: "aspectratio")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Framelines")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            addFramelineMenu
                        }

                        if viewModel.framelines.isEmpty {
                            Text("No framelines. Add from presets or create custom.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(viewModel.framelines.enumerated()), id: \.element.id) { index, frameline in
                                FramelineRow(
                                    frameline: Binding(
                                        get: {
                                            guard index < viewModel.framelines.count else { return frameline }
                                            return viewModel.framelines[index]
                                        },
                                        set: {
                                            guard index < viewModel.framelines.count else { return }
                                            viewModel.framelines[index] = $0
                                        }
                                    ),
                                    framingIntents: viewModel.framingIntents,
                                    viewModel: viewModel,
                                    onDelete: { viewModel.removeFrameline(frameline) }
                                )
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Framing Decisions", systemImage: "viewfinder.rectangular")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable effective area", isOn: $viewModel.showEffectiveDimensions)
                            .font(.caption)

                        if viewModel.showEffectiveDimensions {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Width")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    TextField("W", value: $viewModel.canvasEffectiveWidth, format: .number.grouping(.never))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                }
                                Text("\u{00D7}")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Height")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    TextField("H", value: $viewModel.canvasEffectiveHeight, format: .number.grouping(.never))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                }
                            }

                            if viewModel.canvasEffectiveWidth != nil {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Anchor X")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        TextField("X", value: $viewModel.canvasEffectiveAnchorX, format: .number.grouping(.never))
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Anchor Y")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        TextField("Y", value: $viewModel.canvasEffectiveAnchorY, format: .number.grouping(.never))
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .font(.caption)
                } label: {
                    Label("Effective Dimensions", systemImage: "rectangle.center.inset.filled")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Squeeze", selection: Binding(
                            get: {
                                switch squeezeChoice {
                                case .preset(let v):
                                    let current = viewModel.anamorphicSqueeze
                                    return current == v ? squeezeChoice : .preset(current)
                                case .custom: return .custom
                                }
                            },
                            set: { choice in
                                squeezeChoice = choice
                                switch choice {
                                case .preset(let v): viewModel.anamorphicSqueeze = v
                                case .custom:
                                    customSqueezeValue = viewModel.anamorphicSqueeze
                                }
                            }
                        )) {
                            Text("1.0\u{00D7}").tag(SqueezeChoice.preset(1.0))
                            Text("1.3\u{00D7}").tag(SqueezeChoice.preset(1.3))
                            Text("1.5\u{00D7}").tag(SqueezeChoice.preset(1.5))
                            Text("2.0\u{00D7}").tag(SqueezeChoice.preset(2.0))
                            Text("Custom").tag(SqueezeChoice.custom)
                        }
                        .pickerStyle(.segmented)

                        if case .custom = squeezeChoice {
                            HStack {
                                Text("Value")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("Squeeze", value: Binding(
                                    get: { customSqueezeValue },
                                    set: { customSqueezeValue = $0; viewModel.anamorphicSqueeze = $0 }
                                ), format: .number.grouping(.never))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                } label: {
                    Label("Anamorphic Squeeze", systemImage: "arrow.left.and.right")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Canvas Boundary", isOn: $viewModel.showCanvasLayer)
                        Toggle("Effective Area", isOn: $viewModel.showEffectiveLayer)
                        Toggle("Framing Decisions", isOn: $viewModel.showFramingLayer)
                        Toggle("Protection", isOn: $viewModel.showProtectionLayer)
                        Toggle("Dimension Labels", isOn: $viewModel.showDimensionLabels)
                        Toggle("Crosshairs", isOn: $viewModel.showCrosshairs)
                        Toggle("Grid", isOn: $viewModel.showGridOverlay)
                        if viewModel.showGridOverlay {
                            Picker("Grid Spacing", selection: $viewModel.gridSpacing) {
                                Text("250 px").tag(250.0)
                                Text("500 px").tag(500.0)
                                Text("1000 px").tag(1000.0)
                            }
                            .pickerStyle(.segmented)
                        }
                        if viewModel.anamorphicSqueeze != 1.0 {
                            Toggle("Squeeze Circle", isOn: $viewModel.showSqueezeCircle)
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 2)
                } label: {
                    Label("Layers", systemImage: "square.3.layers.3d")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Show on chart", isOn: $viewModel.metadataOverlayShow)
                            .font(.caption)
                        if viewModel.metadataOverlayShow {
                            TextField("Show/Project Name", text: $viewModel.metadataShowName)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                            TextField("DP / Cinematographer", text: $viewModel.metadataDOP)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                } label: {
                    Label("Metadata Overlay", systemImage: "text.below.photo")
                        .font(.headline)
                }

                GroupBox {
                    Toggle("Show labels on chart", isOn: $viewModel.showLabels)
                        .font(.caption)
                        .padding(.vertical, 2)
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
                        .font(.headline)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var cameraCascadingPickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Make", selection: Binding(
                    get: { selectedMake ?? "" },
                    set: { new in
                        selectedMake = new.isEmpty ? nil : new
                        viewModel.selectedCameraID = nil
                        viewModel.selectedModeID = nil
                    }
                )) {
                    Text("Select make...").tag("")
                    ForEach(cameraDB.manufacturers, id: \.self) { mfr in
                        Text(mfr).tag(mfr)
                    }
                }
                .labelsHidden()
            }

            if selectedMake != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Model", selection: Binding(
                        get: { viewModel.selectedCameraID ?? "" },
                        set: { new in
                            viewModel.selectedCameraID = new.isEmpty ? nil : new
                            viewModel.selectedModeID = nil
                        }
                    )) {
                        Text("Select model...").tag("")
                        ForEach(cameraDB.cameras(byManufacturer: selectedMake ?? "")) { cam in
                            Text("\(cam.model)").tag(cam.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            if let camera = viewModel.selectedCamera {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording Mode")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Mode", selection: Binding(
                        get: { viewModel.selectedModeID ?? "" },
                        set: { viewModel.selectedModeID = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Select mode...").tag("")
                        ForEach(camera.recordingModes) { mode in
                            Text(verbatim: "\(mode.name) (\(mode.activePhotosites.width)\u{00D7}\(mode.activePhotosites.height))")
                                .tag(mode.id)
                        }
                    }
                    .labelsHidden()
                }

                if let mode = viewModel.selectedRecordingMode {
                    HStack(spacing: 8) {
                        Text(verbatim: "\(mode.activePhotosites.width) \u{00D7} \(mode.activePhotosites.height)")
                            .font(.system(.caption, design: .monospaced))
                        AspectRatioLabel(width: Double(mode.activePhotosites.width),
                                         height: Double(mode.activePhotosites.height))
                    }
                    .padding(6)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .onAppear {
            if selectedMake == nil, let cam = viewModel.selectedCamera {
                selectedMake = cam.manufacturer
            }
        }
    }

    @ViewBuilder
    private var customCanvasFields: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Width")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("W", value: $viewModel.customCanvasWidth, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
            Text("\u{00D7}")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Height")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("H", value: $viewModel.customCanvasHeight, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
            }
        }
    }

    @ViewBuilder
    private var canvasSummary: some View {
        let w = viewModel.canvasWidth
        let h = viewModel.canvasHeight
        if w > 0 && h > 0 {
            HStack(spacing: 6) {
                Text("Canvas:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(Int(w)) \u{00D7} \(Int(h))")
                    .font(.system(.caption, design: .monospaced))
                AspectRatioLabel(width: w, height: h)
            }
        }
    }

    private var addFramingIntentMenu: some View {
        Menu {
            Section("Presets") {
                ForEach(commonPresets) { preset in
                    Button(preset.label) {
                        viewModel.addFramingIntent(label: preset.label, aspectWidth: preset.aspectWidth, aspectHeight: preset.aspectHeight)
                    }
                }
            }
            Divider()
            Button("Custom...") {
                viewModel.addFramingIntent(label: "Custom", aspectWidth: 2.39, aspectHeight: 1)
            }
        } label: {
            Label("Add Intent", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
    }

    private var addFramelineMenu: some View {
        Menu {
            if !viewModel.framingIntents.isEmpty {
                Section("From Framing Intent") {
                    ForEach(viewModel.framingIntents) { intent in
                        Button("\(intent.label) (\(intent.aspectRatioDescription))") {
                            viewModel.addFramelineFromIntent(intent)
                        }
                    }
                }
            }
            Section("Presets") {
                ForEach(commonPresets) { preset in
                    Button(preset.label) {
                        viewModel.addPreset(preset)
                    }
                }
            }
            Divider()
            Button("Custom (canvas size)...") {
                viewModel.addFrameline(label: "Custom")
            }
        } label: {
            Label("Add", systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton)
    }
}

// MARK: - Framing Intent Row

struct FramingIntentRow: View {
    @Binding var intent: FramingIntent
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                TextField("Label", text: Binding(
                    get: { intent.label },
                    set: { var i = intent; i.label = $0; intent = i }
                ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 120)

                Text(intent.aspectRatioDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.7))
            }

            HStack(spacing: 8) {
                Text("Aspect")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("W", value: Binding(
                    get: { intent.aspectWidth },
                    set: { var i = intent; i.aspectWidth = $0; intent = i }
                ), format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    .font(.caption)
                Text(":")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("H", value: Binding(
                    get: { intent.aspectHeight },
                    set: { var i = intent; i.aspectHeight = $0; intent = i }
                ), format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 55)
                    .font(.caption)
            }

            HStack(spacing: 6) {
                Text("Protection")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { intent.protectionPercent },
                    set: { var i = intent; i.protectionPercent = $0; intent = i }
                ), in: 0...100, step: 0.5)
                    .frame(maxWidth: 120)
                TextField("", value: Binding(
                    get: { intent.protectionPercent },
                    set: { var i = intent; i.protectionPercent = max(0, $0); intent = i }
                ), format: .number.grouping(.never).precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .font(.caption)
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Frameline Row

struct FramelineRow: View {
    @Binding var frameline: Frameline
    let framingIntents: [FramingIntent]
    let viewModel: ChartGeneratorViewModel
    let onDelete: () -> Void

    private var linkedIntent: FramingIntent? {
        guard let id = frameline.linkedIntentID else { return nil }
        return framingIntents.first { $0.id == id }
    }

    private var effectiveAspectRatio: Double {
        if let intent = linkedIntent, intent.aspectRatio > 0 {
            return intent.aspectRatio
        }
        guard frameline.height > 0 else { return 0 }
        return frameline.width / frameline.height
    }

    private var widthBinding: Binding<Double> {
        Binding(
            get: { frameline.width },
            set: { newW in
                var fl = frameline
                let rounded = roundToEven(newW)
                fl.width = rounded
                if fl.aspectLocked && effectiveAspectRatio > 0 {
                    fl.height = roundToEven(rounded / effectiveAspectRatio)
                }
                frameline = fl
            }
        )
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { frameline.height },
            set: { newH in
                var fl = frameline
                let rounded = roundToEven(newH)
                fl.height = rounded
                if fl.aspectLocked && effectiveAspectRatio > 0 {
                    fl.width = roundToEven(rounded * effectiveAspectRatio)
                }
                frameline = fl
            }
        )
    }

    private var inheritedProtectionDims: (width: Double, height: Double)? {
        guard let intent = linkedIntent, intent.protectionPercent > 0 else { return nil }
        if let pw = frameline.protectionWidth, let ph = frameline.protectionHeight {
            return (pw, ph)
        }
        return viewModel.effectiveProtection(for: frameline)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Header: color dot, label, aspect ratio, delete
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: frameline.color) ?? .gray)
                    .frame(width: 10, height: 10)

                TextField("Label", text: $frameline.label)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 120)

                Spacer()

                Text(frameline.aspectRatioDescription)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red.opacity(0.7))
            }

            // Framing Intent picker
            HStack(spacing: 4) {
                Text("Intent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("Intent", selection: Binding<UUID?>(
                    get: {
                        guard let id = frameline.linkedIntentID,
                              framingIntents.contains(where: { $0.id == id }) else { return nil as UUID? }
                        return id
                    },
                    set: { (id: UUID?) in
                        var fl = frameline
                        fl.linkedIntentID = id
                        if let id = id, let intent = framingIntents.first(where: { $0.id == id }), intent.aspectRatio > 0 {
                            fl.aspectLocked = true
                            fl.height = roundToEven(fl.width / intent.aspectRatio)
                        }
                        frameline = fl
                    }
                )) {
                    Text("None").tag(nil as UUID?)
                    ForEach(framingIntents) { intent in
                        Text("\(intent.label) (\(intent.aspectRatioDescription))").tag(intent.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            // Inherited intent info banner
            if let intent = linkedIntent {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("Aspect: \(intent.aspectRatioDescription)")
                        .font(.caption2)
                    if intent.protectionPercent > 0 {
                        Text("Protection: \(String(format: "%.1f", intent.protectionPercent))%")
                            .font(.caption2)
                    }
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(4)
                .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            }

            // Dimensions + lock
            HStack(spacing: 4) {
                Text("W")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("W", value: widthBinding, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .font(.caption)
                Text("\u{00D7}")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("H")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("H", value: heightBinding, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .font(.caption)

                Button(action: {
                    var fl = frameline
                    fl.aspectLocked.toggle()
                    if fl.aspectLocked && effectiveAspectRatio > 0 {
                        fl.height = roundToEven(fl.width / effectiveAspectRatio)
                    }
                    frameline = fl
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: frameline.aspectLocked ? "lock.fill" : "lock.open")
                            .font(.caption2)
                        Text(frameline.aspectLocked ? "Locked" : "Free")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(frameline.aspectLocked ? .orange : .secondary)
                }
                .buttonStyle(.borderless)
                .help(
                    frameline.aspectLocked
                        ? "Aspect ratio locked to intent. Click to unlock."
                        : "Aspect ratio unlocked. Click to lock to intent."
                )

                Spacer()
            }

            if frameline.linkedIntentID == nil && !frameline.aspectLocked {
                HStack(spacing: 4) {
                    Text("Intent label")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField("Intent label", text: $frameline.framingIntent)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(maxWidth: 140)
                    Spacer()
                }
            }

            // Protection section
            if let prot = inheritedProtectionDims {
                HStack(spacing: 6) {
                    Text("Protection:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "\(Int(prot.width)) \u{00D7} \(Int(prot.height)) px")
                        .font(.system(.caption2, design: .monospaced))
                    if let intent = linkedIntent {
                        Text("(\(String(format: "%.1f", intent.protectionPercent))% from intent)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }

            DisclosureGroup("Anchor / Alignment") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("H")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("H", selection: $frameline.hAlign) {
                            ForEach(FDLHorizontalAlignment.allCases) { a in
                                Text(a.rawValue.capitalized).tag(a)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    HStack(spacing: 8) {
                        Text("V")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Picker("V", selection: $frameline.vAlign) {
                            ForEach(FDLVerticalAlignment.allCases) { a in
                                Text(a.rawValue.capitalized).tag(a)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    HStack(spacing: 4) {
                        Text("Manual:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("X", value: $frameline.anchorX, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        TextField("Y", value: $frameline.anchorY, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }
                .font(.caption)
                .padding(.vertical, 2)
            }
            .font(.caption)

            if inheritedProtectionDims == nil {
                DisclosureGroup("Manual Protection") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            TextField("W", value: $frameline.protectionWidth, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("\u{00D7}")
                                .foregroundStyle(.secondary)
                            TextField("H", value: $frameline.protectionHeight, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                        HStack(spacing: 4) {
                            Text("Anchor:")
                                .foregroundStyle(.secondary)
                            TextField("X", value: $frameline.protectionAnchorX, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            TextField("Y", value: $frameline.protectionAnchorY, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 2)
                }
                .font(.caption)
            }
        }
        .padding(6)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Color(hex:) Extension

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: h).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
