import SwiftUI

@MainActor
enum ScreenshotService {
    static let canvasWidth: CGFloat = 390
    static let canvasHeight: CGFloat = canvasWidth * 16 / 9 // 693.33 — 9:16 portrait

    /// Render `MixCanvasContent` offscreen at 9:16 and return a UIImage.
    static func capture(
        mixType: MixType,
        textContent: String,
        mediaThumbnail: UIImage?,
        embedUrl: String? = nil,
        embedOg: OGMetadata? = nil,
        embedImage: UIImage? = nil
    ) -> UIImage? {
        let view = MixCanvasContent(
            mixType: mixType,
            textContent: textContent,
            mediaThumbnail: mediaThumbnail,
            embedUrl: embedUrl,
            embedOg: embedOg,
            embedImage: embedImage
        )
        .frame(width: canvasWidth, height: canvasHeight)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }

    /// Compute vertical crop factor. scaleY > 1 means we only show the center 1/scaleY of the height.
    static func computeScaleY(
        mixType: MixType,
        textContent: String,
        mediaThumbnail: UIImage?,
        importHasVideo: Bool,
        embedImage: UIImage? = nil,
        embedUrl: String? = nil,
        embedOg: OGMetadata? = nil
    ) -> Double {
        switch mixType {
        case .photo, .video:
            return imageScaleY(for: mediaThumbnail)

        case .text:
            return textScaleY(for: textContent)

        case .audio:
            return 2.0

        case .embed:
            return embedScaleY(image: embedImage, url: embedUrl, og: embedOg)

        case .import:
            if importHasVideo {
                return imageScaleY(for: mediaThumbnail)
            } else {
                return 2.0
            }
        }
    }

    // MARK: - Private

    /// For photo/video: crop past black bars top/bottom when image is wider than canvas.
    private static func imageScaleY(for image: UIImage?) -> Double {
        guard let image else { return 1.0 }

        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0 else { return 1.0 }

        let imgAspect = imgW / imgH
        let canvasAspect = canvasWidth / canvasHeight

        if imgAspect > canvasAspect {
            // Wider than canvas → scaledToFit leaves black bars top/bottom
            let fitHeight = canvasWidth / imgAspect
            return min(Double(canvasHeight / fitHeight), 2.5)
        }
        // Taller or same — fills width, no vertical bars to crop
        return 1.0
    }

    private static func textScaleY(for text: String) -> Double {
        let count = text.count
        if count < 20 { return 2.2 }
        if count < 50 { return 2.0 }
        if count < 100 { return 1.8 }
        if count < 200 { return 1.5 }
        return 1.3
    }

    /// Render the embed card to measure its height, then compute how much to crop vertically.
    private static func embedScaleY(image: UIImage?, url: String?, og: OGMetadata?) -> Double {
        guard let image, let url else { return 1.0 }

        let cardWidth: CGFloat = canvasWidth - 64 // 32px padding each side
        let cardView = StaticEmbedCard(urlString: url, og: og, image: image)
            .frame(width: cardWidth)

        let renderer = ImageRenderer(content: cardView)
        renderer.scale = 1.0
        guard let measured = renderer.uiImage else { return 1.0 }

        let cardHeight = measured.size.height
        return min(Double(canvasHeight / cardHeight), 2.5)
    }
}
