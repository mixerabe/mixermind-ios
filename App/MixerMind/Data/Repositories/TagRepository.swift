import Foundation
import CoreData

final class TagRepository {

    // MARK: - Tags CRUD

    func listTags(context: NSManagedObjectContext) throws -> [Tag] {
        let request = NSFetchRequest<LocalTag>(entityName: "LocalTag")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocalTag.name, ascending: true)]
        return try context.fetch(request).map { $0.toTag() }
    }

    func createTag(name: String, context: NSManagedObjectContext) throws -> Tag {
        let tagId = UUID()
        let now = Date()
        let local = LocalTag(tagId: tagId, name: name, createdAt: now, context: context)
        try context.save()
        return local.toTag()
    }

    func updateTag(id: UUID, name: String, context: NSManagedObjectContext) throws -> Tag? {
        let request = NSFetchRequest<LocalTag>(entityName: "LocalTag")
        request.predicate = NSPredicate(format: "tagId == %@", id as CVarArg)
        request.fetchLimit = 1
        if let local = try context.fetch(request).first {
            local.name = name
            try context.save()
            return local.toTag()
        }
        return nil
    }

    func deleteTag(id: UUID, context: NSManagedObjectContext) throws {
        // Delete the tag
        let tagRequest = NSFetchRequest<LocalTag>(entityName: "LocalTag")
        tagRequest.predicate = NSPredicate(format: "tagId == %@", id as CVarArg)
        tagRequest.fetchLimit = 1
        if let local = try context.fetch(tagRequest).first {
            context.delete(local)
        }
        // Delete related mix-tag rows
        let mixTagRequest = NSFetchRequest<LocalMixTag>(entityName: "LocalMixTag")
        mixTagRequest.predicate = NSPredicate(format: "tagId == %@", id as CVarArg)
        if let rows = try? context.fetch(mixTagRequest) {
            for row in rows {
                context.delete(row)
            }
        }
        try context.save()
    }

    // MARK: - Mix-Tag Relations

    func getTagIdsForMix(mixId: UUID, context: NSManagedObjectContext) throws -> [UUID] {
        let request = NSFetchRequest<LocalMixTag>(entityName: "LocalMixTag")
        request.predicate = NSPredicate(format: "mixId == %@", mixId as CVarArg)
        return try context.fetch(request).map(\.tagId)
    }

    func setTagsForMix(mixId: UUID, tagIds: Set<UUID>, context: NSManagedObjectContext) throws {
        // Delete existing
        let request = NSFetchRequest<LocalMixTag>(entityName: "LocalMixTag")
        request.predicate = NSPredicate(format: "mixId == %@", mixId as CVarArg)
        let existing = try context.fetch(request)
        for row in existing {
            context.delete(row)
        }
        // Insert new
        for tagId in tagIds {
            _ = LocalMixTag(mixId: mixId, tagId: tagId, context: context)
        }
        try context.save()
    }

    func addTagToMix(mixId: UUID, tagId: UUID, context: NSManagedObjectContext) throws {
        _ = LocalMixTag(mixId: mixId, tagId: tagId, context: context)
        try context.save()
    }

    func removeTagFromMix(mixId: UUID, tagId: UUID, context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<LocalMixTag>(entityName: "LocalMixTag")
        request.predicate = NSPredicate(format: "mixId == %@ AND tagId == %@", mixId as CVarArg, tagId as CVarArg)
        request.fetchLimit = 1
        if let row = try context.fetch(request).first {
            context.delete(row)
            try context.save()
        }
    }

    func tagsForMix(mixId: UUID, context: NSManagedObjectContext) throws -> [Tag] {
        let mixTagRequest = NSFetchRequest<LocalMixTag>(entityName: "LocalMixTag")
        mixTagRequest.predicate = NSPredicate(format: "mixId == %@", mixId as CVarArg)
        let mixTags = try context.fetch(mixTagRequest)
        let tagIds = Set(mixTags.map(\.tagId))

        let tagRequest = NSFetchRequest<LocalTag>(entityName: "LocalTag")
        let allTags = try context.fetch(tagRequest)
        return allTags.filter { tagIds.contains($0.tagId) }.map { $0.toTag() }
    }

    func tagMap(context: NSManagedObjectContext) throws -> [UUID: Set<UUID>] {
        let request = NSFetchRequest<LocalMixTag>(entityName: "LocalMixTag")
        let rows = try context.fetch(request)
        var map: [UUID: Set<UUID>] = [:]
        for row in rows {
            map[row.mixId, default: []].insert(row.tagId)
        }
        return map
    }

}
