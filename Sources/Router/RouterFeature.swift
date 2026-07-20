import ComposableArchitecture
import Foundation

@Reducer
public struct RouterFeature<Route: RouterDestination>: Sendable {
    private let routerService: NavigationRouter<Route>

    public init(routerService: NavigationRouter<Route>) {
        self.routerService = routerService
    }

    @ObservableState
    public struct State: Equatable {
        public var destinations: [Route]
        public var presentedSheet: Route?
        public var presentedAlert: PopupAlert?
        public var isAlertPresented: Bool
        public var loadingMessage: String?
        public var shownLoadingString: String?

        public init(
            destinations: [Route] = [],
            presentedSheet: Route? = nil,
            presentedAlert: PopupAlert? = nil,
            isAlertPresented: Bool = false,
            loadingMessage: String? = nil,
            shownLoadingString: String? = nil
        ) {
            self.destinations = destinations
            self.presentedSheet = presentedSheet
            self.presentedAlert = presentedAlert
            self.isAlertPresented = isAlertPresented
            self.loadingMessage = loadingMessage
            self.shownLoadingString = shownLoadingString
        }
    }

    public enum Action: BindableAction {
        case binding(BindingAction<State>)
        case observeDestinations
        case observeSheets
        case observeAlerts
        case observeLoader
        case setDestinations([Route])
        case setSheet(Route?)
        case setAlert(PopupAlert?)
        case setLoadingMessage(String?)
        case setLoadingString(String?)
        case destinationsDidUpdate([Route])
        case sheetDidUpdate(Route?)
        case alertDidDismiss
        case isShowingAlertDidUpdate(Bool)
        case goTo(Route)
    }

    public var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .observeDestinations:
                return .run { send in
                    for await destinations in await routerService.destinationsStream {
                        await send(.setDestinations(destinations))
                    }
                }

            case .observeSheets:
                return .run { send in
                    for await sheet in await routerService.sheetStream {
                        await send(.setSheet(sheet))
                    }
                }

            case .observeAlerts:
                return .run { send in
                    for await alert in await routerService.alertStream {
                        await send(.setAlert(alert))
                    }
                }

            case .observeLoader:
                return .run { send in
                    for await message in await routerService.loadingStream {
                        await send(.setLoadingMessage(message), animation: .spring(duration: 0.15))
                    }
                }

            case .setDestinations(let destinations):
                state.destinations = destinations
                return .none

            case .setSheet(let sheet):
                state.presentedSheet = sheet
                return .none

            case .setAlert(let alert):
                state.presentedAlert = alert
                state.isAlertPresented = alert != nil
                return .none

            case .setLoadingMessage(let message), .setLoadingString(let message):
                state.loadingMessage = message
                state.shownLoadingString = message
                return .none

            case .destinationsDidUpdate(let destinations):
                return .run { _ in
                    await routerService.updateDestinations(with: destinations)
                }

            case .sheetDidUpdate(let sheet):
                guard sheet == nil else { return .none }
                return .run { _ in
                    await routerService.dismissSheet()
                }

            case .alertDidDismiss:
                state.isAlertPresented = false
                return .run { _ in
                    await routerService.dismissAlert()
                }

            case .isShowingAlertDidUpdate(let isShowing):
                guard !isShowing else { return .none }
                state.isAlertPresented = false
                return .run { _ in
                    await routerService.dismissAlert()
                }

            case .goTo(let destination):
                return .run { _ in
                    await routerService.navigateTo(destination)
                }

            case .binding:
                return .none
            }
        }
    }
}
