import Kingfisher
import SwiftUI

public struct VLRemoteImage<RequestModifier: AsyncImageDownloadRequestModifier>: View {
    let url: URL?
    let contentMode: SwiftUI.ContentMode
    let requestModifier: RequestModifier

    @Environment(\.displayScale) private var scale

    @State private var placeholder: (() -> AnyView)?
    @State private var failureView: (() -> AnyView)?
    @State private var size: CGSize?

    public init(
        url: URL?,
        contentMode: SwiftUI.ContentMode = .fill,
        requestModifier: RequestModifier
    ) {
        self.url = url
        self.contentMode = contentMode
        self.requestModifier = requestModifier
    }

    public var body: some View {
        ZStack {
            if let size {
                image(size: size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            GeometryReader { proxy in
                Color.clear.task(id: proxy.size) {
                    withAnimation {
                        self.size = proxy.size
                    }
                }
            }
        }
    }

    public func placeholder<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> Self {
        self.placeholder = { AnyView(content()) }
        return self
    }

    public func failureView<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> Self {
        self.failureView = { AnyView(content()) }
        return self
    }

    @ViewBuilder
    private func image(size: CGSize) -> some View {
        if let url {
            KFImage(url)
                .cacheOriginalImage()
                .requestModifier(requestModifier)
                .backgroundDecode()
                .setProcessor(DownsamplingImageProcessor(size: CGSize(width: size.width * scale, height: size.height * scale)))
                .resizable()
                .onFailureView {
                    failureView?()
                }
                .placeholder {
                    placeholder?()
                }
                .aspectRatio(contentMode: contentMode)
                .frame(width: size.width, height: size.height)
                .clipped()
                .contentShape(Rectangle())
        } else {
            if let placeholder {
                placeholder()
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
            }
        }
    }
}
