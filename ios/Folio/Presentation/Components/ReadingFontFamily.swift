import SwiftUI

/// Font families available in the reading view.
enum ReadingFontFamily: String, CaseIterable {
    case notoSerif = "noto_serif"
    case system = "system"
    case serif = "serif"

    var displayName: String {
        switch self {
        case .notoSerif: return "Noto Serif SC"
        case .system: return "System (SF Pro)"
        case .serif: return "Georgia"
        }
    }

    var previewFont: Font {
        font(size: 16)
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .notoSerif: return Font.custom("Noto Serif SC", size: size)
        case .system: return Font.system(size: size)
        case .serif: return Font.custom("Georgia", size: size)
        }
    }
}
