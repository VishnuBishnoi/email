import Foundation
import SQLite3

// MARK: - Supporting Types

/// Result returned from an FTS5 full-text search query.
///
/// Contains the matched email's identifiers and BM25 relevance score.
///
/// Spec ref: FR-SEARCH-06
public struct FTS5SearchResult: Sendable {
    /// The unique identifier of the matched email.
    public let emailId: String
    /// The account that owns the matched email.
    public let accountId: String
    /// BM25 relevance score. Lower values indicate better matches.
    public let rank: Double
}

/// Columns in the FTS5 `email_fts` virtual table.
///
/// Raw values correspond to column indices in the table definition.
public enum FTS5Column: Int, Sendable {
    case emailId = 0
    case accountId = 1
    case subject = 2
    case body = 3
    case senderName = 4
    case senderEmail = 5
}

/// Errors originating from the FTS5 search database.
public enum FTS5Error: Error, Sendable {
    /// An operation was attempted while the database is closed.
    case databaseNotOpen
    /// A raw SQLite error with the status code and human-readable message.
    case sqliteError(code: Int32, message: String)
    /// The database file is corrupt and has been deleted for recreation.
    case corruptDatabase
    /// The search query is empty or otherwise invalid after sanitization.
    case invalidQuery
}

// MARK: - FTS5Manager

/// Actor that manages an FTS5 full-text search index backed by a
/// standalone SQLite database (`search.sqlite`).
///
/// This actor is intentionally **not** `@MainActor` -- all I/O runs on
/// a background executor so the main thread is never blocked.
///
/// The FTS5 virtual table uses `unicode61 remove_diacritics 2` tokenization
/// for broad language support with diacritic-insensitive matching.
///
/// Spec ref: FR-SEARCH-06, AC-S-06
public actor FTS5Manager {

    // MARK: - State

    /// Raw SQLite database handle. `nil` when closed.
    ///
    /// Marked `nonisolated(unsafe)` so that `deinit` (which is nonisolated
    /// in actors) can close the database without a Sendable violation.
    /// Safety: `db` is only mutated within actor-isolated methods, and
    /// `deinit` runs after all other references are released.
    private nonisolated(unsafe) var db: OpaquePointer?

    /// Directory in which `search.sqlite` is stored.
    private let databaseDirectoryURL: URL

    /// Resolved path to the database file.
    private var databasePath: String {
        databaseDirectoryURL.appendingPathComponent("search.sqlite").path
    }

    // MARK: - Init

    /// Creates an FTS5Manager that stores its database in the given directory.
    ///
    /// - Parameter databaseDirectoryURL: Directory URL where `search.sqlite`
    ///   will be created. The directory must already exist.
    public init(databaseDirectoryURL: URL) {
        self.databaseDirectoryURL = databaseDirectoryURL
    }

    deinit {
        // Close the database if it was left open.
        // Actor deinit runs when the last reference is released.
        if let db {
            sqlite3_close_v2(db)
        }
    }

    // MARK: - Lifecycle

    /// Opens the database and creates the FTS5 virtual table if it does not
    /// already exist.
    ///
    /// If the database file is corrupt (`SQLITE_CORRUPT`), it is deleted
    /// and recreated automatically.
    ///
    /// - Throws: `FTS5Error.sqliteError` if opening or table creation fails
    ///   for a reason other than corruption.
    public func open() throws {
        // Already open -- no-op.
        if db != nil { return }

        do {
            try openDatabase()
            try createTableIfNeeded()
        } catch FTS5Error.corruptDatabase {
            // Delete the corrupt file and retry once.
            close()
            try? FileManager.default.removeItem(atPath: databasePath)
            try openDatabase()
            try createTableIfNeeded()
        }
    }

    /// Closes the database, releasing all resources.
    ///
    /// Calling this on an already-closed manager is safe (no-op).
    public func close() {
        guard let db else { return }
        sqlite3_close_v2(db)
        self.db = nil
    }

    /// Whether the database is currently open and ready for queries.
    public var isOpen: Bool {
        db != nil
    }

    // MARK: - Index Mutations

    /// Inserts an email into the FTS5 index.
    ///
    /// If an entry with the same `emailId` already exists it is replaced
    /// (delete + insert, since FTS5 does not support `REPLACE`).
    ///
    /// - Parameters:
    ///   - emailId: Stable identifier for the email.
    ///   - accountId: Account that owns the email.
    ///   - subject: Email subject line.
    ///   - body: Plain-text email body.
    ///   - senderName: Display name of the sender.
    ///   - senderEmail: Email address of the sender.
    /// - Throws: `FTS5Error` on failure.
    ///
    /// Spec ref: FR-SEARCH-06
    public func insert(
        emailId: String,
        accountId: String,
        subject: String,
        body: String,
        senderName: String,
        senderEmail: String
    ) throws {
        guard let db else { throw FTS5Error.databaseNotOpen }

        // Delete existing entry first (FTS5 doesn't support REPLACE).
        try deleteRow(emailId: emailId, db: db)

        let sql = """
            INSERT INTO email_fts(email_id, account_id, subject, body, sender_name, sender_email)
            VALUES (?, ?, ?, ?, ?, ?);
            """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        try prepareStatement(sql: sql, db: db, stmt: &stmt)

        sqlite3_bind_text(stmt, 1, emailId, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 2, accountId, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 3, subject, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 4, body, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 5, senderName, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 6, senderEmail, -1, Self.sqliteTransient)

        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE else {
            throw sqliteError(db: db, code: result)
        }
    }

    /// Deletes a single email from the FTS5 index.
    ///
    /// - Parameter emailId: Identifier of the email to remove.
    /// - Throws: `FTS5Error` on failure.
    public func delete(emailId: String) throws {
        guard let db else { throw FTS5Error.databaseNotOpen }
        try deleteRow(emailId: emailId, db: db)
    }

    /// Deletes all FTS5 entries belonging to the given account.
    ///
    /// - Parameter accountId: Account whose entries should be removed.
    /// - Throws: `FTS5Error` on failure.
    public func deleteAll(accountId: String) throws {
        guard let db else { throw FTS5Error.databaseNotOpen }

        let sql = "DELETE FROM email_fts WHERE account_id = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        try prepareStatement(sql: sql, db: db, stmt: &stmt)
        sqlite3_bind_text(stmt, 1, accountId, -1, Self.sqliteTransient)

        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE else {
            throw sqliteError(db: db, code: result)
        }
    }

    // MARK: - Search

    /// Searches the FTS5 index for emails matching the given query.
    ///
    /// The query is sanitized and a trailing `*` is appended for prefix
    /// matching (search-as-you-type). Results are ranked by BM25 score
    /// (lower values indicate better relevance).
    ///
    /// - Parameters:
    ///   - query: User-entered search string.
    ///   - limit: Maximum number of results to return. Defaults to 50.
    /// - Returns: Array of `FTS5SearchResult` sorted by BM25 rank.
    /// - Throws: `FTS5Error.invalidQuery` if the sanitized query is empty,
    ///   or `FTS5Error` on database failure.
    ///
    /// Spec ref: FR-SEARCH-06
    public func search(query: String, limit: Int = 50) throws -> [FTS5SearchResult] {
        guard let db else { throw FTS5Error.databaseNotOpen }

        let sanitized = sanitizeQuery(query)
        guard !sanitized.isEmpty else { throw FTS5Error.invalidQuery }

        // Append * for prefix matching (search-as-you-type).
        let ftsQuery = sanitized + "*"

        let sql = """
            SELECT email_id, account_id, bm25(email_fts) AS rank
            FROM email_fts
            WHERE email_fts MATCH ?
            ORDER BY bm25(email_fts)
            LIMIT ?;
            """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        try prepareStatement(sql: sql, db: db, stmt: &stmt)
        sqlite3_bind_text(stmt, 1, ftsQuery, -1, Self.sqliteTransient)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [FTS5SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let emailId = String(cString: sqlite3_column_text(stmt, 0))
            let accountId = String(cString: sqlite3_column_text(stmt, 1))
            let rank = sqlite3_column_double(stmt, 2)
            results.append(FTS5SearchResult(emailId: emailId, accountId: accountId, rank: rank))
        }

        return results
    }

    /// Returns highlighted text for a specific email and column, wrapping
    /// matched terms in `<b>` / `</b>` tags.
    ///
    /// - Parameters:
    ///   - emailId: Identifier of the email to highlight.
    ///   - column: The FTS5 column to highlight.
    ///   - query: The search query whose matches should be highlighted.
    /// - Returns: The highlighted text, or `nil` if the email was not found.
    /// - Throws: `FTS5Error` on failure.
    public func highlight(emailId: String, column: FTS5Column, query: String) throws -> String? {
        guard let db else { throw FTS5Error.databaseNotOpen }

        let sanitized = sanitizeQuery(query)
        guard !sanitized.isEmpty else { throw FTS5Error.invalidQuery }

        let ftsQuery = sanitized + "*"

        let sql = """
            SELECT highlight(email_fts, \(column.rawValue), '<b>', '</b>')
            FROM email_fts
            WHERE email_fts MATCH ? AND email_id = ?;
            """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        try prepareStatement(sql: sql, db: db, stmt: &stmt)
        sqlite3_bind_text(stmt, 1, ftsQuery, -1, Self.sqliteTransient)
        sqlite3_bind_text(stmt, 2, emailId, -1, Self.sqliteTransient)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        guard let cText = sqlite3_column_text(stmt, 0) else {
            return nil
        }

        return String(cString: cText)
    }

    // MARK: - Private: Database Setup

    /// Opens the SQLite database at `databasePath` with WAL journal mode.
    private func openDatabase() throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databasePath, &db, flags, nil)

        if result == SQLITE_CORRUPT || result == SQLITE_NOTADB {
            db = nil
            throw FTS5Error.corruptDatabase
        }

        guard result == SQLITE_OK else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            db = nil
            throw FTS5Error.sqliteError(code: result, message: message)
        }

        // Enable WAL mode for concurrent reads.
        try exec(sql: "PRAGMA journal_mode = WAL;", db: db!)
    }

    /// Creates the FTS5 virtual table if it does not already exist.
    private func createTableIfNeeded() throws {
        guard let db else { throw FTS5Error.databaseNotOpen }

        let sql = """
            CREATE VIRTUAL TABLE IF NOT EXISTS email_fts USING fts5(
                email_id UNINDEXED,
                account_id UNINDEXED,
                subject,
                body,
                sender_name,
                sender_email,
                tokenize='unicode61 remove_diacritics 2'
            );
            """

        do {
            try exec(sql: sql, db: db)
        } catch let error as FTS5Error {
            if case .sqliteError(let code, _) = error, code == SQLITE_CORRUPT {
                throw FTS5Error.corruptDatabase
            }
            throw error
        }
    }

    // MARK: - Private: SQL Helpers

    /// Executes a non-parameterized SQL statement via `sqlite3_exec`.
    private func exec(sql: String, db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }

        guard result == SQLITE_OK else {
            let message = errorMessage.flatMap { String(cString: $0) } ?? "unknown"
            throw FTS5Error.sqliteError(code: result, message: message)
        }
    }

    /// Prepares a parameterized SQL statement.
    private func prepareStatement(
        sql: String,
        db: OpaquePointer,
        stmt: inout OpaquePointer?
    ) throws {
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK else {
            throw sqliteError(db: db, code: result)
        }
    }

    /// Deletes a single row by `email_id`.
    private func deleteRow(emailId: String, db: OpaquePointer) throws {
        let sql = "DELETE FROM email_fts WHERE email_id = ?;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        try prepareStatement(sql: sql, db: db, stmt: &stmt)
        sqlite3_bind_text(stmt, 1, emailId, -1, Self.sqliteTransient)

        let result = sqlite3_step(stmt)
        guard result == SQLITE_DONE else {
            throw sqliteError(db: db, code: result)
        }
    }

    /// Constructs an `FTS5Error.sqliteError` from the current database state.
    private func sqliteError(db: OpaquePointer, code: Int32) -> FTS5Error {
        let message = String(cString: sqlite3_errmsg(db))
        return .sqliteError(code: code, message: message)
    }

    // MARK: - Private: Query Sanitization

    /// Sanitizes a user-entered query for safe use in FTS5 MATCH expressions.
    ///
    /// Removes FTS5 special characters (`"`, `*`, `(`, `)`, `:`, `^`, `{`, `}`)
    /// and collapses whitespace. Individual terms are joined so FTS5 performs
    /// an implicit AND across all tokens.
    private func sanitizeQuery(_ query: String) -> String {
        let specialCharacters = CharacterSet(charactersIn: "\"*():^{}")
        let cleaned = query.unicodeScalars
            .filter { !specialCharacters.contains($0) }
            .map { Character($0) }

        let result = String(cleaned)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return result
    }

    // MARK: - Private: Constants

    /// `SQLITE_TRANSIENT` tells SQLite to make its own copy of bound text.
    /// The C macro is defined as `((sqlite3_destructor_type)-1)` which Swift
    /// cannot import directly, so we replicate it here.
    private static let sqliteTransient = unsafeBitCast(
        -1, to: sqlite3_destructor_type.self
    )
}
