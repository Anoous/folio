import Foundation

enum DemoCaptureSuccess: Equatable {
    case accepted(host: String)
    case duplicate(host: String)

    var title: String {
        switch self {
        case .accepted:
            "已接收 · 正在处理"
        case .duplicate:
            "已经收藏过"
        }
    }
}
