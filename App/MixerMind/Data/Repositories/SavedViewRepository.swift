import Foundation
import CoreData

final class SavedViewRepository {

    func listSavedViews(context: NSManagedObjectContext) throws -> [SavedView] {
        let request = NSFetchRequest<LocalSavedView>(entityName: "LocalSavedView")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocalSavedView.name, ascending: true)]
        return try context.fetch(request).map { $0.toSavedView() }
    }

    func createSavedView(name: String, tagIds: [UUID], context: NSManagedObjectContext) throws -> SavedView {
        let local = LocalSavedView(name: name, tagIds: tagIds, context: context)
        try context.save()
        return local.toSavedView()
    }

    func updateTagIds(id: UUID, tagIds: [UUID], context: NSManagedObjectContext) throws -> SavedView? {
        let request = NSFetchRequest<LocalSavedView>(entityName: "LocalSavedView")
        request.predicate = NSPredicate(format: "viewId == %@", id as CVarArg)
        request.fetchLimit = 1
        if let local = try context.fetch(request).first {
            local.tagIds = tagIds
            try context.save()
            return local.toSavedView()
        }
        return nil
    }

    func updateName(id: UUID, name: String, context: NSManagedObjectContext) throws -> SavedView? {
        let request = NSFetchRequest<LocalSavedView>(entityName: "LocalSavedView")
        request.predicate = NSPredicate(format: "viewId == %@", id as CVarArg)
        request.fetchLimit = 1
        if let local = try context.fetch(request).first {
            local.name = name
            try context.save()
            return local.toSavedView()
        }
        return nil
    }

    func deleteSavedView(id: UUID, context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<LocalSavedView>(entityName: "LocalSavedView")
        request.predicate = NSPredicate(format: "viewId == %@", id as CVarArg)
        request.fetchLimit = 1
        if let local = try context.fetch(request).first {
            context.delete(local)
            try context.save()
        }
    }
}
