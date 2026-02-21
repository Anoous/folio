import SwiftUI

/// A bottom sheet for adjusting reading preferences: font size, line spacing,
/// theme, and font family.
struct ReadingPreferenceView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("reader_fontSize") private var fontSize: Double = 17
    @AppStorage("reader_lineSpacing") private var lineSpacing: Double = 11.9
    @AppStorage("reader_theme") private var theme: String = ReadingTheme.system.rawValue
    @AppStorage("reader_fontFamily") private var fontFamily: String = ReadingFontFamily.notoSerif.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // MARK: - Font Size
                    fontSizeSection

                    Divider()

                    // MARK: - Line Spacing
                    lineSpacingSection

                    Divider()

                    // MARK: - Theme
                    themeSection

                    Divider()

                    // MARK: - Font Family
                    fontFamilySection

                    Divider()

                    // MARK: - Preview
                    previewSection
                }
                .padding(Spacing.screenPadding)
            }
            .navigationTitle(String(localized: "reader.prefs.title", defaultValue: "Reading Preferences"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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

    // MARK: - Font Size Section

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

    // MARK: - Line Spacing Section

    private var lineSpacingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(String(localized: "reader.prefs.lineSpacing", defaultValue: "Line Spacing"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            HStack(spacing: Spacing.md) {
                Image(systemName: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(Color.folio.textSecondary)

                Slider(value: $lineSpacing, in: 4...20, step: 1)
                    .tint(Color.folio.accent)

                Image(systemName: "text.alignleft")
                    .font(.body)
                    .foregroundStyle(Color.folio.textSecondary)
            }

            Text(String(format: "%.0fpt", lineSpacing))
                .font(Typography.caption)
                .foregroundStyle(Color.folio.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Theme Section

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(String(localized: "reader.prefs.theme", defaultValue: "Theme"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            HStack(spacing: Spacing.sm) {
                ForEach(ReadingTheme.allCases, id: \.self) { t in
                    themeButton(t)
                }
            }
        }
    }

    private func themeButton(_ readingTheme: ReadingTheme) -> some View {
        Button {
            theme = readingTheme.rawValue
        } label: {
            VStack(spacing: Spacing.xxs) {
                RoundedRectangle(cornerRadius: CornerRadius.medium)
                    .fill(readingTheme.previewColor)
                    .frame(width: 56, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .stroke(
                                theme == readingTheme.rawValue ? Color.folio.accent : Color.folio.separator,
                                lineWidth: theme == readingTheme.rawValue ? 2 : 1
                            )
                    )

                Text(readingTheme.displayName)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Font Family Section

    private var fontFamilySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(String(localized: "reader.prefs.fontFamily", defaultValue: "Font"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            ForEach(ReadingFontFamily.allCases, id: \.self) { family in
                Button {
                    fontFamily = family.rawValue
                } label: {
                    HStack {
                        Text(family.displayName)
                            .font(family.previewFont)
                            .foregroundStyle(Color.folio.textPrimary)

                        Spacer()

                        if fontFamily == family.rawValue {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.folio.accent)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(String(localized: "reader.prefs.preview", defaultValue: "Preview"))
                .font(Typography.listTitle)
                .foregroundStyle(Color.folio.textPrimary)

            Text("The quick brown fox jumps over the lazy dog. Swift is a powerful and intuitive programming language.")
                .font(currentPreviewFont)
                .foregroundStyle(Color.folio.textPrimary)
                .lineSpacing(CGFloat(lineSpacing))
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.folio.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.medium)
                        .stroke(Color.folio.separator, lineWidth: 0.5)
                )
        }
    }

    private var currentPreviewFont: Font {
        let family = ReadingFontFamily(rawValue: fontFamily) ?? .notoSerif
        return family.font(size: CGFloat(fontSize))
    }
}

// MARK: - Reading Theme

enum ReadingTheme: String, CaseIterable {
    case system
    case light
    case dark
    case sepia

    var displayName: String {
        switch self {
        case .system: return String(localized: "reader.theme.system", defaultValue: "System")
        case .light: return String(localized: "reader.theme.light", defaultValue: "Light")
        case .dark: return String(localized: "reader.theme.dark", defaultValue: "Dark")
        case .sepia: return String(localized: "reader.theme.sepia", defaultValue: "Sepia")
        }
    }

    var previewColor: Color {
        switch self {
        case .system: return Color(UIColor.systemBackground)
        case .light: return .white
        case .dark: return Color(white: 0.15)
        case .sepia: return Color(red: 0.96, green: 0.93, blue: 0.87)
        }
    }
}

// MARK: - Reading Font Family

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

#Preview {
    ReadingPreferenceView()
}
