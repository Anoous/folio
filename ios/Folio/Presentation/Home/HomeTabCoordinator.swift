import Foundation
import Observation

enum HomeTab: CaseIterable, Identifiable, Equatable {
    case today
    case library
    case ask
    case me

    var id: Self { self }

    var title: String {
        switch self {
        case .today:
            "今日"
        case .library:
            "资料库"
        case .ask:
            "提问"
        case .me:
            "我"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            "house.fill"
        case .library:
            "books.vertical"
        case .ask:
            "bubble.left"
        case .me:
            "person"
        }
    }

    var pageTitle: String {
        switch self {
        case .today:
            "页集"
        case .library:
            "资料库"
        case .ask:
            "提问"
        case .me:
            "我"
        }
    }
}

struct HomeTabFocusRequest: Equatable, Identifiable {
    enum Target: Equatable {
        case librarySearch
        case askInput
    }

    let id = UUID()
    let target: Target
}

@MainActor
@Observable
final class HomeTabCoordinator {
    var selection: HomeTab
    var focusRequest: HomeTabFocusRequest?

    init(selection: HomeTab = .today) {
        self.selection = selection
    }

    func select(_ tab: HomeTab) {
        selection = tab
        focusRequest = nil
    }

    func openLibrarySearch() {
        selection = .library
        focusRequest = HomeTabFocusRequest(target: .librarySearch)
    }

    func openAsk() {
        selection = .ask
        focusRequest = HomeTabFocusRequest(target: .askInput)
    }
}
