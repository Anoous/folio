import SwiftUI

enum ReaderFontChoice: String, CaseIterable, Identifiable {
    case notoSerif
    case systemSans
    case systemRounded

    var id: Self { self }

    var title: String {
        switch self {
        case .notoSerif:
            "思源宋体"
        case .systemSans:
            "系统黑体"
        case .systemRounded:
            "系统圆体"
        }
    }

    var licenseNote: String {
        switch self {
        case .notoSerif:
            "SIL OFL 1.1"
        case .systemSans, .systemRounded:
            "随 iOS 提供"
        }
    }

    func regularFont(_ size: Double, relativeTo style: Font.TextStyle) -> Font {
        switch self {
        case .notoSerif:
            FolioTypography.editorial(size, relativeTo: style)
        case .systemSans:
            .system(style, design: .default, weight: .regular)
        case .systemRounded:
            .system(style, design: .rounded, weight: .regular)
        }
    }

    func emphasizedFont(_ size: Double, relativeTo style: Font.TextStyle) -> Font {
        switch self {
        case .notoSerif:
            FolioTypography.editorialBold(size, relativeTo: style)
        case .systemSans:
            .system(style, design: .default, weight: .semibold)
        case .systemRounded:
            .system(style, design: .rounded, weight: .semibold)
        }
    }
}
