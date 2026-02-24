import Foundation
import Supabase

final class LocalFileManager: Sendable {
    static let shared = LocalFileManager()

    private let baseDirectory: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        baseDirectory = docs.appendingPathComponent("MixMedia", isDirectory: true)

        // Create base directory if needed
        if !FileManager.default.fileExists(atPath: baseDirectory.path) {
            try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Path Utilities

    func fileURL(for relativePath: String) -> URL {
        baseDirectory.appendingPathComponent(relativePath)
    }

    func fileExists(at relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: relativePath).path)
    }

    // MARK: - Download from Supabase Storage

    /// Downloads a file from Supabase Storage using its storage path (e.g. "UUID/filename.jpg").
    /// Returns the relative path within MixMedia/.
    func downloadFromStorage(storagePath: String) async throws -> String {
        let publicURL = try storagePublicURL(for: storagePath)
        return try await download(from: publicURL, relativePath: storagePath)
    }

    /// Downloads from an external URL (Apple Music artwork, embed OG images).
    /// Stores under `external/{hash}/{filename}`.
    func downloadFromURL(_ url: URL) async throws -> String {
        let hash = String(url.absoluteString.hashValue, radix: 16, uppercase: false)
            .replacingOccurrences(of: "-", with: "")
        let filename = url.lastPathComponent.isEmpty ? "file" : url.lastPathComponent
        let relativePath = "external/\(hash)/\(filename)"
        return try await download(from: url, relativePath: relativePath)
    }

    // MARK: - Storage Path Extraction

    /// Extracts `{UUID}/{filename}` from a full Supabase public URL.
    /// Example: `https://xxx.supabase.co/storage/v1/object/public/mix-media/UUID/file.jpg` -> `UUID/file.jpg`
    /// Returns nil for external URLs (Apple Music, etc.)
    func storagePath(from publicURL: String) -> String? {
        guard let url = URL(string: publicURL),
              let host = url.host,
              host.contains("supabase") else {
            return nil
        }

        let pathComponents = url.pathComponents
        // Look for "mix-media" in the path and take everything after it
        if let idx = pathComponents.firstIndex(of: "mix-media"), idx + 1 < pathComponents.count {
            let remaining = pathComponents[(idx + 1)...]
            return remaining.joined(separator: "/")
        }
        return nil
    }

    // MARK: - File Management

    func deleteFile(at relativePath: String) {
        let url = fileURL(for: relativePath)
        try? FileManager.default.removeItem(at: url)

        // Clean up empty parent directory
        let parent = url.deletingLastPathComponent()
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        if contents.isEmpty {
            try? FileManager.default.removeItem(at: parent)
        }
    }

    func totalStorageUsed() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func getAvailableStorageSpace() -> Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return Int64.max
        }
        return available
    }

    func hasSpaceForDownload(estimatedSize: Int64) -> Bool {
        let buffer: Int64 = 100 * 1024 * 1024 // 100 MB buffer
        return getAvailableStorageSpace() > estimatedSize + buffer
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: baseDirectory)
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func download(from url: URL, relativePath: String) async throws -> String {
        let destination = fileURL(for: relativePath)

        // Skip if already downloaded
        if FileManager.default.fileExists(atPath: destination.path) {
            return relativePath
        }

        // Create parent directory
        let parent = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        return relativePath
    }

    private func storagePublicURL(for storagePath: String) throws -> URL {
        guard let client = SupabaseManager.shared.client else {
            throw URLError(.notConnectedToInternet)
        }
        return try client.storage.from("mix-media").getPublicURL(path: storagePath)
    }
}
