import SwiftUI

struct SidebarView: View {
    @Binding var selectedTool: Tool

    var body: some View {
        VStack(spacing: 0) {
            List(Tool.allCases, selection: $selectedTool) { tool in
                Label(tool.rawValue, systemImage: tool.systemImage)
                    .tag(tool)
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Spacer()
                SettingsLink {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        .navigationTitle("FDL Tool")
    }
}
