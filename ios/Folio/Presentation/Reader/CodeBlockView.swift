import SwiftUI

/// A code block view with a dark background, optional language label,
/// monospaced font, and horizontal scroll for long lines.
struct CodeBlockView: View {
    let code: String
    let language: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language label
            if !language.isEmpty {
                HStack {
                    Text(language.uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, Spacing.sm)
                        .padding(.top, Spacing.xs)

                    Spacer()
                }
            }

            // Code content with horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Typography.articleCode)
                    .foregroundStyle(.white.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        CodeBlockView(code: """
        func greet(name: String) -> String {
            return "Hello, \\(name)! Welcome to Folio."
        }
        """, language: "swift")

        CodeBlockView(code: """
        const result = await fetch('/api/articles');
        const data = await result.json();
        console.log(data);
        """, language: "javascript")

        CodeBlockView(code: "SELECT * FROM articles WHERE status = 'completed';", language: "sql")

        CodeBlockView(code: "print('Hello, World!')", language: "")
    }
    .padding()
}
