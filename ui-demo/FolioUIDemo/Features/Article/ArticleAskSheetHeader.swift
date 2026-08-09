import SwiftUI

struct ArticleAskSheetHeader: View {
    let onHide: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            FolioPageMascot(size: 28)

            Text("问这篇")
                .font(.title3.bold())
                .foregroundStyle(FolioPalette.inkGreenDeep)

            Spacer()

            Button("隐藏答疑", systemImage: "chevron.down", action: onHide)
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle(FolioPalette.inkGreenDeep)
                .frame(width: FolioMetrics.minimumTapTarget, height: FolioMetrics.minimumTapTarget)
                .background(FolioPalette.subtleGreen, in: .circle)
                .buttonStyle(FolioPressButtonStyle())
        }
        .padding(.horizontal, FolioMetrics.libraryInset)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}
