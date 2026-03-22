import SwiftUI
import AuthenticationServices

struct OnboardingView: View {
    @AppStorage(AppConstants.onboardingCompletedKey) private var hasCompletedOnboarding = false
    @Environment(AuthViewModel.self) private var authViewModel: AuthViewModel?
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage = 0
    let onComplete: () -> Void

    private let totalPages = 6

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    TabView(selection: $currentPage) {
                        brandPage.tag(0)
                        savePage.tag(1)
                        rememberPage.tag(2)
                        usePage.tag(3)
                        loginPage.tag(4)
                        startPage.tag(5)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(Motion.settle, value: currentPage)

                    // Bottom area: dots + continue button
                    bottomBar
                }

                // Skip button (pages 0–3 only)
                if currentPage <= 3 {
                    Button {
                        withAnimation(Motion.settle) {
                            currentPage = 4
                        }
                    } label: {
                        Text("跳过")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.folio.textTertiary)
                            .padding(Spacing.xs)
                    }
                    .padding(.trailing, Spacing.screenPadding)
                    .padding(.top, Spacing.xs)
                }
            }
            .background(Color.folio.background)
        }
        .onChange(of: authViewModel?.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated == true {
                withAnimation(Motion.settle) {
                    currentPage = 5
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: Spacing.md) {
            // Dot indicators
            HStack(spacing: Spacing.xs) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.folio.textPrimary : Color.folio.textQuaternary)
                        .frame(width: index == currentPage ? 20 : 6, height: 6)
                        .animation(Motion.quick, value: currentPage)
                }
            }

            // Continue button (pages 0–3 only)
            if currentPage <= 3 {
                Button {
                    withAnimation(Motion.settle) {
                        currentPage += 1
                    }
                } label: {
                    Text("继续")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.folio.background)
                        .frame(maxWidth: 300)
                        .padding(.vertical, 15)
                        .background(Color.folio.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding(.horizontal, 44)
        .padding(.bottom, 40)
        .padding(.top, Spacing.md)
    }

    // MARK: - Page 0: Brand

    private var brandPage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "book.closed")
                .font(.system(size: 72))
                .foregroundStyle(Color.folio.textPrimary)
                .opacity(0.12)
                .padding(.bottom, 40)

            Text("Folio \u{00B7} 页集")
                .font(Typography.v3OnboardingBrand)
                .foregroundStyle(Color.folio.textTertiary)
                .tracking(1)
                .padding(.bottom, Spacing.xs)

            Text("Folio 记得。\n然后帮你也记得。")
                .font(Typography.v3OnboardingTitle)
                .foregroundStyle(Color.folio.textPrimary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.bottom, Spacing.sm)

            Text("你读过的每一篇好文章，\n都值得被记住。")
                .font(.system(size: 16))
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(16 * 0.65 - 16 * 0.35) // lineHeight 1.65 approximation

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 44)
    }

    // MARK: - Page 1: Save (存)

    private var savePage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 64))
                .foregroundStyle(Color.folio.textPrimary)
                .opacity(0.12)
                .padding(.bottom, 40)

            Text("存")
                .font(Typography.v3OnboardingTitle)
                .foregroundStyle(Color.folio.textPrimary)
                .padding(.bottom, Spacing.sm)

            Text("从 Safari、微信、Twitter……\n一键分享到 Folio。\nAI 自动阅读、理解、提炼洞察。")
                .font(.system(size: 16))
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(16 * 0.65 - 16 * 0.35)

            // Preview card
            VStack(alignment: .leading, spacing: 10) {
                Text("洞察摘要")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.folio.textQuaternary)
                    .tracking(1)
                    .textCase(.uppercase)

                Text("失败的根因不是技术能力不足，而是问题定义错误。")
                    .font(Font.custom("LXGWWenKaiTC-Regular", size: 15))
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(15 * 0.6)

                Text("来自《为什么 90% 的 AI 项目失败了》")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.folio.textQuaternary)
            }
            .padding(18)
            .frame(maxWidth: 300, alignment: .leading)
            .background(Color.folio.echoBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 28)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 44)
    }

    // MARK: - Page 2: Remember (记)

    private var rememberPage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.folio.textPrimary)
                .opacity(0.12)
                .padding(.bottom, 40)

            Text("记")
                .font(Typography.v3OnboardingTitle)
                .foregroundStyle(Color.folio.textPrimary)
                .padding(.bottom, Spacing.sm)

            Text("间隔重复，帮你真正记住。\nFolio 在你快忘记的时候提问，\n你只需 10 秒回忆。")
                .font(.system(size: 16))
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(16 * 0.65 - 16 * 0.35)

            // Echo card mockup
            VStack(spacing: 14) {
                Text("✦ Echo")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.folio.textQuaternary)
                    .tracking(1)
                    .textCase(.uppercase)

                Text("还记得 AI 项目失败\n最反直觉的结论吗？")
                    .font(Font.custom("LXGWWenKaiTC-Regular", size: 15))
                    .foregroundStyle(Color.folio.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(15 * 0.6)

                HStack(spacing: Spacing.xs) {
                    echoButton(title: "记得")
                    echoButton(title: "忘了")
                }
            }
            .padding(20)
            .frame(maxWidth: 300)
            .background(Color.folio.echoBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 28)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 44)
    }

    private func echoButton(title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.folio.textSecondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.folio.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.folio.separator, lineWidth: 0.5)
            )
    }

    // MARK: - Page 3: Use (用)

    private var usePage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(Color.folio.textPrimary)
                .opacity(0.12)
                .padding(.bottom, 40)

            Text("用")
                .font(Typography.v3OnboardingTitle)
                .foregroundStyle(Color.folio.textPrimary)
                .padding(.bottom, Spacing.sm)

            Text("用自然语言提问，\nFolio 综合你的收藏回答，\n溯源到每一篇原文。")
                .font(.system(size: 16))
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(16 * 0.65 - 16 * 0.35)

            // Q&A mockup
            VStack(alignment: .leading, spacing: 0) {
                Text("你问")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.folio.textQuaternary)
                    .tracking(1)
                    .textCase(.uppercase)
                    .padding(.bottom, 10)

                Text("关于用户留存有哪些方法？")
                    .font(Font.custom("LXGWWenKaiTC-Regular", size: 14))
                    .foregroundStyle(Color.folio.textTertiary)
                    .padding(.bottom, Spacing.sm)

                Text("Folio 答")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.folio.textQuaternary)
                    .tracking(1)
                    .textCase(.uppercase)
                    .padding(.bottom, 10)

                Text("留存的本质是习惯设计，不是功能堆砌。触发\u{2192}行动\u{2192}奖赏\u{2192}投入…")
                    .font(Font.custom("LXGWWenKaiTC-Regular", size: 15))
                    .foregroundStyle(Color.folio.textPrimary)
                    .lineSpacing(15 * 0.6)
                    .padding(.bottom, Spacing.xs)

                Text("基于你的 5 篇相关收藏")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.folio.textQuaternary)
            }
            .padding(18)
            .frame(maxWidth: 300, alignment: .leading)
            .background(Color.folio.echoBg)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.top, 28)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 44)
    }

    // MARK: - Page 4: Login

    private var loginPage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "person.crop.circle")
                .font(.system(size: 56))
                .foregroundStyle(Color.folio.textPrimary)
                .opacity(0.12)
                .padding(.bottom, 40)

            Text("登录以同步你的知识")
                .font(Font.custom("LXGWWenKaiTC-Medium", size: 24))
                .foregroundStyle(Color.folio.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, Spacing.sm)

            Text("登录后可在多设备间同步收藏。\n不登录也可以使用全部功能。")
                .font(.system(size: 16))
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(16 * 0.65 - 16 * 0.35)

            // Login buttons
            VStack(spacing: Spacing.sm) {
                // Apple Sign In
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    Task {
                        await authViewModel?.handleAppleSignIn(result: result)
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: 300)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Email login
                NavigationLink {
                    EmailAuthView()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope")
                        Text("邮箱登录")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.folio.textPrimary)
                    .frame(maxWidth: 300)
                    .frame(height: 50)
                    .background(Color.folio.echoBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.folio.separator, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)

                // Skip login
                Button {
                    withAnimation(Motion.settle) {
                        currentPage = 5
                    }
                } label: {
                    Text("不登录，直接使用")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.folio.textTertiary)
                        .padding(.vertical, Spacing.xs)
                }
            }
            .padding(.top, 36)

            if let error = authViewModel?.errorMessage {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.error)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.xs)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 44)
    }

    // MARK: - Page 5: Start

    private var startPage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "book.closed")
                .font(.system(size: 72))
                .foregroundStyle(Color.folio.textPrimary)
                .opacity(0.12)
                .padding(.bottom, 40)

            Text("准备好了")
                .font(Typography.v3OnboardingTitle)
                .foregroundStyle(Color.folio.textPrimary)
                .padding(.bottom, Spacing.sm)

            Text("从任何 App 分享一个链接到 Folio，\n你的知识旅程就此开始。")
                .font(.system(size: 16))
                .foregroundStyle(Color.folio.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(16 * 0.65 - 16 * 0.35)

            Button {
                completeOnboarding()
            } label: {
                Text("开始使用")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.folio.background)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 15)
                    .background(Color.folio.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.top, 36)

            Text("你可以在设置中随时登录")
                .font(.system(size: 13))
                .foregroundStyle(Color.folio.textQuaternary)
                .padding(.top, 14)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 44)
    }

    // MARK: - Actions

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        onComplete()
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
