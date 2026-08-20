import SwiftUI

struct LibraryUndoBanner: View {
    let articleTitle: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .foregroundStyle(FolioPalette.secondaryText)
                .accessibilityHidden(true)

            Text("已删除“\(articleTitle)”")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button("撤销", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(minHeight: FolioMetrics.minimumTapTarget)
                .accessibilityIdentifier("library-undo-delete")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .background(.regularMaterial, in: .capsule)
        .shadow(color: Color.black.opacity(0.10), radius: 14, y: 5)
    }
}
