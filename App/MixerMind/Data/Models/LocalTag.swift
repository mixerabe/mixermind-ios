import Foundation
import SwiftData

@Model
final class LocalTag {
    @Attribute(.unique) var tagId: UUID
    var name: String
    var createdAt: Date

    init(tagId: UUID, name: String, createdAt: Date) {
        self.tagId = tagId
        self.name = name
        self.createdAt = createdAt
    }

    func toTag() -> Tag {
        Tag(id: tagId, name: name, createdAt: createdAt)
    }

    func updateFromRemote(_ tag: Tag) {
        name = tag.name
        createdAt = tag.createdAt
    }
}

@Model
final class LocalMixTag {
    var mixId: UUID
    var tagId: UUID

    init(mixId: UUID, tagId: UUID) {
        self.mixId = mixId
        self.tagId = tagId
    }
}
