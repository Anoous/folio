import SwiftUI

struct ReaderAppearanceSheet: View {
    @Binding var selectedFont: ReaderFontChoice
    @Binding var selectedTheme: ReaderTheme
    @Environment(\.dismiss) private var dismiss

    private let themeColumns = Array(
        repeating: GridItem(.flexible(), spacing: 10),
        count: ReaderTheme.allCases.count
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("阅读背景")
                            .font(.headline)

                        LazyVGrid(columns: themeColumns, spacing: 12) {
                            ForEach(ReaderTheme.allCases) { theme in
                                ReaderThemeButton(theme: theme, selection: $selectedTheme)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("阅读字体")
                            .font(.headline)

                        ForEach(ReaderFontChoice.allCases) { font in
                            ReaderFontButton(font: font, selection: $selectedFont)
                        }
                    }

                    Text("思源宋体采用 SIL Open Font License 1.1；系统字体由 iOS 提供，不随 App 复制分发字体文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(FolioPalette.canvas)
            .navigationTitle("阅读外观")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: close)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func close() {
        dismiss()
    }
}
