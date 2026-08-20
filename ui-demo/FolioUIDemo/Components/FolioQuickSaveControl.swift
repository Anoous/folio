import SwiftUI

struct FolioQuickSaveControl: View {
    @Binding var phase: QuickSavePhase
    @Binding var text: String
    let glassNamespace: Namespace.ID
    let onSave: (URL) -> DemoCaptureResult
    let onRecover: (DemoCaptureFailure) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var isURLFieldFocused: Bool
    @State private var impactFeedbackTrigger = 0
    @State private var successFeedbackTrigger = 0
    @State private var pendingURL: URL?

    var body: some View {
        Group {
            switch phase {
            case .idle:
                Button("收藏链接", systemImage: "plus", action: expand)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(
                        width: FolioMetrics.tabBarHeight,
                        height: FolioMetrics.tabBarHeight
                    )
                    .background {
                        FolioGlassLens(
                            shape: Circle(),
                            tint: FolioPalette.inkGreen,
                            isProminent: true
                        )
                    }
                    .accessibilityIdentifier("quick-save")
                    .transition(phaseTransition)

            case .editing:
                HStack(spacing: 3) {
                    Button("取消收藏", systemImage: "xmark", action: collapse)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14, weight: .medium))
                        .frame(
                            width: FolioMetrics.minimumTapTarget,
                            height: FolioMetrics.minimumTapTarget
                        )

                    TextField("粘贴链接，收藏到 Folio", text: $text)
                        .font(.body)
                        .foregroundStyle(FolioPalette.inkGreenDeep)
                        .textInputAutocapitalization(.never)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .submitLabel(.send)
                        .focused($isURLFieldFocused)
                        .onSubmit(save)
                        .accessibilityIdentifier("quick-save-url-field")

                    Button("发送收藏", systemImage: "arrow.up", action: save)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(
                            width: FolioMetrics.minimumTapTarget,
                            height: FolioMetrics.minimumTapTarget
                        )
                        .background(
                            isValidURL
                                ? FolioPalette.inkGreenDeep
                                : FolioPalette.tertiaryText.opacity(0.28),
                            in: .circle
                        )
                        .disabled(!isValidURL)
                        .accessibilityIdentifier("quick-save-send")
                }
                .transition(phaseTransition)

            case .saving:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FolioPalette.inkGreen)

                    Text("正在收藏 \(displayHost)…")
                        .font(.body)
                        .foregroundStyle(FolioPalette.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在收藏链接")
                .transition(phaseTransition)

            case .succeeded(let success):
                Label(success.title, systemImage: successSymbol(for: success))
                    .font(.body)
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("quick-save-success")
                    .transition(phaseTransition)

            case .failed(let failure):
                HStack(spacing: 9) {
                    Image(systemName: failure.symbol)
                        .foregroundStyle(FolioPalette.danger)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(failure.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FolioPalette.inkGreenDeep)

                        Text(failure.message)
                            .font(.caption2)
                            .foregroundStyle(FolioPalette.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button(failure.actionTitle, action: recover)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 36)
                        .background(FolioPalette.inkGreenDeep, in: .capsule)
                        .accessibilityIdentifier("quick-save-recover")

                    Button("关闭提示", systemImage: "xmark", action: collapse)
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .transition(phaseTransition)
            }
        }
        .buttonStyle(FolioPressButtonStyle())
        .padding(.horizontal, phase.isExpanded ? 6 : 0)
        .frame(
            maxWidth: phase.isExpanded ? .infinity : nil,
            minHeight: FolioMetrics.tabBarHeight
        )
        .contentShape(.capsule)
        .background(
            reduceTransparency ? FolioPalette.surface.opacity(0.96) : .clear,
            in: .capsule
        )
        .glassEffect(controlGlass, in: .capsule)
        .glassEffectID("folio-save", in: glassNamespace)
        .glassEffectTransition(.matchedGeometry)
        .sensoryFeedback(
            .impact(weight: .light, intensity: 0.72),
            trigger: impactFeedbackTrigger
        )
        .sensoryFeedback(.success, trigger: successFeedbackTrigger)
        .onChange(of: phase, focusURLField)
        .task(id: phase, advanceDemoPhase)
    }

    private var isValidURL: Bool {
        QuickSaveURLValidator.normalizedURL(from: text) != nil
    }

    private var displayHost: String {
        QuickSaveURLValidator.displayHost(from: text)
    }

    private func expand() {
        impactFeedbackTrigger += 1
        withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
            phase = .editing
        }
    }

    private func collapse() {
        impactFeedbackTrigger += 1
        isURLFieldFocused = false
        text = ""
        pendingURL = nil
        withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
            phase = .idle
        }
    }

    private func save() {
        guard let normalizedURL = QuickSaveURLValidator.normalizedURL(from: text) else { return }
        impactFeedbackTrigger += 1
        isURLFieldFocused = false
        pendingURL = normalizedURL
        withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
            phase = .saving
        }
    }

    private func focusURLField(_ oldPhase: QuickSavePhase, _ newPhase: QuickSavePhase) {
        guard oldPhase != .editing, newPhase == .editing else { return }
        isURLFieldFocused = true
    }

    private func advanceDemoPhase() async {
        switch phase {
        case .saving:
            do {
                try await Task.sleep(for: .milliseconds(550))
            } catch {
                return
            }
            guard phase == .saving, let pendingURL else { return }
            let result = onSave(pendingURL)
            withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
                switch result {
                case .success(let success):
                    successFeedbackTrigger += 1
                    phase = .succeeded(success)
                case .failure(let failure):
                    phase = .failed(failure)
                }
            }

        case .succeeded:
            do {
                try await Task.sleep(for: .milliseconds(1_200))
            } catch {
                return
            }
            guard case .succeeded = phase else { return }
            text = ""
            pendingURL = nil
            withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
                phase = .idle
            }

        case .idle, .editing, .failed:
            break
        }
    }

    private func recover() {
        guard case .failed(let failure) = phase else { return }
        onRecover(failure)

        switch failure {
        case .offline, .timeout:
            withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
                phase = .saving
            }
        case .sessionExpired, .capacityFull:
            collapse()
        }
    }

    private func successSymbol(for success: DemoCaptureSuccess) -> String {
        switch success {
        case .accepted:
            "checkmark"
        case .duplicate:
            "doc.on.doc"
        }
    }

    private var controlGlass: Glass {
        guard !reduceTransparency else { return .identity }
        return phase.isExpanded
            ? .regular.interactive()
            : .regular.tint(FolioPalette.inkGreen.opacity(0.16)).interactive()
    }

    private var phaseTransition: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .identity)
    }
}

#Preview("Quick save composer") {
    @Previewable @Namespace var glassNamespace
    @Previewable @State var phase = QuickSavePhase.editing
    @Previewable @State var text = "example.com/article"

    FolioQuickSaveControl(
        phase: $phase,
        text: $text,
        glassNamespace: glassNamespace,
        onSave: { url in .success(.accepted(host: url.host() ?? "链接")) },
        onRecover: { _ in }
    )
    .padding(FolioMetrics.compactInset)
    .background(FolioPalette.canvas)
}
