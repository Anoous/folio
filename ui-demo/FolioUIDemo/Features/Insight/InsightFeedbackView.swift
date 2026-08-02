import SwiftUI

struct InsightFeedbackView: View {
    @State private var selectedFeedback: String?

    var body: some View {
        HStack(spacing: 14) {
            Text("这条洞察有帮助吗？")
                .font(FolioTypography.editorial(15, relativeTo: .body))

            Spacer()

            Button("有用", systemImage: "hand.thumbsup", action: selectHelpful)
                .buttonStyle(InsightFeedbackButtonStyle(isSelected: selectedFeedback == "有用"))

            Button("不准确", systemImage: "hand.thumbsdown", action: selectInaccurate)
                .buttonStyle(InsightFeedbackButtonStyle(isSelected: selectedFeedback == "不准确"))
        }
        .sensoryFeedback(.selection, trigger: selectedFeedback)
    }

    private func selectHelpful() {
        selectedFeedback = "有用"
    }

    private func selectInaccurate() {
        selectedFeedback = "不准确"
    }
}
