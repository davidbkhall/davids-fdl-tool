import SwiftUI

struct SidebarView: View {
    @Binding var selectedTool: Tool

    var body: some View {
        VStack(spacing: 0) {
            List(Tool.allCases, selection: $selectedTool) { tool in
                Label {
                    Text(tool.rawValue)
                } icon: {
                    Image(systemName: tool.systemImage)
                        .symbolRenderingMode(.hierarchical)
                }
                .tag(tool)
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
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
