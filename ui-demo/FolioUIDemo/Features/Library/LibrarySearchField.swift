import SwiftUI

struct LibrarySearchField: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FolioPalette.tertiaryText)
                    .accessibilityHidden(true)

                TextField(.librarySearchPlaceholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("library-search-field")

                if !text.isEmpty {
                    Button(.clearSearch, systemImage: "xmark.circle.fill", action: clear)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(FolioPalette.tertiaryText)
                        .frame(
                            width: FolioMetrics.minimumTapTarget,
                            height: FolioMetrics.minimumTapTarget
                        )
                        .buttonStyle(.plain)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 2)
            .frame(minHeight: 48)
            .background(FolioPalette.surface, in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(FolioPalette.paperLine.opacity(0.9), lineWidth: 0.8)
            }

            Button(.cancelSearch, action: onCancel)
                .font(.subheadline.bold())
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(minWidth: FolioMetrics.minimumTapTarget, minHeight: FolioMetrics.minimumTapTarget)
        }
    }

    private func clear() {
        text = ""
    }
}
