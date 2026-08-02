import Observation

@Observable
final class DemoStore {
    var isSignedIn = false
    var selectedTab = DemoTab.library
    var path: [DemoRoute] = []

    init(initialScreen: DemoScreen? = nil) {
        guard let initialScreen else { return }

        switch initialScreen {
        case .welcome:
            break
        case .library:
            isSignedIn = true
        case .reader:
            isSignedIn = true
            path = [.reader]
        case .insight:
            isSignedIn = true
            path = [.insight]
        case .evidence:
            isSignedIn = true
            path = [.evidence]
        case .askHome:
            isSignedIn = true
            selectedTab = .ask
        case .askAnswer:
            isSignedIn = true
            selectedTab = .ask
            path = [.askAnswer]
        case .askInsufficient:
            isSignedIn = true
            selectedTab = .ask
            path = [.askInsufficient]
        case .shareSuccess:
            isSignedIn = true
            path = [.shareSuccess]
        case .settings:
            isSignedIn = true
            path = [.settings]
        }
    }

    func signIn() {
        isSignedIn = true
    }

    func selectTab(_ tab: DemoTab) {
        selectedTab = tab
        path.removeAll()
    }

    func open(_ route: DemoRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func reset() {
        path.removeAll()
        selectedTab = .library
    }
}
