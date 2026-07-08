import AppKit
import Foundation

/// On-disk store for inline images referenced from Markdown as
/// `![](attachments/<uuid>.png)`. PNGs live under
/// `~/Library/Application Support/Nova/attachments/`. The Markdown strings
/// (`model.todoMemo`, `TodoItem.note`) only ever hold the *relative* path
/// `attachments/<uuid>.png`; this type maps that token to/from disk.
///
/// Stateless namespace, mirroring `AppSupport`. All IO is synchronous and runs
/// on the caller's thread — fine for screenshot-sized PNGs pasted from the
/// clipboard. Filenames are fresh UUIDs (write-once), so reads never race a
/// rewrite of the same file and no locking is needed.
enum AttachmentStore {
    static let directoryName = "attachments"
    /// The prefix that appears in the Markdown token, e.g. `attachments/x.png`.
    static let relativePrefix = "attachments/"

    enum AttachmentError: Error { case encodingFailed, decodingFailed }

    /// In-memory decode cache. `NSCache` is internally thread-safe and
    /// self-evicting; since filenames are write-once UUIDs, cache invalidation is
    /// a non-issue (hence `nonisolated(unsafe)` — access is safe without an actor).
    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    /// `~/Library/Application Support/Nova/attachments/`, created if missing.
    static func attachmentsDirectory() throws -> URL {
        let dir = try AppSupport.dataDirectory()
            .appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Absolute URL for a stored relative path. Strips the leading
    /// `attachments/` so we never double-nest, and rejects path traversal.
    static func url(forRelativePath relativePath: String) -> URL? {
        guard let name = lastPathComponentSafe(relativePath) else { return nil }
        return try? attachmentsDirectory().appendingPathComponent(name, isDirectory: false)
    }

    // MARK: - Save

    /// Encode an `NSImage` to PNG and persist it. Returns the relative-path token
    /// `attachments/<uuid>.png` to embed in Markdown.
    @discardableResult
    static func save(_ image: NSImage) throws -> String {
        guard let data = pngData(from: image) else { throw AttachmentError.encodingFailed }
        return try save(pngData: data)
    }

    /// Persist already-encoded PNG bytes (clipboard `.png` path).
    @discardableResult
    static func save(pngData data: Data) throws -> String {
        let filename = "\(UUID().uuidString).png"
        let dest = try attachmentsDirectory().appendingPathComponent(filename, isDirectory: false)
        try data.write(to: dest, options: .atomic)
        return relativePrefix + filename
    }

    /// Persist from a dropped / imported file URL. Decodes then re-encodes to PNG
    /// so JPEG/HEIC/TIFF/etc. all normalize to a single on-disk format, and so we
    /// own our own copy rather than depending on the source file surviving.
    @discardableResult
    static func save(fileURL: URL) throws -> String {
        guard let image = NSImage(contentsOf: fileURL) else { throw AttachmentError.decodingFailed }
        return try save(image)
    }

    // MARK: - Load

    static func loadImage(relativePath: String) -> NSImage? {
        if let hit = cache.object(forKey: relativePath as NSString) { return hit }
        guard let url = url(forRelativePath: relativePath),
              FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: relativePath as NSString)
        return image
    }

    // MARK: - NSImage → PNG

    /// The full `tiffRepresentation → NSBitmapImageRep → PNG` chain.
    /// `NSBitmapImageRep(data:)` collapses a multi-rep TIFF to its primary rep,
    /// which is what we want for a single clipboard image.
    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Helpers

    /// Returns just the file name for an `attachments/<name>` token, or `nil` if
    /// it contains traversal (`..`), a path separator, or is empty. Defends
    /// `loadImage` / `url` against escaping the attachments directory.
    private static func lastPathComponentSafe(_ relativePath: String) -> String? {
        let trimmed = relativePath.hasPrefix(relativePrefix)
            ? String(relativePath.dropFirst(relativePrefix.count))
            : relativePath
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains("..") else { return nil }
        return trimmed
    }

    // MARK: - Optional GC (phase 2 — not wired into normal save paths)

    /// Deletes any `.png` under the attachments dir not present in
    /// `referencedPaths` (the set of relative tokens still alive in the memo and
    /// all notes). Returns the number of files removed.
    @discardableResult
    static func pruneUnreferenced(referencedPaths: Set<String>) -> Int {
        guard let dir = try? attachmentsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return 0 }
        let referencedNames = Set(referencedPaths.compactMap(lastPathComponentSafe))
        var deleted = 0
        for file in files where file.pathExtension.lowercased() == "png" {
            if !referencedNames.contains(file.lastPathComponent),
               (try? FileManager.default.removeItem(at: file)) != nil {
                deleted += 1
            }
        }
        return deleted
    }
}
