import SwiftUI
import VLQuery

public struct StandardAsyncView<Value: Codable & Sendable, Content: View>: View {
    @Environment(\.queryClient) private var queryClient

    private let fetch: Fetch<Value>
    private let content: (Binding<Value>) -> Content

    public init(
        fetch: Fetch<Value>,
        @ViewBuilder content: @escaping (Binding<Value>) -> Content
    ) {
        self.fetch = fetch
        self.content = content
    }

    public init(
        fetch: Fetch<Value>,
        @ViewBuilder content: @escaping (Value) -> Content
    ) {
        self.fetch = fetch
        self.content = { content($0.wrappedValue) }
    }

    public var body: some View {
        QueryView(fetch) { snapshot in
            switch snapshot.status {
            case .pending:
                ProgressView()
                    .tint(.secondary)
            case .success:
                if let value = snapshot.data {
                    content(
                        Binding(
                            get: { value },
                            set: { value in
                                Task {
                                    await queryClient.setQueryData(key: fetch.key, value)
                                }
                            }
                        )
                    )
                }
            case .failure:
                ContentUnavailableView(
                    "Unable to load content",
                    systemImage: "exclamationmark.icloud"
                )
            }
        }
    }
}

#Preview {
    StandardAsyncView(fetch: .previewTodo) { $todo in
        Text(todo.count, format: .number)

        Button("Update") {
            todo.count += 1
        }
    }
}
