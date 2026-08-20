import Foundation

enum DemoCaptureFailure: Equatable {
    case offline
    case sessionExpired
    case capacityFull
    case timeout

    var title: String {
        switch self {
        case .offline:
            "尚未保存"
        case .sessionExpired:
            "需要重新登录"
        case .capacityFull:
            "云端空间已满"
        case .timeout:
            "暂时无法确认"
        }
    }

    var message: String {
        switch self {
        case .offline:
            "当前没有网络，链接没有进入本地队列。联网后可以安全重试。"
        case .sessionExpired:
            "登录状态已失效，链接尚未提交。重新登录后再试一次。"
        case .capacityFull:
            "已有内容仍可阅读和删除。释放空间后才能继续收藏。"
        case .timeout:
            "云端是否接收仍不确定。Folio 会使用同一请求安全重试，不会创建重复内容。"
        }
    }

    var actionTitle: String {
        switch self {
        case .offline, .timeout:
            "重试"
        case .sessionExpired:
            "重新登录"
        case .capacityFull:
            "管理空间"
        }
    }

    var symbol: String {
        switch self {
        case .offline:
            "wifi.slash"
        case .sessionExpired:
            "person.crop.circle.badge.exclamationmark"
        case .capacityFull:
            "externaldrive.badge.exclamationmark"
        case .timeout:
            "clock.badge.exclamationmark"
        }
    }
}
