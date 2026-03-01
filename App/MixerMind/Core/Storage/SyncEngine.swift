import Foundation
import CoreData

enum SyncStatus: Equatable {
    case idle
    case syncing
    case completed
    case failed(String)
}

@Observable @MainActor
final class SyncEngine {
    var syncStatus: SyncStatus = .idle

    private let fileManager = LocalFileManager.shared

    func sync(context: NSManagedObjectContext) async {
        syncStatus = .syncing

        do {
            // Generate local embeddings for mixes that have content but no embedding
            await generateMissingEmbeddings(context: context)

            // Ensure every mix has audio — copy silent placeholder if none exists
            populateSilencePlaceholders(context: context)

            try context.save()
            syncStatus = .completed
        } catch {
            syncStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - Local Embeddings

    private func generateMissingEmbeddings(context: NSManagedObjectContext) async {
        let request = NSFetchRequest<LocalMix>(entityName: "LocalMix")
        guard let localMixes = try? context.fetch(request) else { return }

        for local in localMixes {
            // Skip if already embedded or no content to embed
            guard local.localEmbedding == nil,
                  let content = local.searchContent,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            do {
                local.localEmbedding = try await EmbeddingService.generate(from: content)
            } catch {
                // Embedding failed — will retry next sync
            }
        }
    }

    // MARK: - Silence Placeholders

    private func populateSilencePlaceholders(context: NSManagedObjectContext) {
        let request = NSFetchRequest<LocalMix>(entityName: "LocalMix")
        guard let localMixes = try? context.fetch(request) else { return }

        for local in localMixes {
            guard local.localAudioPath == nil else { continue }
            guard let bundleURL = Bundle.main.url(forResource: "silence_10s", withExtension: "mp3") else { continue }

            let relativePath = "\(local.mixId.uuidString)/silence.mp3"
            let destination = fileManager.fileURL(for: relativePath)

            let parent = destination.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }

            if !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.copyItem(at: bundleURL, to: destination)
            }

            local.localAudioPath = relativePath
        }
    }
}
