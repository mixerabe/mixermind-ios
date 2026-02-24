import SwiftUI

struct LocalAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        if let url {
            if url.isFileURL {
                fileImage(url: url)
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        content(image)
                    case .failure:
                        placeholder()
                    default:
                        placeholder()
                    }
                }
            }
        } else {
            placeholder()
        }
    }

    @ViewBuilder
    private func fileImage(url: URL) -> some View {
        if let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            content(Image(uiImage: uiImage))
        } else {
            placeholder()
        }
    }
}
