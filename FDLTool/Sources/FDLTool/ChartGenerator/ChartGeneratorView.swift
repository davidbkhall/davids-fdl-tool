import SwiftUI

struct ChartGeneratorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ChartGeneratorContent(
            viewModel: appState.chartGeneratorViewModel,
            appState: appState
        )
    }
}

/// Inner view that directly observes the viewModel so `.disabled()`, sheets, etc.
/// react to `@Published` property changes (avoids nested-ObservableObject issue).
private struct ChartGeneratorContent: View {
    @ObservedObject var viewModel: ChartGeneratorViewModel
    @ObservedObject var appState: AppState

    var body: some View {
        HSplitView {
            ChartConfigPanel(
                viewModel: viewModel,
                cameraDB: appState.cameraDBStore
            )
            .frame(minWidth: 260, idealWidth: 310, maxWidth: 380)

            VStack(spacing: 0) {
                HStack {
                    Text("\(viewModel.framelines.count) frameline\(viewModel.framelines.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(action: {
                        let doc = viewModel.buildLocalFDLDocument(
                            creator: appState.defaultCreator
                        )
                        appState.pendingFDLDocument = doc
                        appState.pendingFDLFileName = "\(viewModel.chartTitle).fdl"
                        appState.selectedTool = .viewer
                    }) {
                        Label("Open in Framing Workspace", systemImage: "eye")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.framelines.isEmpty)

                    Button(action: { viewModel.showExportSheet = true }) {
                        if viewModel.isExporting {
                            Label("Exporting…", systemImage: "clock.arrow.circlepath")
                        } else {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.framelines.isEmpty || viewModel.isExporting)

                    Button(action: { viewModel.copyExportDiagnostics() }) {
                        Label("Copy Diagnostics", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: { viewModel.showSaveToLibrary = true }) {
                        Label("Save to Library", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.framelines.isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                ChartCanvasView(viewModel: viewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Framing Chart Generator")
        .sheet(isPresented: $viewModel.showExportSheet, onDismiss: {
            viewModel.runPendingExportRequestIfNeeded()
        }) {
            ChartExportSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showSaveToLibrary) {
            SaveToLibrarySheet(
                viewModel: viewModel,
                projects: appState.libraryViewModel.projects
            )
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Export Complete", isPresented: Binding(
            get: { viewModel.exportStatusMessage != nil },
            set: { if !$0 { viewModel.exportStatusMessage = nil } }
        )) {
            Button("OK") { viewModel.exportStatusMessage = nil }
        } message: {
            Text(viewModel.exportStatusMessage ?? "")
        }
        .alert("Saved to Library", isPresented: Binding(
            get: { viewModel.saveStatusMessage != nil },
            set: { if !$0 { viewModel.saveStatusMessage = nil } }
        )) {
            Button("OK") { viewModel.saveStatusMessage = nil }
        } message: {
            Text(viewModel.saveStatusMessage ?? "")
        }
        .alert("Diagnostics Copied", isPresented: Binding(
            get: { viewModel.diagnosticsStatusMessage != nil },
            set: { if !$0 { viewModel.diagnosticsStatusMessage = nil } }
        )) {
            Button("OK") { viewModel.diagnosticsStatusMessage = nil }
        } message: {
            Text(viewModel.diagnosticsStatusMessage ?? "")
        }
        .onChange(of: viewModel.exportStatusMessage) { _, newValue in
            guard newValue != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if viewModel.exportStatusMessage != nil {
                    viewModel.exportStatusMessage = nil
                }
            }
        }
        .onChange(of: viewModel.saveStatusMessage) { _, newValue in
            guard newValue != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if viewModel.saveStatusMessage != nil {
                    viewModel.saveStatusMessage = nil
                }
            }
        }
        .onChange(of: viewModel.diagnosticsStatusMessage) { _, newValue in
            guard newValue != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                if viewModel.diagnosticsStatusMessage != nil {
                    viewModel.diagnosticsStatusMessage = nil
                }
            }
        }
    }
}
