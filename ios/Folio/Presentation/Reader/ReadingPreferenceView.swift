import SwiftUI

struct ReadingPreferenceView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ReadingPreferenceKeys.fontSize) private var fontSize: Double = 17

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                fontSizeSection
                Spacer()
            }
            .padding(Spacing.screenPadding)
            .navigationTitle(String(localized: "reader.prefs.title", defaultValue: "Reading"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(String(localized: "reader.prefs.done", defaultValue: "Done"))
                            .foregroundStyle(Color.folio.accent)
                    }
                }
            }
        }
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(String(localized: "reader.prefs.fontSize", defaultValue: "Font Size"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            HStack(spacing: Spacing.md) {
                Text("A")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.folio.textSecondary)

                Slider(value: $fontSize, in: 14...24, step: 1)
                    .tint(Color.folio.accent)

                Text("A")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.folio.textSecondary)
            }

            Text("\(Int(fontSize))pt")
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

#Preview {
    ReadingPreferenceView()
}
