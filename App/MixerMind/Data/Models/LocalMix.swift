import Foundation
import CoreData

@objc(LocalMix)
class LocalMix: NSManagedObject {
    @NSManaged var mixId: UUID
    @NSManaged var type: String
    @NSManaged var createdAt: Date
    @NSManaged var title: String?

    // Text
    @NSManaged var textContent: String?

    // Embed (legacy — new mixes use widgetsJson)
    @NSManaged var embedUrl: String?
    @NSManaged var embedOgJson: Data?

    // Media flags
    @NSManaged var mediaIsVideo: Bool

    // Local relative paths (relative to Documents/MixMedia/)
    @NSManaged var localMediaPath: String?
    @NSManaged var localMediaThumbnailPath: String?
    @NSManaged var localEmbedOgImagePath: String?
    @NSManaged var localAudioPath: String?
    @NSManaged var localScreenshotPath: String?

    // Screenshot preview
    @NSManaged var previewScaleY: NSNumber?    // Legacy — kept for migration
    @NSManaged var previewCropX: NSNumber?      // 0.0 = left, 0.5 = center, 1.0 = right
    @NSManaged var previewCropY: NSNumber?      // 0.0 = top, 0.5 = center, 1.0 = bottom
    @NSManaged var previewCropScale: NSNumber?  // Zoom factor (1.0 = no crop)
    @NSManaged var gradientTop: String?
    @NSManaged var gradientBottom: String?

    // File (legacy — new mixes use widgetsJson)
    @NSManaged var fileName: String?

    // Widgets (JSON-encoded [MixWidget])
    @NSManaged var widgetsJson: Data?

    // Import source URL
    @NSManaged var sourceUrl: String?

    // Screenshot text bucket (small/medium/large)
    @NSManaged var screenshotBucket: String?

    // Search content (AI-generated description / transcript)
    @NSManaged var searchContent: String?
    // Local embedding from NLContextualEmbedding (encoded [Float])
    @NSManaged var localEmbedding: Data?

    var previewScaleYDouble: Double? {
        get { previewScaleY?.doubleValue }
        set {
            guard let value = newValue, value.isFinite else {
                setPrimitiveValue(nil, forKey: "previewScaleY")
                return
            }
            setPrimitiveValue(NSNumber(value: value), forKey: "previewScaleY")
        }
    }

    var previewCropXDouble: Double? {
        get { previewCropX?.doubleValue }
        set {
            guard let value = newValue, value.isFinite else {
                setPrimitiveValue(nil, forKey: "previewCropX")
                return
            }
            setPrimitiveValue(NSNumber(value: value), forKey: "previewCropX")
        }
    }

    var previewCropYDouble: Double? {
        get { previewCropY?.doubleValue }
        set {
            guard let value = newValue, value.isFinite else {
                setPrimitiveValue(nil, forKey: "previewCropY")
                return
            }
            setPrimitiveValue(NSNumber(value: value), forKey: "previewCropY")
        }
    }

    var previewCropScaleDouble: Double? {
        get { previewCropScale?.doubleValue }
        set {
            guard let value = newValue, value.isFinite else {
                setPrimitiveValue(nil, forKey: "previewCropScale")
                return
            }
            setPrimitiveValue(NSNumber(value: value), forKey: "previewCropScale")
        }
    }

    convenience init(mixId: UUID, type: String, createdAt: Date, context: NSManagedObjectContext) {
        let entity = NSEntityDescription.entity(forEntityName: "LocalMix", in: context)!
        self.init(entity: entity, insertInto: context)
        self.mixId = mixId
        self.type = type
        self.createdAt = createdAt
    }

    // MARK: - Convert to Mix

    func toMix(tags: [Tag] = []) -> Mix {
        let fileManager = LocalFileManager.shared

        // Decode widgets from JSON, or migrate legacy embed/file records
        let widgets: [MixWidget] = {
            // First try decoding widgetsJson
            if let data = widgetsJson,
               let decoded = try? JSONDecoder().decode([MixWidget].self, from: data) {
                return decoded
            }

            // Legacy migration: build widgets from old fields
            var migrated: [MixWidget] = []

            // Legacy embed → embed widget
            if type == "embed", let url = embedUrl, !url.isEmpty {
                let og: OGMetadata? = {
                    guard let data = embedOgJson else { return nil }
                    guard var og = try? JSONDecoder().decode(OGMetadata.self, from: data) else { return nil }
                    if let localPath = localEmbedOgImagePath, fileManager.fileExists(at: localPath) {
                        og = OGMetadata(
                            title: og.title,
                            description: og.description,
                            imageUrl: fileManager.fileURL(for: localPath).absoluteString,
                            host: og.host
                        )
                    }
                    return og
                }()
                migrated.append(MixWidget(
                    id: UUID(),
                    type: .embed,
                    embedUrl: url,
                    embedOg: og
                ))
            }

            // Legacy file → file widget
            if type == "file", let name = fileName, !name.isEmpty {
                migrated.append(MixWidget(
                    id: UUID(),
                    type: .file,
                    fileName: name,
                    fileLocalPath: localMediaPath
                ))
            }

            return migrated
        }()

        // Map old type strings to new MixType
        let mixType: MixType = {
            switch type {
            case "text": return .note
            case "embed": return .canvas
            case "file": return .canvas
            case "import": return .import
            default: return MixType(rawValue: type) ?? .note
            }
        }()

        // OG metadata for embed widget (non-legacy path — from widgetsJson)
        // Already handled inside the widgets array

        // New crop model — fall back to legacy previewScaleY for old mixes
        let cropX = previewCropXDouble
        let cropY = previewCropYDouble
        let cropScale: Double? = previewCropScaleDouble ?? previewScaleY?.doubleValue

        return Mix(
            id: mixId,
            type: mixType,
            createdAt: createdAt,
            title: title,
            tags: tags,
            textContent: textContent,
            audioUrl: localURL(localAudioPath, fileManager: fileManager),
            mediaUrl: localURL(localMediaPath, fileManager: fileManager),
            mediaThumbnailUrl: localURL(localMediaThumbnailPath, fileManager: fileManager),
            mediaIsVideo: mediaIsVideo,
            widgets: widgets,
            content: searchContent,
            screenshotUrl: localURL(localScreenshotPath, fileManager: fileManager),
            previewCropX: cropX,
            previewCropY: cropY,
            previewCropScale: cropScale,
            gradientTop: gradientTop,
            gradientBottom: gradientBottom,
            sourceUrl: sourceUrl,
            screenshotBucket: screenshotBucket
        )
    }

    private func localURL(_ localPath: String?, fileManager: LocalFileManager) -> String? {
        guard let localPath, fileManager.fileExists(at: localPath) else { return nil }
        return fileManager.fileURL(for: localPath).absoluteString
    }
}
