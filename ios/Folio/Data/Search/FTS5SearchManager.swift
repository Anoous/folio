import Foundation
import SQLite3
import SwiftData

/// SQLITE_TRANSIENT tells SQLite to copy the bound data immediately.
/// The C macro is `((sqlite3_destructor_type)-1)` which isn't directly
/// expressible in Swift. This constant keeps the cast in one auditable place.
private let SQLITE_TRANSIENT_SWIFT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class FTS5SearchManager: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.folio.fts5", qos: .userInitiated)

    struct SearchResult {
        let articleID: UUID
        let rank: Double
        var highlightedTitle: String?
        var snippet: String?
    }

    init(databasePath: String) throws {
        guard sqlite3_open(databasePath, &db) == SQLITE_OK else {
            throw FTS5Error.cannotOpenDatabase
        }
        try createFTS5Table()
    }

    init(inMemory: Bool = true) throws {
        let path: String
        if inMemory {
            path = ":memory:"
        } else {
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            path = cacheDir.appendingPathComponent("folio_fts5.db").path
        }
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw FTS5Error.cannotOpenDatabase
        }
        try createFTS5Table()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Table Management

    private func createFTS5Table() throws {
        let sql = """
        CREATE VIRTUAL TABLE IF NOT EXISTS article_fts USING fts5(
            article_id UNINDEXED,
            title,
            content,
            summary,
            tags,
            author,
            site_name,
            tokenize='unicode61 remove_diacritics 2'
        );
        """
        try execute(sql)
    }

    // MARK: - Index Operations

    func indexArticle(_ article: Article) throws {
        try queue.sync {
            let sql = """
            INSERT INTO article_fts(article_id, title, content, summary, tags, author, site_name)
            VALUES(?, ?, ?, ?, ?, ?, ?);
            """
            let tagNames = article.tags.map(\.name).joined(separator: " ")
            try execute(sql, bindings: [
                article.id.uuidString,
                article.title ?? "",
                article.markdownContent ?? "",
                article.summary ?? "",
                tagNames,
                article.author ?? "",
                article.siteName ?? "",
            ])
        }
    }

    func removeFromIndex(articleID: UUID) throws {
        try queue.sync {
            let sql = "DELETE FROM article_fts WHERE article_id = ?;"
            try execute(sql, bindings: [articleID.uuidString])
        }
    }

    func updateIndex(_ article: Article) throws {
        try queue.sync {
            let sql = "DELETE FROM article_fts WHERE article_id = ?;"
            try execute(sql, bindings: [article.id.uuidString])
            let insertSQL = """
            INSERT INTO article_fts(article_id, title, content, summary, tags, author, site_name)
            VALUES(?, ?, ?, ?, ?, ?, ?);
            """
            let tagNames = article.tags.map(\.name).joined(separator: " ")
            try execute(insertSQL, bindings: [
                article.id.uuidString,
                article.title ?? "",
                article.markdownContent ?? "",
                article.summary ?? "",
                tagNames,
                article.author ?? "",
                article.siteName ?? "",
            ])
        }
    }

    func rebuildAll(articles: [Article]) throws {
        try queue.sync {
            try execute("DELETE FROM article_fts;")
            for article in articles {
                let sql = """
                INSERT INTO article_fts(article_id, title, content, summary, tags, author, site_name)
                VALUES(?, ?, ?, ?, ?, ?, ?);
                """
                let tagNames = article.tags.map(\.name).joined(separator: " ")
                try execute(sql, bindings: [
                    article.id.uuidString,
                    article.title ?? "",
                    article.markdownContent ?? "",
                    article.summary ?? "",
                    tagNames,
                    article.author ?? "",
                    article.siteName ?? "",
                ])
            }
        }
    }

    // MARK: - Helpers (Query Safety)

    private static func sanitizeFTSQuery(_ query: String) -> String {
        // Remove FTS5 special syntax characters
        let specialChars = CharacterSet(charactersIn: "\"()*:^{}-+")
        let cleaned = query.unicodeScalars.filter { !specialChars.contains($0) }
        var result = String(cleaned)
        // Remove FTS5 keywords that could alter query semantics
        for keyword in ["NOT", "AND", "OR", "NEAR"] {
            result = result.replacingOccurrences(of: " \(keyword) ", with: " ")
        }
        return result
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    // MARK: - Search

    func search(query: String, limit: Int = 20) throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let sanitized = Self.sanitizeFTSQuery(query)
        let ftsQuery = sanitized.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
        guard !ftsQuery.isEmpty else { return [] }

        return try queue.sync {
            let sql = """
            SELECT article_id,
                   bm25(article_fts, 0.0, 10.0, 5.0, 3.0, 2.0, 1.0, 1.0) as rank
            FROM article_fts
            WHERE article_fts MATCH ?
            ORDER BY rank
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw FTS5Error.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT_SWIFT)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var results: [SearchResult] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idString = columnText(stmt, 0)
                let rank = sqlite3_column_double(stmt, 1)
                if let uuid = UUID(uuidString: idString) {
                    results.append(SearchResult(articleID: uuid, rank: rank))
                }
            }
            return results
        }
    }

    func searchWithHighlight(query: String, limit: Int = 20) throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let sanitized = Self.sanitizeFTSQuery(query)
        let ftsQuery = sanitized.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
        guard !ftsQuery.isEmpty else { return [] }

        return try queue.sync {
            let sql = """
            SELECT article_id,
                   bm25(article_fts, 0.0, 10.0, 5.0, 3.0, 2.0, 1.0, 1.0) as rank,
                   highlight(article_fts, 1, '<mark>', '</mark>') as hl_title
            FROM article_fts
            WHERE article_fts MATCH ?
            ORDER BY rank
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw FTS5Error.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT_SWIFT)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var results: [SearchResult] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idString = columnText(stmt, 0)
                let rank = sqlite3_column_double(stmt, 1)
                let hlTitle = columnText(stmt, 2)
                if let uuid = UUID(uuidString: idString) {
                    var result = SearchResult(articleID: uuid, rank: rank)
                    result.highlightedTitle = hlTitle
                    results.append(result)
                }
            }
            return results
        }
    }

    func searchWithSnippet(query: String, limit: Int = 20) throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let sanitized = Self.sanitizeFTSQuery(query)
        let ftsQuery = sanitized.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
        guard !ftsQuery.isEmpty else { return [] }

        return try queue.sync {
            let sql = """
            SELECT article_id,
                   bm25(article_fts, 0.0, 10.0, 5.0, 3.0, 2.0, 1.0, 1.0) as rank,
                   snippet(article_fts, 2, '<mark>', '</mark>', '...', 20) as snip
            FROM article_fts
            WHERE article_fts MATCH ?
            ORDER BY rank
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw FTS5Error.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT_SWIFT)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            var results: [SearchResult] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let idString = columnText(stmt, 0)
                let rank = sqlite3_column_double(stmt, 1)
                let snip = columnText(stmt, 2)
                if let uuid = UUID(uuidString: idString) {
                    var result = SearchResult(articleID: uuid, rank: rank)
                    result.snippet = snip
                    results.append(result)
                }
            }
            return results
        }
    }

    // MARK: - Helpers

    private func execute(_ sql: String, bindings: [String] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw FTS5Error.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        for (i, value) in bindings.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), value, -1, SQLITE_TRANSIENT_SWIFT)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw FTS5Error.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func rowCount() throws -> Int {
        let sql = "SELECT count(*) FROM article_fts;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw FTS5Error.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
        return Int(sqlite3_column_int(stmt, 0))
    }
}

enum FTS5Error: Error {
    case cannotOpenDatabase
    case queryFailed(String)
}
