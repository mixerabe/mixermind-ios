import SwiftUI

@MainActor
enum ScreenshotService {
    static let canvasWidth: CGFloat = 390
    static let canvasHeight: CGFloat = canvasWidth * 21 / 9 // 910 — 9:21 portrait
    static let canvasAspect: CGFloat = 9.0 / 21.0 // width / height

    // MARK: - Text Bucket

    enum TextBucket: String {
        case small, medium, large

        var containerWidth: CGFloat {
            switch self {
            case .small:  return 272
            case .medium: return 342
            case .large:  return 382
            }
        }

        var canvasWidth: CGFloat { containerWidth + 48 }
        var canvasHeight: CGFloat { canvasWidth * 21 / 9 }

        static var current: TextBucket {
            let screenWidth = UIScreen.main.bounds.width
            if screenWidth <= 375 { return .small }
            if screenWidth >= 415 { return .large }
            return .medium
        }

        init?(stored: String?) {
            guard let stored else { return nil }
            self.init(rawValue: stored)
        }
    }

    /// Render `MixCanvasContent` offscreen at 9:21 and return a UIImage.
    static func capture(
        mixType: MixType,
        textContent: String,
        mediaThumbnail: UIImage?,
        widgets: [MixWidget] = [],
        embedImage: UIImage? = nil,
        gradientTop: String? = nil,
        gradientBottom: String? = nil,
        textBucket: TextBucket? = nil
    ) -> UIImage? {
        let w: CGFloat
        let h: CGFloat
        if mixType == .note, let bucket = textBucket {
            w = bucket.canvasWidth
            h = bucket.canvasHeight
        } else {
            w = canvasWidth
            h = canvasHeight
        }

        let view = MixCanvasContent(
            mixType: mixType,
            textContent: textContent,
            mediaThumbnail: mediaThumbnail,
            widgets: widgets,
            embedImage: embedImage,
            gradientTop: gradientTop,
            gradientBottom: gradientBottom
        )
        .frame(width: w, height: h)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.uiImage
    }

    /// Preview crop: (cropX, cropY, cropScale).
    /// - cropX: 0.0 = left edge, 0.5 = center, 1.0 = right edge
    /// - cropY: 0.0 = top edge, 0.5 = center, 1.0 = bottom edge
    /// - cropScale: zoom factor (1.0 = no crop, 2.0 = show half the height)
    struct PreviewCrop {
        var cropX: Double = 0.5
        var cropY: Double = 0.5
        var cropScale: Double = 1.0
    }

    static func computeCrop(
        mixType: MixType,
        textContent: String,
        mediaThumbnail: UIImage?,
        widgets: [MixWidget] = [],
        embedImage: UIImage? = nil,
        textBucket: TextBucket? = nil
    ) -> PreviewCrop {
        switch mixType {
        case .note:
            return textCrop(for: textContent, bucket: textBucket)

        case .media:
            return imageCrop(for: mediaThumbnail)

        case .voice:
            return PreviewCrop(cropX: 0.5, cropY: 0.5, cropScale: 4.0)

        case .canvas:
            // canvasAspect = 9/21, square = 1.0, so scale = 1/canvasAspect = 21/9 ≈ 2.33
            let squareScale = Double(canvasHeight / canvasWidth)
            return PreviewCrop(cropX: 0.5, cropY: 0.5, cropScale: squareScale)

        case .`import`:
            if mediaThumbnail != nil {
                return imageCrop(for: mediaThumbnail)
            }
            return PreviewCrop(cropX: 0.5, cropY: 0.5, cropScale: 4.0)
        }
    }

    // MARK: - Private

    /// For photo/video: compute how much of the 9:21 canvas the fitted image occupies.
    /// `.scaledToFit()` scales the image to fill the width, so its rendered height = canvasWidth / imageAspect.
    /// cropScale = canvasHeight / renderedHeight — i.e. how many times the image fits vertically.
    /// cropY stays 0.5 because ZStack centers the image.
    private static func imageCrop(for image: UIImage?) -> PreviewCrop {
        guard let image else { return PreviewCrop() }
        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0 else { return PreviewCrop() }

        let imageAspect = imgW / imgH  // e.g. 1.0 for square, 1.78 for 16:9
        let fittedHeight = canvasWidth / imageAspect  // height when scaled to fit width

        if fittedHeight < canvasHeight {
            // Image is wider than canvas — has black bars top/bottom
            let scale = min(Double(canvasHeight / fittedHeight), 5.0)
            return PreviewCrop(cropX: 0.5, cropY: 0.5, cropScale: scale)
        }
        // Image is taller than or matches canvas — no crop needed
        return PreviewCrop(cropX: 0.5, cropY: 0.5, cropScale: 1.0)
    }

    /// For text: tightly frame the actual text content on the canvas.
    /// MixCanvasContent lays out text with .padding(.top, 120) and .padding(.bottom, 200).
    /// We measure the real text height, then compute a crop window that starts just above
    /// the first line and ends just below the last line.
    private static func textCrop(for text: String, bucket: TextBucket? = nil) -> PreviewCrop {
        guard !text.isEmpty else { return PreviewCrop() }

        let bucketCanvasWidth = bucket?.canvasWidth ?? canvasWidth
        let bucketCanvasHeight = bucket?.canvasHeight ?? canvasHeight

        let font = UIFont.systemFont(ofSize: 17, weight: .regular)
        let maxWidth = bucketCanvasWidth - 48 // 24px padding each side

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6

        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraphStyle],
            context: nil
        )

        let textContentHeight = ceil(boundingRect.height)
        guard textContentHeight > 0 else { return PreviewCrop() }

        // Where text sits on the canvas
        let textTop: CGFloat = 120        // .padding(.top, 120)
        let textBottom = textTop + textContentHeight
        let margin: CGFloat = 40          // breathing room above/below

        // Crop window: from just above text to just below text
        let cropTop = max(textTop - margin, 0)
        let cropBottom = min(textBottom + margin, bucketCanvasHeight)
        let cropWindowHeight = cropBottom - cropTop

        // cropScale = how much to zoom (canvas / visible)
        let scale = min(Double(bucketCanvasHeight / cropWindowHeight), 5.0)

        // cropY = where the center of the crop window sits relative to the overflow
        let overflow = bucketCanvasHeight - cropWindowHeight
        let cropY: Double = overflow > 0 ? min(Double(cropTop / overflow), 1.0) : 0.5

        return PreviewCrop(cropX: 0.5, cropY: cropY, cropScale: scale)
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
