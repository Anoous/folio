import SwiftUI

enum ReaderTheme: String, CaseIterable, Identifiable {
    case paper
    case parchment
    case mint
    case sky

    var id: Self { self }

    var title: String {
        switch self {
        case .paper:
            "宣纸"
        case .parchment:
            "米黄"
        case .mint:
            "薄荷"
        case .sky:
            "雾蓝"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .paper:
            FolioPalette.canvas
        case .parchment:
            Color(.sRGB, red: 0.976, green: 0.950, blue: 0.872)
        case .mint:
            Color(.sRGB, red: 0.925, green: 0.966, blue: 0.927)
        case .sky:
            Color(.sRGB, red: 0.930, green: 0.949, blue: 0.982)
        }
    }

    var textColor: Color {
        Color(.sRGB, red: 0.12, green: 0.14, blue: 0.13)
    }

    var headingColor: Color {
        FolioPalette.inkGreenDeep
    }

    var quoteBackgroundColor: Color {
        Color.white.opacity(0.46)
    }

    var quoteRuleColor: Color {
        Color(.sRGB, red: 0.55, green: 0.38, blue: 0.17)
    }
}
