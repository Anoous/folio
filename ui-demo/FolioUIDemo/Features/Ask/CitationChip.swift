import SwiftUI

struct CitationChip: View {
    let number: Int
    let action: () -> Void

    var body: some View {
        Button(number.formatted(), action: action)
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .foregroundStyle(FolioPalette.inkGreenDeep)
            .frame(width: 30, height: 44)
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(FolioPalette.inkGreenDeep, lineWidth: 0.8)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("查看来源 \(number)")
    }
}
