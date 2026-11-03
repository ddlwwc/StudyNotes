import Foundation
import SQLite3

struct SearchableDocument: Sendable {
    let materialID: UUID
    let knowledgeBaseID: UUID?
    let kind: StudyMaterialKind
    let title: String
    let body: String
    let annotations: String
    let ai: String
    let tags: [String]
    let updatedAt: Date
}

actor StudyNotesSearchIndex {
    private let databaseURL: URL
    private var database: OpaquePointer?

    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    func search(
        query: String,
        filter: SearchFilter,
        documents: [SearchableDocument]
    ) throws -> [SearchHit] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return []
        }
        try ensureDatabase()
        try synchronizeIfNeeded(documents)

        do {
            return try executeSearch(
                query: normalizedQuery,
                filter: filter
            )
        } catch {
            try resetDatabase()
            try synchronizeIfNeeded(documents, force: true)
            return try executeSearch(query: normalizedQuery, filter: filter)
        }
    }

    private func ensureDatabase() throws {
        if database != nil {
            return
        }
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: databaseURL.path) {
            guard sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK else {
                database = nil
                throw SearchIndexError.openFailed
            }
            try createSchema()
            return
        }

        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else {
            database = nil
            try resetDatabase()
            return
        }
        do {
            try verifySchema()
        } catch {
            try resetDatabase()
        }
    }

    private func resetDatabase() throws {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
        try? FileManager.default.removeItem(at: databaseURL)
        try? FileManager.default.removeItem(
            atPath: databaseURL.path + "-wal"
        )
        try? FileManager.default.removeItem(
            atPath: databaseURL.path + "-shm"
        )
        try ensureDatabase()
    }

    private func createSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS documents (
              material_id TEXT PRIMARY KEY NOT NULL,
              knowledge_base_id TEXT,
              kind TEXT NOT NULL,
              title TEXT NOT NULL,
              body TEXT NOT NULL,
              annotations TEXT NOT NULL,
              ai TEXT NOT NULL,
              tags TEXT NOT NULL,
              updated_at REAL NOT NULL
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
              material_id UNINDEXED,
              title,
              body,
              annotations,
              ai,
              tokenize='trigram'
            );
            CREATE TABLE IF NOT EXISTS metadata (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT NOT NULL
            );
            """
        )
    }

    private func verifySchema() throws {
        let statement = try prepare(
            "SELECT count(*) FROM sqlite_master WHERE type IN ('table','view') AND name IN ('documents','documents_fts','metadata');"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SearchIndexError.queryFailed("无法读取索引结构。")
        }
        guard sqlite3_column_int(statement, 0) == 3 else {
            throw SearchIndexError.corruptIndex
        }
    }

    private func synchronizeIfNeeded(
        _ documents: [SearchableDocument],
        force: Bool = false
    ) throws {
        let signature = documents
            .sorted { $0.materialID.uuidString < $1.materialID.uuidString }
            .map {
                [
                    $0.materialID.uuidString,
                    $0.title,
                    String($0.updatedAt.timeIntervalSince1970),
                    ContentFingerprint.sha256($0.body + $0.annotations + $0.ai)
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
        let digest = ContentFingerprint.sha256(signature)
        if !force, try metadataValue(for: "snapshot") == digest {
            return
        }

        try execute("BEGIN IMMEDIATE;")
        do {
            try execute("DELETE FROM documents; DELETE FROM documents_fts;")
            for document in documents {
                let insertDocument = try prepare(
                    """
                    INSERT INTO documents
                      (material_id, knowledge_base_id, kind, title, body, annotations, ai, tags, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """
                )
                defer { sqlite3_finalize(insertDocument) }
                bind(document.materialID.uuidString, to: 1, in: insertDocument)
                bind(document.knowledgeBaseID?.uuidString, to: 2, in: insertDocument)
                bind(document.kind.rawValue, to: 3, in: insertDocument)
                bind(document.title, to: 4, in: insertDocument)
                bind(document.body, to: 5, in: insertDocument)
                bind(document.annotations, to: 6, in: insertDocument)
                bind(document.ai, to: 7, in: insertDocument)
                bind(document.tags.joined(separator: "\n"), to: 8, in: insertDocument)
                sqlite3_bind_double(insertDocument, 9, document.updatedAt.timeIntervalSince1970)
                guard sqlite3_step(insertDocument) == SQLITE_DONE else {
                    throw SearchIndexError.queryFailed(lastError)
                }

                let insertSearch = try prepare(
                    """
                    INSERT INTO documents_fts
                      (material_id, title, body, annotations, ai)
                    VALUES (?, ?, ?, ?, ?);
                    """
                )
                defer { sqlite3_finalize(insertSearch) }
                bind(document.materialID.uuidString, to: 1, in: insertSearch)
                bind(document.title, to: 2, in: insertSearch)
                bind(document.body, to: 3, in: insertSearch)
                bind(document.annotations, to: 4, in: insertSearch)
                bind(document.ai, to: 5, in: insertSearch)
                guard sqlite3_step(insertSearch) == SQLITE_DONE else {
                    throw SearchIndexError.queryFailed(lastError)
                }
            }
            try setMetadata(key: "snapshot", value: digest)
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func executeSearch(
        query: String,
        filter: SearchFilter
    ) throws -> [SearchHit] {
        let useFallback = query.count < 3
        let sql: String
        if useFallback {
            sql = """
            SELECT d.material_id, d.knowledge_base_id, d.kind, d.title, d.body,
                   d.annotations, d.ai, d.tags, d.updated_at
            FROM documents d
            WHERE (
              instr(lower(d.title), lower(?)) > 0 OR
              instr(lower(d.body), lower(?)) > 0 OR
              instr(lower(d.annotations), lower(?)) > 0 OR
              instr(lower(d.ai), lower(?)) > 0
            )
            AND \(filterClause(filter, alias: "d"))
            ORDER BY d.updated_at DESC
            LIMIT 100;
            """
        } else {
            sql = """
            SELECT d.material_id, d.knowledge_base_id, d.kind, d.title, d.body,
                   d.annotations, d.ai, d.tags, d.updated_at
            FROM documents_fts f
            JOIN documents d ON d.material_id = f.material_id
            WHERE documents_fts MATCH ?
            AND \(filterClause(filter, alias: "d"))
            ORDER BY bm25(documents_fts), d.updated_at DESC
            LIMIT 100;
            """
        }

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var bindingIndex: Int32 = 1
        let matcher = useFallback ? query : "\"\(query.replacingOccurrences(of: "\"", with: "\"\""))\""
        if useFallback {
            for _ in 0..<4 {
                bind(query, to: bindingIndex, in: statement)
                bindingIndex += 1
            }
        } else {
            bind(matcher, to: bindingIndex, in: statement)
            bindingIndex += 1
        }
        try bindFilter(filter, startingAt: &bindingIndex, to: statement)

        var hits: [SearchHit] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                break
            }
            guard step == SQLITE_ROW else {
                throw SearchIndexError.queryFailed(lastError)
            }
            let idString = column(statement, 0)
            guard let id = UUID(uuidString: idString),
                  let kind = StudyMaterialKind(rawValue: column(statement, 2)) else {
                continue
            }
            let title = column(statement, 3)
            let body = column(statement, 4)
            let annotations = column(statement, 5)
            let ai = column(statement, 6)
            let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 8))
            let match = matchingLayer(
                query: query,
                title: title,
                body: body,
                annotations: annotations,
                ai: ai
            )
            hits.append(
                SearchHit(
                    materialID: id,
                    title: title,
                    knowledgeBaseID: UUID(uuidString: column(statement, 1)),
                    kind: kind,
                    snippet: snippet(
                        in: match.text,
                        query: query,
                        layer: match.layer
                    ),
                    matchedLayer: match.layer,
                    updatedAt: updatedAt
                )
            )
        }
        return hits
    }

    private func bindFilter(
        _ filter: SearchFilter,
        startingAt index: inout Int32,
        to statement: OpaquePointer
    ) throws {
        if let knowledgeBaseID = filter.knowledgeBaseID {
            bind(knowledgeBaseID.uuidString, to: index, in: statement)
            index += 1
        }
        if let kind = filter.kind {
            bind(kind.rawValue, to: index, in: statement)
            index += 1
        }
        if let tag = filter.tag {
            bind(tag, to: index, in: statement)
            index += 1
        }
        if let updatedAfter = filter.updatedAfter {
            sqlite3_bind_double(statement, index, updatedAfter.timeIntervalSince1970)
            index += 1
        }
    }

    private func filterClause(_ filter: SearchFilter, alias: String) -> String {
        var clauses = ["1 = 1"]
        if filter.knowledgeBaseID != nil {
            clauses.append("\(alias).knowledge_base_id = ?")
        }
        if filter.kind != nil {
            clauses.append("\(alias).kind = ?")
        }
        if filter.tag != nil {
            clauses.append(
                "instr(char(10) || \(alias).tags || char(10), char(10) || ? || char(10)) > 0"
            )
        }
        if filter.updatedAfter != nil {
            clauses.append("\(alias).updated_at >= ?")
        }
        return clauses.joined(separator: " AND ")
    }

    private func matchingLayer(
        query: String,
        title: String,
        body: String,
        annotations: String,
        ai: String
    ) -> (layer: SearchMatchLayer, text: String) {
        let candidate: [(SearchMatchLayer, String)] = [
            (.title, title),
            (.body, body),
            (.annotation, annotations),
            (.ai, ai)
        ]
        return candidate.first {
            $0.1.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }.map { ($0.0, $0.1) } ?? (.body, body)
    }

    private func snippet(
        in text: String,
        query: String,
        layer: SearchMatchLayer
    ) -> String {
        let nsText = text as NSString
        let range = nsText.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        guard range.location != NSNotFound else {
            return "\(layerLabel(layer)) · \(String(text.prefix(96)))"
        }
        let start = max(0, range.location - 36)
        let end = min(nsText.length, NSMaxRange(range) + 58)
        let fragment = nsText.substring(with: NSRange(location: start, length: end - start))
        return "\(layerLabel(layer)) · \(fragment.replacingOccurrences(of: "\n", with: " "))"
    }

    private func layerLabel(_ layer: SearchMatchLayer) -> String {
        switch layer {
        case .title:
            "标题"
        case .body:
            "正文"
        case .annotation:
            "标注"
        case .ai:
            "AI"
        }
    }

    private func metadataValue(for key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM metadata WHERE key = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        bind(key, to: 1, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return column(statement, 0)
    }

    private func setMetadata(key: String, value: String) throws {
        let statement = try prepare(
            "INSERT INTO metadata (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        )
        defer { sqlite3_finalize(statement) }
        bind(key, to: 1, in: statement)
        bind(value, to: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SearchIndexError.queryFailed(lastError)
        }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SearchIndexError.queryFailed(lastError)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SearchIndexError.queryFailed(lastError)
        }
        return statement
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(
            statement,
            index,
            value,
            -1,
            unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        )
    }

    private func column(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }

    private var lastError: String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "索引未打开。"
    }
}

enum SearchIndexError: Error, Equatable, Sendable, LocalizedError {
    case openFailed
    case corruptIndex
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed:
            "无法打开本地搜索索引。"
        case .corruptIndex:
            "本地搜索索引已损坏，正在尝试重建。"
        case .queryFailed(let message):
            "搜索索引查询失败：\(message)"
        }
    }
}
