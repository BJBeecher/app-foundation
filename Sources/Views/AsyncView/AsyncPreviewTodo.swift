import VLQuery

public struct AsyncPreviewTodo: Codable, Equatable, Sendable {
    public let id: Int
    public var title: String
    public var completed: Bool
    public var count: Int

    public init(id: Int, title: String, completed: Bool, count: Int) {
        self.id = id
        self.title = title
        self.completed = completed
        self.count = count
    }

    public static let sample = AsyncPreviewTodo(
        id: 1,
        title: "Preview todo",
        completed: false,
        count: 0
    )
}

public extension Fetch where Value == AsyncPreviewTodo {
    static let previewTodo = Fetch(key: ["preview", "todo", 1]) {
        AsyncPreviewTodo.sample
    }
}
