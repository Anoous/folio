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

    var backgroundColor: Color {
        switch self {
        case .system: return Color.folio.background
        case .light: return .white
        case .dark: return Color(white: 0.12)
        case .sepia: return Color(red: 0.96, green: 0.93, blue: 0.87)
        }
    }

    var textColor: Color {
        switch self {
        case .system: return Color.folio.textPrimary
        case .light: return Color(white: 0.1)
        case .dark: return Color(white: 0.88)
        case .sepia: return Color(red: 0.23, green: 0.20, blue: 0.16)
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .system: return Color.folio.textSecondary
        case .light: return Color(white: 0.4)
        case .dark: return Color(white: 0.6)
        case .sepia: return Color(red: 0.45, green: 0.40, blue: 0.33)
        }
    }
}

#Preview {
    ReadingPreferenceView()
}
