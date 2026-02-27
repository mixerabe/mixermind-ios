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
        embedImage: UIImage? = nil,
        gradientTop: String? = nil,
        gradientBottom: String? = nil
    ) -> UIImage? {
        let view = MixCanvasContent(
            mixType: mixType,
            textContent: textContent,
            mediaThumbnail: mediaThumbnail,
            embedUrl: embedUrl,
            embedOg: embedOg,
            embedImage: embedImage,
            gradientTop: gradientTop,
            gradientBottom: gradientBottom
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
    /// then compute scaleY = canvasHeight / textHeight. Capped at 2.0 to show the beginning of the note.
    private static func textScaleY(for text: String) -> Double {
        guard !text.isEmpty else { return 1.0 }

        let font = UIFont.systemFont(ofSize: 17, weight: .regular)
        let maxWidth = canvasWidth - 48 // 24px padding each side, matching MixCanvasContent

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6

        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraphStyle],
            context: nil
        )

        let textHeight = ceil(boundingRect.height) + 120 + 200 // top + bottom padding
        guard textHeight > 0 else { return 1.0 }

        return min(Double(canvasHeight / textHeight), 2.0)
    }

    /// Extract dominant gradient colors from the top and bottom strips of a captured image.
    /// Returns hex strings like "#1a1a2e".
    static func extractGradients(from image: UIImage) -> (top: String, bottom: String) {
        let topColor = image.dominantColor(in: .top) ?? UIColor(red: 0.1, green: 0.1, blue: 0.18, alpha: 1)
        let bottomColor = image.dominantColor(in: .bottom) ?? UIColor(red: 0.09, green: 0.13, blue: 0.24, alpha: 1)
        return (top: topColor.hexString, bottom: bottomColor.hexString)
    }
}

// MARK: - Dominant Color Extraction

private struct RGBColor {
    let r, g, b: UInt8
}

enum ImageStrip {
    case top
    case bottom
}

extension UIImage {

    /// Returns the dominant color from a horizontal strip at the top or bottom of the image.
    func dominantColor(in strip: ImageStrip, rowCount: Int = 20, threshold: Double = 0.3) -> UIColor? {
        guard let pixels = extractPixels(from: strip, rowCount: rowCount) else { return nil }
        return findDominantColor(from: pixels, threshold: threshold)
    }

    // MARK: - Pixel Extraction

    private func extractPixels(from strip: ImageStrip, rowCount: Int) -> [RGBColor]? {
        guard let cgImage = self.cgImage else { return nil }

        let imgW = cgImage.width
        let imgH = cgImage.height
        let stripHeight = min(rowCount, imgH)
        guard stripHeight > 0, imgW > 0 else { return nil }

        let originY: Int
        switch strip {
        case .top:    originY = 0
        case .bottom: originY = imgH - stripHeight
        }

        let cropRect = CGRect(x: 0, y: originY, width: imgW, height: stripHeight)
        guard let cropped = cgImage.cropping(to: cropRect),
              let data = cropped.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }

        let bpp = cropped.bitsPerPixel / 8
        let bpr = cropped.bytesPerRow
        let w = cropped.width
        let h = cropped.height
        let sampling = 4 // sample every 4th pixel for speed

        var colors: [RGBColor] = []
        colors.reserveCapacity((w / sampling) * (h / sampling))

        for y in stride(from: 0, to: h, by: sampling) {
            for x in stride(from: 0, to: w, by: sampling) {
                let i = y * bpr + x * bpp
                colors.append(RGBColor(r: ptr[i], g: ptr[i + 1], b: ptr[i + 2]))
            }
        }
        return colors
    }

    // MARK: - Iterative Quantization

    /// Finds the dominant color by progressively coarsening quantization until a bucket
    /// exceeds the threshold percentage, then returns the true average of pixels in that bucket.
    private func findDominantColor(from pixels: [RGBColor], threshold: Double) -> UIColor? {
        guard !pixels.isEmpty else { return nil }

        var bestKey: Int?
        var bestShift = 0

        for shift in 0...7 {
            var counts: [Int: Int] = [:]
            for p in pixels {
                let key = (Int(p.r) >> shift) << 16 | (Int(p.g) >> shift) << 8 | (Int(p.b) >> shift)
                counts[key, default: 0] += 1
            }
            guard let top = counts.max(by: { $0.value < $1.value }) else { continue }
            if Double(top.value) / Double(pixels.count) >= threshold {
                bestKey = top.key
                bestShift = shift
                break
            }
        }

        guard let winningKey = bestKey else { return .white }

        // Average the actual pixel values in the winning bucket
        var sumR = 0, sumG = 0, sumB = 0, count = 0
        for p in pixels {
            let key = (Int(p.r) >> bestShift) << 16 | (Int(p.g) >> bestShift) << 8 | (Int(p.b) >> bestShift)
            if key == winningKey {
                sumR += Int(p.r); sumG += Int(p.g); sumB += Int(p.b)
                count += 1
            }
        }
        guard count > 0 else { return .white }

        return UIColor(
            red: CGFloat(sumR / count) / 255,
            green: CGFloat(sumG / count) / 255,
            blue: CGFloat(sumB / count) / 255,
            alpha: 1
        )
    }
}

// MARK: - UIColor → Hex

extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02x%02x%02x", ri, gi, bi)
    }
}
