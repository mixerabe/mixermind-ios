import Foundation
import CoreData

final class MixRepository {

    // MARK: - CRUD

    func listMixes(context: NSManagedObjectContext) throws -> [Mix] {
        let request = NSFetchRequest<LocalMix>(entityName: "LocalMix")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocalMix.createdAt, ascending: false)]
        return try context.fetch(request).map { $0.toMix() }
    }

    /// Fetches mixes with tags pre-populated via a single pass over mix-tag rows.
    func listMixesWithTags(context: NSManagedObjectContext) throws -> [Mix] {
        let mixRequest = NSFetchRequest<LocalMix>(entityName: "LocalMix")
        mixRequest.sortDescriptors = [NSSortDescriptor(keyPath: \LocalMix.createdAt, ascending: false)]
        let localMixes = try context.fetch(mixRequest)

        let tagRequest = NSFetchRequest<LocalTag>(entityName: "LocalTag")
        let localTags = try context.fetch(tagRequest)
        let tagLookup = Dictionary(uniqueKeysWithValues: localTags.map { ($0.tagId, $0.toTag()) })

        let mixTagRequest = NSFetchRequest<LocalMixTag>(entityName: "LocalMixTag")
        let localMixTags = try context.fetch(mixTagRequest)
        var tagMap: [UUID: [Tag]] = [:]
        for row in localMixTags {
            if let tag = tagLookup[row.tagId] {
                tagMap[row.mixId, default: []].append(tag)
            }
        }

        return localMixes.map { local in
            local.toMix(tags: tagMap[local.mixId] ?? [])
        }
    }

    func getMix(id: UUID, context: NSManagedObjectContext) throws -> Mix? {
        let request = NSFetchRequest<LocalMix>(entityName: "LocalMix")
        request.predicate = NSPredicate(format: "mixId == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first?.toMix()
    }

    func updateTitle(id: UUID, title: String?, context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<LocalMix>(entityName: "LocalMix")
        request.predicate = NSPredicate(format: "mixId == %@", id as CVarArg)
        request.fetchLimit = 1
        if let local = try context.fetch(request).first {
            local.title = title
            try context.save()
        }
    }

    func deleteMix(id: UUID, context: NSManagedObjectContext) throws {
        let fileManager = LocalFileManager.shared

        let mixRequest = NSFetchRequest<LocalMix>(entityName: "LocalMix")
        mixRequest.predicate = NSPredicate(format: "mixId == %@", id as CVarArg)
        mixRequest.fetchLimit = 1
        if let local = try context.fetch(mixRequest).first {
            // Delete local files
            let paths = [
                local.localMediaPath, local.localMediaThumbnailPath,
                local.localEmbedOgImagePath, local.localAudioPath,
                local.localScreenshotPath,
            ]
            for path in paths {
                if let path { fileManager.deleteFile(at: path) }
            }

            // Delete the mix directory
            let dirURL = fileManager.fileURL(for: id.uuidString)
            try? FileManager.default.removeItem(at: dirURL)

            context.delete(local)
        }

        // Delete associated mix-tag rows
        let tagRequest = NSFetchRequest<LocalMixTag>(entityName: "LocalMixTag")
        tagRequest.predicate = NSPredicate(format: "mixId == %@", id as CVarArg)
        if let rows = try? context.fetch(tagRequest) {
            for row in rows {
                context.delete(row)
            }
        }

        try context.save()
    }
}
