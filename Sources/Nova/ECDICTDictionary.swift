import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct ECDICTEntry {
    let word: String
    let phonetic: String?
    /// Chinese senses, one per line in the source data.
    let translation: String
    /// English definitions, one per line in the source data (may be empty).
    let definition: String?
    /// Space-separated exam tags like "cet4 cet6 ky toefl ielts gre".
    let tag: String?
}

/// Offline English→Chinese dictionary backed by the ECDICT sqlite database
/// (https://github.com/skywind3000/ECDICT, ~770k entries).
///
/// The database file `ecdict.db` is bundled into the app by
/// `scripts/build_app.sh`; run `scripts/fetch_ecdict.sh` once to download and
/// slim it. When the file is missing (e.g. plain `swift run` without an app
/// bundle) every lookup simply returns nil and callers fall through to the
/// online providers.
actor ECDICTDictionary {
    private var db: OpaquePointer?
    private var attemptedOpen = false

    var isAvailable: Bool {
        openIfNeeded()
        return db != nil
    }

    func lookup(_ word: String) -> ECDICTEntry? {
        openIfNeeded()
        guard let db else { return nil }

        let sql = """
        SELECT word, phonetic, translation, definition, tag
        FROM stardict
        WHERE word = ? COLLATE NOCASE
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            NSLog("[ECDICT] prepare failed: %@", String(cString: sqlite3_errmsg(db)))
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, word, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        func column(_ index: Int32) -> String? {
            guard let cString = sqlite3_column_text(statement, index) else { return nil }
            let value = String(cString: cString).trimmed
            return value.isEmpty ? nil : value
        }

        guard let matchedWord = column(0), let translation = column(2) else { return nil }

        return ECDICTEntry(
            word: matchedWord,
            phonetic: column(1).map { "/\($0)/" },
            translation: translation,
            definition: column(3),
            tag: column(4)
        )
    }

    private func openIfNeeded() {
        guard !attemptedOpen else { return }
        attemptedOpen = true

        guard let url = Bundle.main.url(forResource: "ecdict", withExtension: "db") else {
            NSLog("[ECDICT] ecdict.db not bundled; offline dictionary disabled")
            return
        }

        var handle: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
        guard status == SQLITE_OK, handle != nil else {
            NSLog("[ECDICT] open failed with status %d", status)
            if handle != nil { sqlite3_close(handle) }
            return
        }
        db = handle
    }
}
