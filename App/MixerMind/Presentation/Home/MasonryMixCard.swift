import SwiftUI

struct MasonryMixCard: View {
    let mix: Mix
    var onImageTap: (() -> Void)?

    private static let darkBg = Color(red: 0.08, green: 0.08, blue: 0.08)
    private static let canvasAspect: CGFloat = ScreenshotService.canvasAspect

    private var cropScale: Double { mix.previewCropScale ?? 1.0 }
    private var cropX: Double { mix.previewCropX ?? 0.5 }
    private var cropY: Double { mix.previewCropY ?? 0.5 }

    /// Cropped aspect ratio: full width, visible height = canvasHeight / cropScale
    private var croppedAspectRatio: CGFloat {
        Self.canvasAspect * cropScale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Image card
            ZStack {
                if let url = mix.screenshotUrl, let screenshotURL = URL(string: url) {
                    GeometryReader { geo in
                        let cardW = geo.size.width
                        let cardH = cardW / croppedAspectRatio
                        let imgH = cardW / Self.canvasAspect

                        // How much overflow we have in each axis
                        let overflowY = imgH - cardH
                        let overflowX: CGFloat = 0 // Full-width for now, cropX trims via wider frame

                        // cropY: 0 = top, 0.5 = center, 1 = bottom
                        let offsetY = -overflowY * cropY
                        // cropX: 0 = left, 0.5 = center, 1 = right
                        let offsetX = -overflowX * cropX

                        LocalAsyncImage(url: screenshotURL) { image in
                            image
                                .resizable()
                                .frame(width: cardW, height: imgH)
                                .offset(x: offsetX, y: offsetY)
                                .frame(width: cardW, height: cardH, alignment: .topLeading)
                                .clipped()
                        } placeholder: {
                            Self.darkBg
                                .frame(width: cardW, height: cardH)
                        }
                    }
                    .aspectRatio(croppedAspectRatio, contentMode: .fit)
                } else {
                    ZStack {
                        Self.darkBg
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .frame(height: 120)
                }

            }
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
            .onTapGesture { onImageTap?() }

            // Caption below card
            if let title = mix.title, !title.isEmpty {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .padding(.horizontal, 4)
            }
        }
    }
}
