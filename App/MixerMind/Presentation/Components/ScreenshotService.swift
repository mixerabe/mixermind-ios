import SwiftUI

@MainActor
enum ScreenshotService {
    static let canvasWidth: CGFloat = 390
    static let canvasHeight: CGFloat = canvasWidth * 17 / 9 // 736.67 — 9:17 portrait

    /// Render `MixCanvasContent` offscreen at 9:17 and return a UIImage.
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
            return 1.8

        case .import:
            if importHasVideo {
                return imageScaleY(for: mediaThumbnail)
            } else {
                return 2.0
            }
        }
    }

    // MARK: - Private

    /// For photo/video: compare image aspect ratio to canvas aspect ratio.
    /// If the image is wider, it gets letterboxed (black bars top/bottom) via scaledToFit,
    /// so scaleY = canvasAspect / imageAspect (how much taller the canvas is vs the fitted image).
    private static func imageScaleY(for image: UIImage?) -> Double {
        guard let image else { return 1.0 }
        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0 else { return 1.0 }

        let imageAspect = imgW / imgH         // e.g. 16:9 landscape = 1.78
        let canvasAspect = canvasWidth / canvasHeight // 9:17 = 0.529

        // Image wider than canvas → letterboxed → crop the bars
        if imageAspect > canvasAspect {
            return min(imageAspect / canvasAspect, 2.5)
        }
        return 1.0
    }

    /// For text: measure how tall the text actually renders using the same font as MixCanvasContent,
    /// then compute scaleY = canvasHeight / textHeight.
    private static func textScaleY(for text: String) -> Double {
        guard !text.isEmpty else { return 1.0 }

        let fontSize = textFontSize(for: text)
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        let maxWidth = canvasWidth - 48 // 24px padding each side, matching MixCanvasContent

        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )

        let textHeight = ceil(boundingRect.height)
        guard textHeight > 0 else { return 1.0 }

        return min(Double(canvasHeight / textHeight), 2.5)
    }

    /// Matches MixCanvasContent.dynamicFontSize
    private static func textFontSize(for text: String) -> CGFloat {
        let length = text.count
        if length < 20 { return 32 }
        if length < 50 { return 26 }
        if length < 100 { return 22 }
        if length < 200 { return 18 }
        return 14
    }
}
