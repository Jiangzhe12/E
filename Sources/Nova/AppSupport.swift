import Foundation

/// Resolves the app's Application Support data location and performs a one-time migration
/// from the legacy "EnglishCoach" folder to "Nova", so existing vocabulary / todo / history
/// data carries over after the rebrand. The SQLite file name is intentionally left unchanged
/// so the migration is a single atomic directory move (lowest risk to user data).
enum AppSupport {
    static let folderName = "Nova"
    static let legacyFolderName = "EnglishCoach"
    static let databaseFileName = "english_coach.sqlite3"

    /// Moves the legacy folder to the new one at most once per process (lazy statics are
    /// initialized exactly once and thread-safely in Swift).
    private static let migrateLegacyFolderIfNeeded: Void = {
        let fileManager = FileManager.default
        guard let base = try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return }
        let newDir = base.appendingPathComponent(folderName, isDirectory: true)
        let legacyDir = base.appendingPathComponent(legacyFolderName, isDirectory: true)
        // Only migrate when the new folder doesn't exist yet and the legacy one does —
        // never overwrite data that already lives under the new name.
        guard !fileManager.fileExists(atPath: newDir.path),
              fileManager.fileExists(atPath: legacyDir.path) else { return }
        try? fileManager.moveItem(at: legacyDir, to: newDir)
    }()

    /// The app data directory (`~/Library/Application Support/Nova`), created if missing.
    static func dataDirectory() throws -> URL {
        _ = migrateLegacyFolderIfNeeded
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The shared SQLite database URL.
    static func databaseURL() throws -> URL {
        try dataDirectory().appendingPathComponent(databaseFileName, isDirectory: false)
    }
}
