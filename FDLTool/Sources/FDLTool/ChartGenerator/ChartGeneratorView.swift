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
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.framelines.isEmpty)

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
        .sheet(isPresented: $viewModel.showExportSheet) {
            ChartExportSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showSaveToLibrary) {
            SaveToLibrarySheet(
                viewModel: viewModel,
                projects: appState.libraryViewModel.projects
            )
        }
        .onChange(of: viewModel.showExportSheet) { _, isPresented in
            if !isPresented {
                viewModel.runPendingExportRequestIfNeeded()
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
