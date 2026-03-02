import SwiftUI

struct ChartGeneratorView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HSplitView {
            // Left: Config panel
            ChartConfigPanel(
                viewModel: appState.chartGeneratorViewModel,
                cameraDB: appState.cameraDBStore
            )
            .frame(minWidth: 260, idealWidth: 310, maxWidth: 380)

            // Center/Right: Canvas + toolbar
            VStack(spacing: 0) {
                // Action toolbar
                HStack {
                    Spacer()

                    Button(action: { appState.chartGeneratorViewModel.showExportSheet = true }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(appState.chartGeneratorViewModel.framelines.isEmpty)

                    Button(action: { appState.chartGeneratorViewModel.showSaveToLibrary = true }) {
                        Label("Save to Library", systemImage: "folder.badge.plus")
                    }
                    .disabled(appState.chartGeneratorViewModel.framelines.isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                ChartCanvasView(viewModel: appState.chartGeneratorViewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Framing Chart Generator")
        .sheet(isPresented: $appState.chartGeneratorViewModel.showExportSheet) {
            ChartExportSheet(viewModel: appState.chartGeneratorViewModel)
        }
        .sheet(isPresented: $appState.chartGeneratorViewModel.showSaveToLibrary) {
            SaveToLibrarySheet(
                viewModel: appState.chartGeneratorViewModel,
                projects: appState.libraryViewModel.projects
            )
        }
        .alert("Error", isPresented: Binding(
            get: { appState.chartGeneratorViewModel.errorMessage != nil },
            set: { if !$0 { appState.chartGeneratorViewModel.errorMessage = nil } }
        )) {
            Button("OK") { appState.chartGeneratorViewModel.errorMessage = nil }
        } message: {
            Text(appState.chartGeneratorViewModel.errorMessage ?? "")
        }
    }
}
