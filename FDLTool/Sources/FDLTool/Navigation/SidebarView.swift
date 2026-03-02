import SwiftUI

struct SidebarView: View {
    @Binding var selectedTool: Tool
    var bridgeStatus: AppState.BridgeStatus = .stopped
    var cameraCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            List(Tool.allCases, selection: $selectedTool) { tool in
                Label(tool.rawValue, systemImage: tool.systemImage)
                    .tag(tool)
            }
            .listStyle(.sidebar)

            Divider()

            // Status footer
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(bridgeStatusColor)
                        .frame(width: 8, height: 8)
                    Text("Python: \(bridgeStatus.rawValue)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if cameraCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(cameraCount) cameras")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        .navigationTitle("FDL Tool")
    }

    private var bridgeStatusColor: Color {
        switch bridgeStatus {
        case .stopped: return .gray
        case .starting: return .orange
        case .running: return .green
        case .error: return .red
        }
    }
}
