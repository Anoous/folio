import SwiftUI

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Typography.tag)
            .foregroundStyle(Color.folio.tagText)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(Color.folio.tagBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
    }
}

#Preview {
    HStack {
        TagChip(text: "Swift")
        TagChip(text: "iOS")
        TagChip(text: "SwiftUI")
    }
    .padding()
}
