import SwiftUI

enum FolioTypography {
    static func editorial(_ size: Double, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("NotoSerifSC-Regular", size: size, relativeTo: style)
    }

    static func editorialBold(_ size: Double, relativeTo style: Font.TextStyle = .headline) -> Font {
        .custom("NotoSerifSC-SemiBold", size: size, relativeTo: style)
    }

    static func wordmark(_ size: Double) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}
