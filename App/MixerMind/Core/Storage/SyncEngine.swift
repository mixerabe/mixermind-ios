import Foundation
import SwiftData

enum SyncStatus: Equatable {
    case idle
    case syncing
    case downloading(current: Int, total: Int)
    case completed
    case failed(String)
}

@Observable @MainActor
final class SyncEngine {
    var syncStatus: SyncStatus = .idle

    private let repo: MixRepository = resolve()
    private let tagRepo: TagRepository = resolve()
    private let fileManager = LocalFileManager.shared

    func sync(modelContext: ModelContext) async {
        syncStatus = .syncing

        do {
            // 1. Fetch all mixes from Supabase
            let remoteMixes = try await repo.listMixes()

            // 2. Fetch all LocalMix from SwiftData
            let descriptor = FetchDescriptor<LocalMix>()
            let localMixes = try modelContext.fetch(descriptor)
            let localMap = Dictionary(uniqueKeysWithValues: localMixes.map { ($0.mixId, $0) })

            let remoteIds = Set(remoteMixes.map(\.id))
            let localIds = Set(localMixes.map(\.mixId))

            // 3. Delete removed mixes
            let deletedIds = localIds.subtracting(remoteIds)
            for id in deletedIds {
                if let local = localMap[id] {
                    deleteLocalFiles(for: local)
                    modelContext.delete(local)
                }
            }

            // 4. Determine new and existing mixes
            let newMixes = remoteMixes.filter { !localIds.contains($0.id) }
            let existingMixes = remoteMixes.filter { localIds.contains($0.id) }

            // 5. Check storage space before bulk download
            let totalFiles = countMediaFiles(newMixes) + countMissingFiles(existingMixes, localMap: localMap)
            let estimatedSize = Int64(totalFiles) * 5 * 1024 * 1024 // 5MB per file estimate
            guard fileManager.hasSpaceForDownload(estimatedSize: estimatedSize) else {
                syncStatus = .failed("Not enough storage space")
                return
            }

            var completed = 0
            let totalDownloads = newMixes.count + existingMixes.count

            // 6. Add new mixes
            for mix in newMixes {
                let local = LocalMix(mixId: mix.id, type: mix.type.rawValue, createdAt: mix.createdAt)
                local.updateFromRemote(mix)
                modelContext.insert(local)
                await downloadAllMedia(for: local, from: mix)
                completed += 1
                syncStatus = .downloading(current: completed, total: totalDownloads)
            }

            // 7. Update existing mixes
            for mix in existingMixes {
                if let local = localMap[mix.id] {
                    local.updateFromRemote(mix)
                    await downloadAllMedia(for: local, from: mix)
                    completed += 1
                    syncStatus = .downloading(current: completed, total: totalDownloads)
                }
            }

            // 8. Sync tags and mix_tags
            await syncTags(modelContext: modelContext)

            // 9. Save
            try modelContext.save()
            syncStatus = .completed
        } catch {
            syncStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - Download Media

    private func downloadAllMedia(for local: LocalMix, from mix: Mix) async {
        // Helper: download a Supabase storage URL or external URL
        func download(_ remoteUrl: String?) async -> String? {
            guard let urlString = remoteUrl, !urlString.isEmpty else { return nil }
            do {
                if let storagePath = fileManager.storagePath(from: urlString) {
                    return try await fileManager.downloadFromStorage(storagePath: storagePath)
                } else if let url = URL(string: urlString) {
                    return try await fileManager.downloadFromURL(url)
                }
            } catch {
                // Download failed — will retry on next sync
            }
            return nil
        }

        switch mix.type {
        case .text:
            local.localTtsAudioPath = await download(mix.ttsAudioUrl)

        case .photo:
            local.localPhotoPath = await download(mix.photoUrl)
            local.localPhotoThumbnailPath = await download(mix.photoThumbnailUrl)

        case .video:
            local.localVideoPath = await download(mix.videoUrl)
            local.localVideoThumbnailPath = await download(mix.videoThumbnailUrl)

        case .import:
            local.localImportMediaPath = await download(mix.importMediaUrl)
            local.localImportThumbnailPath = await download(mix.importThumbnailUrl)
            local.localImportAudioPath = await download(mix.importAudioUrl)

        case .embed:
            if let ogImageUrl = mix.embedOg?.imageUrl {
                local.localEmbedOgImagePath = await download(ogImageUrl)
            }

        case .audio:
            local.localAudioPath = await download(mix.audioUrl)
        }

        // Mark as synced if all applicable media is downloaded
        local.isSynced = checkAllMediaDownloaded(local, mix: mix)
    }

    private func checkAllMediaDownloaded(_ local: LocalMix, mix: Mix) -> Bool {
        func hasLocal(_ path: String?, remote: String?) -> Bool {
            guard remote != nil else { return true } // No remote = nothing to download
            guard let path else { return false }
            return fileManager.fileExists(at: path)
        }

        switch mix.type {
        case .text:
            return hasLocal(local.localTtsAudioPath, remote: mix.ttsAudioUrl)
        case .photo:
            return hasLocal(local.localPhotoPath, remote: mix.photoUrl)
                && hasLocal(local.localPhotoThumbnailPath, remote: mix.photoThumbnailUrl)
        case .video:
            return hasLocal(local.localVideoPath, remote: mix.videoUrl)
                && hasLocal(local.localVideoThumbnailPath, remote: mix.videoThumbnailUrl)
        case .import:
            return hasLocal(local.localImportMediaPath, remote: mix.importMediaUrl)
                && hasLocal(local.localImportThumbnailPath, remote: mix.importThumbnailUrl)
                && hasLocal(local.localImportAudioPath, remote: mix.importAudioUrl)
        case .embed:
            return hasLocal(local.localEmbedOgImagePath, remote: mix.embedOg?.imageUrl)
        case .audio:
            return hasLocal(local.localAudioPath, remote: mix.audioUrl)
        }
    }

    // MARK: - Tag Sync

    private func syncTags(modelContext: ModelContext) async {
        do {
            let remoteTags = try await tagRepo.listTags()
            let remoteMixTags = try await tagRepo.allMixTagRows()

            // Sync tags
            let localTags = try modelContext.fetch(FetchDescriptor<LocalTag>())
            let localTagMap = Dictionary(uniqueKeysWithValues: localTags.map { ($0.tagId, $0) })
            let remoteTagIds = Set(remoteTags.map(\.id))
            let localTagIds = Set(localTags.map(\.tagId))

            // Delete removed tags
            for id in localTagIds.subtracting(remoteTagIds) {
                if let local = localTagMap[id] {
                    modelContext.delete(local)
                }
            }

            // Add/update tags
            for tag in remoteTags {
                if let local = localTagMap[tag.id] {
                    local.updateFromRemote(tag)
                } else {
                    let local = LocalTag(tagId: tag.id, name: tag.name, createdAt: tag.createdAt)
                    modelContext.insert(local)
                }
            }

            // Sync mix_tags: replace all with remote state
            let localMixTags = try modelContext.fetch(FetchDescriptor<LocalMixTag>())
            for local in localMixTags {
                modelContext.delete(local)
            }
            for row in remoteMixTags {
                modelContext.insert(LocalMixTag(mixId: row.mixId, tagId: row.tagId))
            }
        } catch {
            // Tag sync failed — local state preserved, will retry next sync
        }
    }

    // MARK: - Cleanup

    private func deleteLocalFiles(for local: LocalMix) {
        let paths = [
            local.localTtsAudioPath,
            local.localPhotoPath,
            local.localPhotoThumbnailPath,
            local.localVideoPath,
            local.localVideoThumbnailPath,
            local.localImportMediaPath,
            local.localImportThumbnailPath,
            local.localImportAudioPath,
            local.localEmbedOgImagePath,
            local.localAudioPath,
        ]
        for path in paths {
            if let path {
                fileManager.deleteFile(at: path)
            }
        }
    }

    // MARK: - Estimation Helpers

    private func countMediaFiles(_ mixes: [Mix]) -> Int {
        mixes.reduce(0) { count, mix in
            count + mediaFieldCount(for: mix)
        }
    }

    private func countMissingFiles(_ mixes: [Mix], localMap: [UUID: LocalMix]) -> Int {
        mixes.reduce(0) { count, mix in
            guard let local = localMap[mix.id] else { return count }
            return count + (local.isSynced ? 0 : mediaFieldCount(for: mix))
        }
    }

    private func mediaFieldCount(for mix: Mix) -> Int {
        switch mix.type {
        case .text: return mix.ttsAudioUrl != nil ? 1 : 0
        case .photo: return [mix.photoUrl, mix.photoThumbnailUrl].compactMap({ $0 }).count
        case .video: return [mix.videoUrl, mix.videoThumbnailUrl].compactMap({ $0 }).count
        case .import: return [mix.importMediaUrl, mix.importThumbnailUrl, mix.importAudioUrl].compactMap({ $0 }).count
        case .embed: return mix.embedOg?.imageUrl != nil ? 1 : 0
        case .audio: return mix.audioUrl != nil ? 1 : 0
        }
    }
}
