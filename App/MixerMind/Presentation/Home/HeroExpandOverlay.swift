import SwiftUI

struct HeroExpandOverlay: View, Animatable {
    @Environment(\.displayScale) private var displayScale

    let screenshotURL: URL
    let sourceFrame: CGRect
    let cropX: CGFloat
    let cropY: CGFloat
    let cropScale: CGFloat

    var progress: CGFloat

    private static let canvasAspect: CGFloat = ScreenshotService.canvasAspect

    init(screenshotURL: URL, expanded: Bool, sourceFrame: CGRect,
         cropX: CGFloat, cropY: CGFloat, cropScale: CGFloat) {
        self.screenshotURL = screenshotURL
        self.sourceFrame = sourceFrame
        self.cropX = cropX
        self.cropY = cropY
        self.cropScale = cropScale
        self.progress = expanded ? 1.0 : 0.0
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private func snapToPixel(_ value: CGFloat) -> CGFloat {
        guard displayScale > 0 else { return value }
        return (value * displayScale).rounded() / displayScale
    }

    var body: some View {
        let screen = UIScreen.main.bounds
        let canvasW = screen.width
        let canvasH = canvasW / Self.canvasAspect

        let croppedAspect = Self.canvasAspect * cropScale

        // Card dimensions
        let cardW = sourceFrame.width
        let cardClipH = cardW / croppedAspect
        let cardImgH = cardW / Self.canvasAspect

        // Clamp and snap
        let rawT = min(max(progress, 0), 1)
        let t = rawT > 0.999 ? 1 : rawT

        let currentW = snapToPixel(cardW + (canvasW - cardW) * t)
        let currentImgH = snapToPixel(cardImgH + (canvasH - cardImgH) * t)
        let currentClipH = snapToPixel(cardClipH + (canvasH - cardClipH) * t)
        let currentX = snapToPixel(sourceFrame.midX + (canvasW / 2 - sourceFrame.midX) * t)
        let currentY = snapToPixel(sourceFrame.midY + (canvasH / 2 - sourceFrame.midY) * t)
        let currentRadius: CGFloat = 12 + (16 - 12) * t

        // Animate crop offset from card position to center (0 offset at full expansion)
        let overflowY = currentImgH - currentClipH
        let currentCropY = cropY + (0.5 - cropY) * t  // lerp toward 0.5
        let offsetY = -overflowY * currentCropY

        LocalAsyncImage(url: screenshotURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: currentW, height: currentImgH)
                .offset(y: offsetY)
                .frame(width: currentW, height: currentClipH, alignment: .topLeading)
                .clipped()
        } placeholder: {
            Color(red: 0.08, green: 0.08, blue: 0.08)
        }
        .clipShape(.rect(cornerRadius: currentRadius))
        .position(x: currentX, y: currentY)
    }
}
