import CoreData

final class CoreDataStack {
    static let shared = CoreDataStack()

    let persistentContainer: NSPersistentContainer
    var viewContext: NSManagedObjectContext { persistentContainer.viewContext }

    private init() {
        persistentContainer = NSPersistentContainer(name: "MixerMind")

        // Enable lightweight migration for simple schema additions
        if let description = persistentContainer.persistentStoreDescriptions.first {
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        }

        persistentContainer.loadPersistentStores { _, error in
            if let error {
                // Schema mismatch — delete the old store and retry
                Self.deleteStoreFiles()
                self.persistentContainer.loadPersistentStores { _, retryError in
                    if let retryError {
                        fatalError("Failed to load Core Data store: \(retryError)")
                    }
                }
            }
        }

        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.automaticallyMergesChangesFromParent = true
    }

    func seedDefaultTagsIfNeeded() {
        let ctx = viewContext
        let request = NSFetchRequest<NSNumber>(entityName: "LocalTag")
        request.resultType = .countResultType
        let count = (try? ctx.fetch(request).first?.intValue) ?? 0
        guard count == 0 else { return }

        let names = [
            "ideas", "work", "personal", "inspiration",
            "music", "photos", "videos", "links",
            "journal", "recipes", "travel", "fitness"
        ]
        let now = Date()
        for name in names {
            _ = LocalTag(tagId: UUID(), name: name, createdAt: now, context: ctx)
        }
        try? ctx.save()
    }

    private static func deleteStoreFiles() {
        let dir = NSPersistentContainer.defaultDirectoryURL()
        let base = dir.appendingPathComponent("MixerMind.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: base.path + suffix)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
