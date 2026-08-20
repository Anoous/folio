import SwiftUI

struct FolioQuickSaveControl: View {
    @Binding var phase: QuickSavePhase
    @Binding var text: String
    let glassNamespace: Namespace.ID
    let onSave: (URL) -> Void
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

            case .saved:
                Label("已收藏 · 正在处理", systemImage: "checkmark")
                    .font(.body)
                    .foregroundStyle(FolioPalette.inkGreenDeep)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("quick-save-success")
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
            onSave(pendingURL)
            successFeedbackTrigger += 1
            withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
                phase = .saved
            }

        case .saved:
            do {
                try await Task.sleep(for: .milliseconds(1_200))
            } catch {
                return
            }
            guard phase == .saved else { return }
            text = ""
            pendingURL = nil
            withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
                phase = .idle
            }

        case .idle, .editing:
            break
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
        onSave: { _ in }
    )
    .padding(FolioMetrics.compactInset)
    .background(FolioPalette.canvas)
}
