import SwiftUI

struct ProjectListView: View {
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { viewModel.selectedProject?.id },
                set: { newID in
                    if let id = newID, let project = viewModel.projects.first(where: { $0.id == id }) {
                        viewModel.selectProject(project)
                    }
                }
            )) {
                Section("Projects") {
                    if viewModel.projects.isEmpty {
                        Text("No projects yet")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(viewModel.projects) { project in
                            ProjectRow(project: project)
                                .tag(project.id)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        viewModel.deleteProject(project)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            HStack {
                Button(action: {
                    viewModel.showProjectCreation = true
                }) {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(8)
        }
        .sheet(isPresented: $viewModel.showProjectCreation) {
            ProjectCreationSheet { name, description in
                viewModel.createProject(name: name, description: description)
            }
        }
    }
}

struct ProjectRow: View {
    let project: Project

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name)
                .font(.body)
                .lineLimit(1)
            if let desc = project.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(Self.dateFormatter.string(from: project.updatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
