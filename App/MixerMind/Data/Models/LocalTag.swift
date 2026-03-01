import Foundation
import CoreData

@objc(LocalTag)
class LocalTag: NSManagedObject {
    @NSManaged var tagId: UUID
    @NSManaged var name: String
    @NSManaged var createdAt: Date

    convenience init(tagId: UUID, name: String, createdAt: Date, context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LocalTag", in: context)!
        self.init(entity: entity, insertInto: context)
        self.tagId = tagId
        self.name = name
        self.createdAt = createdAt
    }

    func toTag() -> Tag {
        Tag(id: tagId, name: name, createdAt: createdAt)
    }
}

@objc(LocalMixTag)
class LocalMixTag: NSManagedObject {
    @NSManaged var mixId: UUID
    @NSManaged var tagId: UUID

    convenience init(mixId: UUID, tagId: UUID, context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LocalMixTag", in: context)!
        self.init(entity: entity, insertInto: context)
        self.mixId = mixId
        self.tagId = tagId
    }
}
