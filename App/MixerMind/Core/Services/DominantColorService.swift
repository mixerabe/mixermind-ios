import UIKit

enum DominantColorService {
    /// Extracts the dominant color from an image by downsampling and averaging center pixels.
    /// Returns a hex string like "#RRGGBB".
    static func extractDominantColor(from image: UIImage) -> String {
        // Downsample to a small size for fast pixel access
        let targetSize = CGSize(width: 40, height: 40)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let cgImage = resized.cgImage else {
            return "#1C1A2D"
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return "#1C1A2D"
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Sample center 60% of the image
        let marginX = width / 5
        let marginY = height / 5
        let startX = marginX
        let endX = width - marginX
        let startY = marginY
        let endY = height - marginY

        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        var count: Double = 0

        for y in startY..<endY {
            for x in startX..<endX {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = Double(pixelData[offset])
                let g = Double(pixelData[offset + 1])
                let b = Double(pixelData[offset + 2])
                let a = Double(pixelData[offset + 3]) / 255.0

                // Skip fully transparent pixels
                guard a > 0.1 else { continue }

                totalR += r * a
                totalG += g * a
                totalB += b * a
                count += a
            }
        }

        guard count > 0 else { return "#1C1A2D" }

        let avgR = Int(totalR / count)
        let avgG = Int(totalG / count)
        let avgB = Int(totalB / count)

        return String(format: "#%02X%02X%02X", min(avgR, 255), min(avgG, 255), min(avgB, 255))
    }
}
