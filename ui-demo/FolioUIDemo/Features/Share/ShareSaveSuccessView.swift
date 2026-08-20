import SwiftUI

struct ShareSaveSuccessView: View {
    let onDone: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 25)
                .fill(Color.white.opacity(0.92))
                .frame(height: 720)
                .padding(.horizontal, 30)
                .offset(y: -14)

            VStack(alignment: .leading, spacing: 0) {
                Text("保存到 Folio")
                    .font(FolioTypography.editorialBold(32, relativeTo: .largeTitle))
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .padding(.top, 49)

                ShareArticleCard()
                    .padding(.top, 29)

                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 46, weight: .light))
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                        .frame(width: 106, height: 106)
                        .background(FolioPalette.subtleGreen.opacity(0.55))
                        .clipShape(.circle)

                    Text("已保存")
                        .font(FolioTypography.editorialBold(32, relativeTo: .largeTitle))
                        .foregroundStyle(FolioPalette.inkGreenDeep)

                    Text("云端已确认接收，Folio 会继续处理内容。")
                        .font(.system(size: 17))
                        .foregroundStyle(FolioPalette.secondaryText)
                        .multilineTextAlignment(.center)

                    Text("现在可以返回了。")
                        .font(.system(size: 15))
                        .foregroundStyle(FolioPalette.tertiaryText)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity)

                Spacer()

                Button("完成", action: onDone)
                    .font(FolioTypography.editorial(19, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(FolioPalette.inkGreenDeep)
                    .clipShape(.rect(cornerRadius: 10))
                    .padding(.bottom, 25)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(FolioPalette.canvas)
            .clipShape(.rect(topLeadingRadius: 24, topTrailingRadius: 24))
            .padding(.top, 20)
            .sensoryFeedback(.success, trigger: true)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    ShareSaveSuccessView(onDone: {})
}
