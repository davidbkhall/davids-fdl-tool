import Foundation
import SQLite

/// Manages SQLite database and file system storage for FDL projects.
@MainActor
class LibraryStore: ObservableObject {
    @Published var projects: [Project] = []

    private var db: Connection?
    private let fileManager = FileManager.default
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - SQLite Table Definitions

    private let projectsTable = Table("projects")
    private let fdlEntriesTable = Table("fdl_entries")
    private let fdlTagsTable = Table("fdl_tags")
    private let canvasTemplatesTable = Table("canvas_templates")
    private let projectTemplatesTable = Table("project_templates")

    // projects columns
    private let colID = SQLite.Expression<String>("id")
    private let colName = SQLite.Expression<String>("name")
    private let colDescription = SQLite.Expression<String?>("description")
    private let colCreatedAt = SQLite.Expression<String>("created_at")
    private let colUpdatedAt = SQLite.Expression<String>("updated_at")

    // fdl_entries columns
    private let colProjectID = SQLite.Expression<String>("project_id")
    private let colFDLUUID = SQLite.Expression<String>("fdl_uuid")
    private let colFilePath = SQLite.Expression<String>("file_path")
    private let colSourceTool = SQLite.Expression<String?>("source_tool")
    private let colCameraModel = SQLite.Expression<String?>("camera_model")

    // fdl_tags columns
    private let colFDLEntryID = SQLite.Expression<String>("fdl_entry_id")
    private let colTag = SQLite.Expression<String>("tag")

    // canvas_templates columns
    private let colTemplateJSON = SQLite.Expression<String>("template_json")
    private let colSource = SQLite.Expression<String?>("source")

    // project_templates columns
    private let colTemplateID = SQLite.Expression<String>("template_id")
    private let colRole = SQLite.Expression<String?>("role")

    // MARK: - Paths

    static var appSupportURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FDLTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var databaseURL: URL {
        appSupportURL.appendingPathComponent("fdltool.db")
    }

    static func projectDirectoryURL(projectID: String) -> URL {
        appSupportURL
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectID, isDirectory: true)
    }

    static func templateFileURL(templateID: String) -> URL {
        appSupportURL
            .appendingPathComponent("templates", isDirectory: true)
            .appendingPathComponent("\(templateID).json")
    }

    // MARK: - Initialization

    init() {
        do {
            try openDatabase()
            try createTables()
            try loadProjects()
        } catch {
            print("LibraryStore init error: \(error)")
        }
    }

    private func openDatabase() throws {
        let url = Self.databaseURL
        db = try Connection(url.path)
        try db?.execute("PRAGMA foreign_keys = ON")
    }

    private func createTables() throws {
        guard let db = db else { return }

        try db.run(projectsTable.create(ifNotExists: true) { t in
            t.column(colID, primaryKey: true)
            t.column(colName)
            t.column(colDescription)
            t.column(colCreatedAt)
            t.column(colUpdatedAt)
        })

        // Use raw SQL for tables with TEXT foreign keys (SQLite.swift references: only supports Int64)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS fdl_entries (
                id          TEXT PRIMARY KEY,
                project_id  TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                fdl_uuid    TEXT NOT NULL,
                name        TEXT NOT NULL,
                file_path   TEXT NOT NULL,
                source_tool TEXT,
                camera_model TEXT,
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS fdl_tags (
                fdl_entry_id TEXT NOT NULL REFERENCES fdl_entries(id) ON DELETE CASCADE,
                tag          TEXT NOT NULL,
                PRIMARY KEY (fdl_entry_id, tag)
            )
        """)

        try db.run(canvasTemplatesTable.create(ifNotExists: true) { t in
            t.column(colID, primaryKey: true)
            t.column(colName)
            t.column(colDescription)
            t.column(colTemplateJSON)
            t.column(colSource)
            t.column(colCreatedAt)
            t.column(colUpdatedAt)
        })

        try db.execute("""
            CREATE TABLE IF NOT EXISTS project_templates (
                project_id  TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                template_id TEXT NOT NULL REFERENCES canvas_templates(id) ON DELETE CASCADE,
                role        TEXT,
                PRIMARY KEY (project_id, template_id)
            )
        """)

        // Indexes
        try db.execute("CREATE INDEX IF NOT EXISTS idx_fdl_project ON fdl_entries(project_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_fdl_camera ON fdl_entries(camera_model)")
    }

    // MARK: - Project CRUD

    private func loadProjects() throws {
        guard let db = db else { return }
        projects = try db.prepare(projectsTable.order(colUpdatedAt.desc)).map { row in
            Project(
                id: row[colID],
                name: row[colName],
                description: row[colDescription],
                createdAt: dateFormatter.date(from: row[colCreatedAt]) ?? Date(),
                updatedAt: dateFormatter.date(from: row[colUpdatedAt]) ?? Date()
            )
        }
    }

    func createProject(name: String, description: String? = nil) throws -> Project {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let project = Project(name: name, description: description)

        try db.run(projectsTable.insert(
            colID <- project.id,
            colName <- project.name,
            colDescription <- project.description,
            colCreatedAt <- dateFormatter.string(from: project.createdAt),
            colUpdatedAt <- dateFormatter.string(from: project.updatedAt)
        ))

        // Create project directory
        let dir = Self.projectDirectoryURL(projectID: project.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        projects.insert(project, at: 0)
        return project
    }

    func deleteProject(id: String) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let project = projectsTable.filter(colID == id)
        try db.run(project.delete())

        // Remove project directory
        let dir = Self.projectDirectoryURL(projectID: id)
        try? fileManager.removeItem(at: dir)

        projects.removeAll { $0.id == id }
    }

    func updateProject(_ project: Project) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let row = projectsTable.filter(colID == project.id)
        try db.run(row.update(
            colName <- project.name,
            colDescription <- project.description,
            colUpdatedAt <- dateFormatter.string(from: Date())
        ))
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        }
    }

    // MARK: - FDL Entry CRUD

    func fdlEntries(forProject projectID: String) throws -> [FDLEntry] {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let query = fdlEntriesTable.filter(colProjectID == projectID).order(colCreatedAt.desc)
        return try db.prepare(query).map { row in
            let entryID = row[colID]
            let tags = try db.prepare(fdlTagsTable.filter(colFDLEntryID == entryID)).map { $0[colTag] }
            return FDLEntry(
                id: entryID,
                projectID: row[colProjectID],
                fdlUUID: row[colFDLUUID],
                name: row[colName],
                filePath: row[colFilePath],
                sourceTool: row[colSourceTool],
                cameraModel: row[colCameraModel],
                tags: tags,
                createdAt: dateFormatter.date(from: row[colCreatedAt]) ?? Date(),
                updatedAt: dateFormatter.date(from: row[colUpdatedAt]) ?? Date()
            )
        }
    }

    func addFDLEntry(_ entry: FDLEntry, jsonData: Data) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }

        try db.run(fdlEntriesTable.insert(
            colID <- entry.id,
            colProjectID <- entry.projectID,
            colFDLUUID <- entry.fdlUUID,
            colName <- entry.name,
            colFilePath <- entry.filePath,
            colSourceTool <- entry.sourceTool,
            colCameraModel <- entry.cameraModel,
            colCreatedAt <- dateFormatter.string(from: entry.createdAt),
            colUpdatedAt <- dateFormatter.string(from: entry.updatedAt)
        ))

        // Insert tags
        for tag in entry.tags {
            try db.run(fdlTagsTable.insert(
                colFDLEntryID <- entry.id,
                colTag <- tag
            ))
        }

        // Write FDL file
        let dir = Self.projectDirectoryURL(projectID: entry.projectID)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(entry.id).fdl.json")
        try jsonData.write(to: fileURL)
    }

    func deleteFDLEntry(id: String, projectID: String) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let row = fdlEntriesTable.filter(colID == id)
        try db.run(row.delete())

        // Remove file
        let fileURL = Self.projectDirectoryURL(projectID: projectID)
            .appendingPathComponent("\(id).fdl.json")
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: - Canvas Template CRUD

    func allCanvasTemplates() throws -> [CanvasTemplate] {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        return try db.prepare(canvasTemplatesTable.order(colUpdatedAt.desc)).map { row in
            CanvasTemplate(
                id: row[colID],
                name: row[colName],
                description: row[colDescription],
                templateJSON: row[colTemplateJSON],
                source: row[colSource],
                createdAt: dateFormatter.date(from: row[colCreatedAt]) ?? Date(),
                updatedAt: dateFormatter.date(from: row[colUpdatedAt]) ?? Date()
            )
        }
    }

    func saveCanvasTemplate(_ template: CanvasTemplate) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }

        try db.run(canvasTemplatesTable.insert(or: .replace,
            colID <- template.id,
            colName <- template.name,
            colDescription <- template.description,
            colTemplateJSON <- template.templateJSON,
            colSource <- template.source,
            colCreatedAt <- dateFormatter.string(from: template.createdAt),
            colUpdatedAt <- dateFormatter.string(from: Date())
        ))

        // Also write to templates directory
        let dir = Self.appSupportURL.appendingPathComponent("templates", isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(template.id).json")
        try template.templateJSON.data(using: .utf8)?.write(to: fileURL)
    }

    func deleteCanvasTemplate(id: String) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        try db.run(canvasTemplatesTable.filter(colID == id).delete())
        try? fileManager.removeItem(at: Self.templateFileURL(templateID: id))
    }

    // MARK: - Project-Template Association

    func assignTemplate(templateID: String, toProject projectID: String, role: String? = nil) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        try db.run(projectTemplatesTable.insert(or: .replace,
            colProjectID <- projectID,
            colTemplateID <- templateID,
            colRole <- role
        ))
    }

    func templatesForProject(_ projectID: String) throws -> [(CanvasTemplate, String?)] {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let query = projectTemplatesTable
            .join(canvasTemplatesTable, on: colTemplateID == canvasTemplatesTable[colID])
            .filter(projectTemplatesTable[colProjectID] == projectID)

        return try db.prepare(query).map { row in
            let template = CanvasTemplate(
                id: row[canvasTemplatesTable[colID]],
                name: row[canvasTemplatesTable[colName]],
                description: row[canvasTemplatesTable[colDescription]],
                templateJSON: row[canvasTemplatesTable[colTemplateJSON]],
                source: row[canvasTemplatesTable[colSource]],
                createdAt: dateFormatter.date(from: row[canvasTemplatesTable[colCreatedAt]]) ?? Date(),
                updatedAt: dateFormatter.date(from: row[canvasTemplatesTable[colUpdatedAt]]) ?? Date()
            )
            let role = row[projectTemplatesTable[colRole]]
            return (template, role)
        }
    }
}

enum LibraryStoreError: Error, LocalizedError {
    case databaseNotOpen
    case projectNotFound(String)
    case entryNotFound(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotOpen: return "Database is not open"
        case .projectNotFound(let id): return "Project not found: \(id)"
        case .entryNotFound(let id): return "FDL entry not found: \(id)"
        }
    }
}
