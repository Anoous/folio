import SwiftUI

struct ReadingPreferenceView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ReadingPreferenceKeys.fontSize) private var fontSize: Double = 17
    @AppStorage(ReadingPreferenceKeys.lineSpacing) private var lineSpacing: Double = 11.9
    @AppStorage(ReadingPreferenceKeys.fontFamily) private var fontFamilyRawValue: String = ReadingFontFamily.notoSerif.rawValue
    @AppStorage(ReadingPreferenceKeys.theme) private var themeRawValue: String = ReadingTheme.system.rawValue

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                fontSizeSection
                lineSpacingSection
                fontFamilySection
                themeSection
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

    private var lineSpacingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("行距")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.folio.textPrimary)
                Spacer()
                Text(String(format: "%.1f", lineSpacing))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.folio.textTertiary)
            }
            Slider(value: $lineSpacing, in: 6...16, step: 1)
                .tint(Color.folio.accent)
        }
    }

    private var fontFamilySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("字体")
                .font(.system(size: 15))
                .foregroundStyle(Color.folio.textPrimary)

            HStack(spacing: 12) {
                ForEach(ReadingFontFamily.allCases, id: \.self) { family in
                    Button {
                        fontFamilyRawValue = family.rawValue
                    } label: {
                        VStack(spacing: 6) {
                            Text("文")
                                .font(family.previewFont)
                                .foregroundStyle(
                                    fontFamilyRawValue == family.rawValue
                                        ? Color.folio.accent
                                        : Color.folio.textPrimary
                                )
                            Text(family.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    fontFamilyRawValue == family.rawValue
                                        ? Color.folio.accent
                                        : Color.folio.textTertiary
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            fontFamilyRawValue == family.rawValue
                                ? Color.folio.accentSoft
                                : Color.folio.echoBg
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("主题")
                .font(.system(size: 15))
                .foregroundStyle(Color.folio.textPrimary)

            HStack(spacing: 12) {
                ForEach(ReadingTheme.allCases, id: \.self) { theme in
                    Button {
                        themeRawValue = theme.rawValue
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(theme.previewColor)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            themeRawValue == theme.rawValue
                                                ? Color.folio.accent
                                                : Color.folio.separator,
                                            lineWidth: themeRawValue == theme.rawValue ? 2 : 0.5
                                        )
                                )
                            Text(theme.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.folio.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ReadingPreferenceView()
}
