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
    private let projectAssetsTable = Table("project_assets")
    private let assetLinksTable = Table("asset_links")
    private let projectCameraModesTable = Table("project_camera_modes")
    private let migrationStateTable = Table("migration_state")

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

    // project_assets columns
    private let colAssetType = SQLite.Expression<String>("asset_type")
    private let colReferenceID = SQLite.Expression<String?>("reference_id")
    private let colAssetFilePath = SQLite.Expression<String?>("file_path")
    private let colPayloadJSON = SQLite.Expression<String?>("payload_json")

    // asset_links columns
    private let colFromAssetID = SQLite.Expression<String>("from_asset_id")
    private let colToAssetID = SQLite.Expression<String>("to_asset_id")
    private let colLinkType = SQLite.Expression<String>("link_type")

    // project_camera_modes columns
    private let colCameraModelID = SQLite.Expression<String>("camera_model_id")
    private let colCameraModelName = SQLite.Expression<String>("camera_model_name")
    private let colRecordingModeID = SQLite.Expression<String>("recording_mode_id")
    private let colRecordingModeName = SQLite.Expression<String>("recording_mode_name")
    private let colNotes = SQLite.Expression<String?>("notes")

    // migration_state columns
    private let colMigrationKey = SQLite.Expression<String>("key")
    private let colMigrationValue = SQLite.Expression<String>("value")

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
            try backfillProjectGraphIfNeeded()
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

        try db.execute("""
            CREATE TABLE IF NOT EXISTS project_assets (
                id           TEXT PRIMARY KEY,
                project_id   TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                asset_type   TEXT NOT NULL,
                name         TEXT NOT NULL,
                source_tool  TEXT,
                reference_id TEXT,
                file_path    TEXT,
                payload_json TEXT,
                created_at   TEXT NOT NULL,
                updated_at   TEXT NOT NULL
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS asset_links (
                id            TEXT PRIMARY KEY,
                project_id    TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                from_asset_id TEXT NOT NULL REFERENCES project_assets(id) ON DELETE CASCADE,
                to_asset_id   TEXT NOT NULL REFERENCES project_assets(id) ON DELETE CASCADE,
                link_type     TEXT NOT NULL,
                created_at    TEXT NOT NULL,
                UNIQUE(project_id, from_asset_id, to_asset_id, link_type)
            )
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS project_camera_modes (
                id                 TEXT PRIMARY KEY,
                project_id         TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
                camera_model_id    TEXT NOT NULL,
                camera_model_name  TEXT NOT NULL,
                recording_mode_id  TEXT NOT NULL,
                recording_mode_name TEXT NOT NULL,
                source             TEXT,
                notes              TEXT,
                created_at         TEXT NOT NULL,
                updated_at         TEXT NOT NULL,
                UNIQUE(project_id, camera_model_id, recording_mode_id)
            )
        """)

        try db.run(migrationStateTable.create(ifNotExists: true) { t in
            t.column(colMigrationKey, primaryKey: true)
            t.column(colMigrationValue)
        })

        // Indexes
        try db.execute("CREATE INDEX IF NOT EXISTS idx_fdl_project ON fdl_entries(project_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_fdl_camera ON fdl_entries(camera_model)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_assets_project ON project_assets(project_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_assets_type ON project_assets(asset_type)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_links_project ON asset_links(project_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_links_from ON asset_links(from_asset_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_links_to ON asset_links(to_asset_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_project_camera_modes_project ON project_camera_modes(project_id)")
    }

    private func backfillProjectGraphIfNeeded() throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let migrationName = "project_graph_backfill_v1"
        let marker = migrationStateTable.filter(colMigrationKey == migrationName)
        if try db.pluck(marker) != nil {
            return
        }

        // Backfill FDL entries -> project_assets (asset_type = fdl)
        for row in try db.prepare(fdlEntriesTable) {
            let entryID = row[colID]
            let projectID = row[colProjectID]
            let assetID = "asset-fdl-\(entryID)"
            try db.run(projectAssetsTable.insert(or: .ignore,
                colID <- assetID,
                colProjectID <- projectID,
                colAssetType <- ProjectAssetType.fdl.rawValue,
                colName <- row[colName],
                colSourceTool <- row[colSourceTool],
                colReferenceID <- entryID,
                colAssetFilePath <- row[colFilePath],
                colPayloadJSON <- nil,
                colCreatedAt <- row[colCreatedAt],
                colUpdatedAt <- row[colUpdatedAt]
            ))
        }

        // Backfill template assignments -> project_assets (asset_type = template)
        let templateJoin = projectTemplatesTable
            .join(canvasTemplatesTable, on: projectTemplatesTable[colTemplateID] == canvasTemplatesTable[colID])
        for row in try db.prepare(templateJoin) {
            let projectID = row[projectTemplatesTable[colProjectID]]
            let templateID = row[projectTemplatesTable[colTemplateID]]
            let assetID = "asset-template-\(projectID)-\(templateID)"
            try db.run(projectAssetsTable.insert(or: .ignore,
                colID <- assetID,
                colProjectID <- projectID,
                colAssetType <- ProjectAssetType.template.rawValue,
                colName <- row[canvasTemplatesTable[colName]],
                colSourceTool <- row[canvasTemplatesTable[colSource]],
                colReferenceID <- templateID,
                colAssetFilePath <- nil,
                colPayloadJSON <- row[canvasTemplatesTable[colTemplateJSON]],
                colCreatedAt <- row[canvasTemplatesTable[colCreatedAt]],
                colUpdatedAt <- row[canvasTemplatesTable[colUpdatedAt]]
            ))
        }

        try db.run(migrationStateTable.insert(or: .replace,
            colMigrationKey <- migrationName,
            colMigrationValue <- dateFormatter.string(from: Date())
        ))
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

        // Mirror into project asset graph.
        let asset = ProjectAsset(
            id: "asset-fdl-\(entry.id)",
            projectID: entry.projectID,
            assetType: .fdl,
            name: entry.name,
            sourceTool: entry.sourceTool,
            referenceID: entry.id,
            filePath: fileURL.path,
            payloadJSON: nil,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt
        )
        try saveProjectAsset(asset)
    }

    func renameFDLEntry(id: String, projectID: String, newName: String) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = dateFormatter.string(from: Date())

        try db.run(
            fdlEntriesTable
                .filter(colID == id && colProjectID == projectID)
                .update(
                    colName <- trimmed,
                    colUpdatedAt <- now
                )
        )

        let fdlAssetID = "asset-fdl-\(id)"
        try db.run(
            projectAssetsTable
                .filter(colID == fdlAssetID)
                .update(
                    colName <- trimmed,
                    colUpdatedAt <- now
                )
        )

        // Keep chart/reference asset names aligned when the entry originated from charts.
        try db.run(
            projectAssetsTable
                .filter(colProjectID == projectID && colAssetType == ProjectAssetType.chart.rawValue && colReferenceID == id)
                .update(
                    colName <- "\(trimmed) Chart Config",
                    colUpdatedAt <- now
                )
        )

        try db.run(
            projectAssetsTable
                .filter(colProjectID == projectID && colAssetType == ProjectAssetType.referenceImage.rawValue && colReferenceID == id)
                .update(
                    colName <- "\(trimmed) Chart TIFF",
                    colUpdatedAt <- now
                )
        )
    }

    func deleteFDLEntry(id: String, projectID: String) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let row = fdlEntriesTable.filter(colID == id)
        try db.run(row.delete())

        // Remove file
        let fileURL = Self.projectDirectoryURL(projectID: projectID)
            .appendingPathComponent("\(id).fdl.json")
        try? fileManager.removeItem(at: fileURL)

        // Remove graph asset + dangling links for this FDL entry.
        let assetID = "asset-fdl-\(id)"
        try db.run(assetLinksTable.filter((colFromAssetID == assetID) || (colToAssetID == assetID)).delete())
        try db.run(projectAssetsTable.filter(colID == assetID).delete())
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

        // Ensure a template project-asset exists for graph workflows.
        if let templateRow = try db.pluck(canvasTemplatesTable.filter(colID == templateID)) {
            let asset = ProjectAsset(
                id: "asset-template-\(projectID)-\(templateID)",
                projectID: projectID,
                assetType: .template,
                name: templateRow[colName],
                sourceTool: templateRow[colSource],
                referenceID: templateID,
                filePath: nil,
                payloadJSON: templateRow[colTemplateJSON],
                createdAt: dateFormatter.date(from: templateRow[colCreatedAt]) ?? Date(),
                updatedAt: dateFormatter.date(from: templateRow[colUpdatedAt]) ?? Date()
            )
            try saveProjectAsset(asset)
        }
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

    func projectIDsForTemplate(_ templateID: String) throws -> Set<String> {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let query = projectTemplatesTable
            .filter(colTemplateID == templateID)
            .select(colProjectID)
        return Set(try db.prepare(query).map { $0[colProjectID] })
    }

    func removeTemplateFromProject(
        templateID: String, projectID: String
    ) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        try db.run(
            projectTemplatesTable
                .filter(colTemplateID == templateID && colProjectID == projectID)
                .delete()
        )
    }

    // MARK: - Project Asset Graph

    func saveProjectAsset(_ asset: ProjectAsset) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        try db.run(projectAssetsTable.insert(or: .replace,
            colID <- asset.id,
            colProjectID <- asset.projectID,
            colAssetType <- asset.assetType.rawValue,
            colName <- asset.name,
            colSourceTool <- asset.sourceTool,
            colReferenceID <- asset.referenceID,
            colAssetFilePath <- asset.filePath,
            colPayloadJSON <- asset.payloadJSON,
            colCreatedAt <- dateFormatter.string(from: asset.createdAt),
            colUpdatedAt <- dateFormatter.string(from: Date())
        ))
    }

    func projectAssets(
        forProject projectID: String,
        ofType type: ProjectAssetType? = nil
    ) throws -> [ProjectAsset] {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        var query = projectAssetsTable.filter(colProjectID == projectID)
        if let type {
            query = query.filter(colAssetType == type.rawValue)
        }

        return try db.prepare(query.order(colUpdatedAt.desc)).compactMap { row in
            guard let assetType = ProjectAssetType(rawValue: row[colAssetType]) else { return nil }
            return ProjectAsset(
                id: row[colID],
                projectID: row[colProjectID],
                assetType: assetType,
                name: row[colName],
                sourceTool: row[colSourceTool],
                referenceID: row[colReferenceID],
                filePath: row[colAssetFilePath],
                payloadJSON: row[colPayloadJSON],
                createdAt: dateFormatter.date(from: row[colCreatedAt]) ?? Date(),
                updatedAt: dateFormatter.date(from: row[colUpdatedAt]) ?? Date()
            )
        }
    }

    func deleteProjectAsset(id: String) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        try db.run(projectAssetsTable.filter(colID == id).delete())
    }

    @discardableResult
    func linkAssets(_ link: ProjectAssetLink) throws -> ProjectAssetLink {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        try db.run(assetLinksTable.insert(or: .replace,
            colID <- link.id,
            colProjectID <- link.projectID,
            colFromAssetID <- link.fromAssetID,
            colToAssetID <- link.toAssetID,
            colLinkType <- link.linkType.rawValue,
            colCreatedAt <- dateFormatter.string(from: link.createdAt)
        ))
        return link
    }

    func assetLinks(forProject projectID: String) throws -> [ProjectAssetLink] {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let query = assetLinksTable
            .filter(colProjectID == projectID)
            .order(colCreatedAt.desc)
        return try db.prepare(query).compactMap { row in
            guard let linkType = ProjectAssetLinkType(rawValue: row[colLinkType]) else { return nil }
            return ProjectAssetLink(
                id: row[colID],
                projectID: row[colProjectID],
                fromAssetID: row[colFromAssetID],
                toAssetID: row[colToAssetID],
                linkType: linkType,
                createdAt: dateFormatter.date(from: row[colCreatedAt]) ?? Date()
            )
        }
    }

    func deleteAssetLink(id: String) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        try db.run(assetLinksTable.filter(colID == id).delete())
    }

    func assignCameraModeToProject(_ assignment: ProjectCameraModeAssignment) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        try db.run(projectCameraModesTable.insert(or: .replace,
            colID <- assignment.id,
            colProjectID <- assignment.projectID,
            colCameraModelID <- assignment.cameraModelID,
            colCameraModelName <- assignment.cameraModelName,
            colRecordingModeID <- assignment.recordingModeID,
            colRecordingModeName <- assignment.recordingModeName,
            colSource <- assignment.source,
            colNotes <- assignment.notes,
            colCreatedAt <- dateFormatter.string(from: assignment.createdAt),
            colUpdatedAt <- dateFormatter.string(from: Date())
        ))
    }

    func cameraModeAssignments(forProject projectID: String) throws -> [ProjectCameraModeAssignment] {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let query = projectCameraModesTable
            .filter(colProjectID == projectID)
            .order(colUpdatedAt.desc)
        return try db.prepare(query).map { row in
            ProjectCameraModeAssignment(
                id: row[colID],
                projectID: row[colProjectID],
                cameraModelID: row[colCameraModelID],
                cameraModelName: row[colCameraModelName],
                recordingModeID: row[colRecordingModeID],
                recordingModeName: row[colRecordingModeName],
                source: row[colSource],
                notes: row[colNotes],
                createdAt: dateFormatter.date(from: row[colCreatedAt]) ?? Date(),
                updatedAt: dateFormatter.date(from: row[colUpdatedAt]) ?? Date()
            )
        }
    }

    func removeCameraModeAssignment(id: String) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        try db.run(projectCameraModesTable.filter(colID == id).delete())
    }

    func updateCameraModeAssignmentNotes(id: String, notes: String?) throws {
        guard let db = db else { throw LibraryStoreError.databaseNotOpen }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.run(
            projectCameraModesTable.filter(colID == id).update(
                colNotes <- ((trimmed?.isEmpty == true) ? nil : trimmed),
                colUpdatedAt <- dateFormatter.string(from: Date())
            )
        )
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
