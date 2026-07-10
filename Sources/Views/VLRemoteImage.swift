import Kingfisher
import SwiftUI

public struct VLRemoteImage<RequestModifier: AsyncImageDownloadRequestModifier>: View {
    let url: URL?
    let contentMode: SwiftUI.ContentMode
    let requestModifier: RequestModifier

    @Environment(\.displayScale) private var scale

    @State private var placeholder: (() -> AnyView)?
    @State private var failureView: (() -> AnyView)?

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
        GeometryReader { proxy in
            image(size: proxy.size)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let downsamplingSize = downsamplingSize(for: size)

        if let url {
            KFImage(url)
                .cacheOriginalImage()
                .requestModifier(requestModifier)
                .backgroundDecode()
                .setProcessor(DownsamplingImageProcessor(size: downsamplingSize))
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

    private func downsamplingSize(for size: CGSize) -> CGSize {
        CGSize(
            width: ceil(max(size.width, 1) * scale),
            height: ceil(max(size.height, 1) * scale)
        )
    }
}
