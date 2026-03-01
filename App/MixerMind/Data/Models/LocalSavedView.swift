import Foundation
import CoreData

@objc(LocalSavedView)
class LocalSavedView: NSManagedObject {
    @NSManaged var viewId: UUID
    @NSManaged var name: String
    @NSManaged var tagIdsData: Data
    @NSManaged var createdAt: Date

    convenience init(viewId: UUID = UUID(), name: String, tagIds: [UUID], createdAt: Date = Date(), context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LocalSavedView", in: context)!
        self.init(entity: entity, insertInto: context)
        self.viewId = viewId
        self.name = name
        self.tagIdsData = (try? JSONEncoder().encode(tagIds)) ?? Data()
        self.createdAt = createdAt
    }

    var tagIds: [UUID] {
        get { (try? JSONDecoder().decode([UUID].self, from: tagIdsData)) ?? [] }
        set { tagIdsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    func toSavedView() -> SavedView {
        SavedView(id: viewId, name: name, tagIds: tagIds, createdAt: createdAt)
    }
}
