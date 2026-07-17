import SwiftUI

private struct QueryClientEnvironmentKey: EnvironmentKey {
    static let defaultValue = QueryClient.shared
}

public extension EnvironmentValues {
    var queryClient: QueryClient {
        get { self[QueryClientEnvironmentKey.self] }
        set { self[QueryClientEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func queryClient(_ queryClient: QueryClient) -> some View {
        environment(\.queryClient, queryClient)
    }
}
