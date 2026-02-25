import SwiftUI

struct HeroExpandOverlay: View, Animatable {
    @Environment(\.displayScale) private var displayScale

    let screenshotURL: URL
    let sourceFrame: CGRect
    let previewScaleY: CGFloat

    var progress: CGFloat

    private static let canvasAspect: CGFloat = 9.0 / 17.0

    init(screenshotURL: URL, expanded: Bool, sourceFrame: CGRect, previewScaleY: CGFloat) {
        self.screenshotURL = screenshotURL
        self.sourceFrame = sourceFrame
        self.previewScaleY = previewScaleY
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
        let canvasH = canvasW * (17.0 / 9.0)

        let croppedAspect = Self.canvasAspect * previewScaleY

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

        LocalAsyncImage(url: screenshotURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: currentW, height: currentImgH)
        } placeholder: {
            Color(red: 0.08, green: 0.08, blue: 0.08)
        }
        .frame(width: currentW, height: currentClipH)
        .clipped()
        .clipShape(.rect(cornerRadius: currentRadius))
        .position(x: currentX, y: currentY)
    }
}
