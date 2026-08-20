import SwiftUI

struct LibraryStatusAccessory: View {
    let status: DemoArticleStatus

    var body: some View {
        if status != .ready {
            Label(title, systemImage: symbol)
                .labelStyle(.titleOnly)
                .font(FolioTypography.editorial(13, relativeTo: .caption))
                .foregroundStyle(foregroundStyle)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(backgroundStyle)
                .clipShape(.capsule)
                .accessibilityLabel(title)
        }
    }

    private var title: String {
        switch status {
        case .accepted:
            "已接收"
        case .queued:
            "等待中"
        case .processing:
            "处理中"
        case .ready:
            "可阅读"
        case .partial:
            "部分完成"
        case .failed:
            "处理失败"
        }
    }

    private var symbol: String {
        switch status {
        case .accepted:
            "checkmark.circle"
        case .queued:
            "clock"
        case .processing:
            "arrow.triangle.2.circlepath"
        case .ready:
            "checkmark"
        case .partial:
            "exclamationmark.circle"
        case .failed:
            "xmark.circle"
        }
    }

    private var foregroundStyle: Color {
        status == .failed ? FolioPalette.danger : FolioPalette.inkGreenDeep
    }

    private var backgroundStyle: Color {
        status.needsAttention
            ? FolioPalette.evidence
            : FolioPalette.subtleGreen
    }
}
