import SwiftUI

struct FolioQuickSaveControl: View {
    @Binding var isExpanded: Bool
    let glassNamespace: Namespace.ID
    let navigationNamespace: Namespace.ID
    let onSave: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var feedbackTrigger = 0

    var body: some View {
        HStack(spacing: 2) {
            if isExpanded {
                Button("链接", systemImage: "link", action: saveLink)
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("quick-save-link")

                Button("笔记", systemImage: "square.and.pencil", action: saveNote)
                    .labelStyle(.titleAndIcon)
                    .accessibilityIdentifier("quick-save-note")

                Button("收起快速收藏", systemImage: "xmark", action: collapse)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("quick-save-close")
            } else {
                Button("展开快速收藏", systemImage: "plus", action: expand)
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("quick-save")
            }
        }
        .font(.system(size: isExpanded ? 13 : 17, weight: .regular))
        .foregroundStyle(FolioPalette.inkGreenDeep)
        .buttonStyle(FolioPressButtonStyle())
        .padding(.horizontal, isExpanded ? 6 : 0)
        .frame(minWidth: FolioMetrics.tabBarHeight, minHeight: FolioMetrics.tabBarHeight)
        .contentShape(.capsule)
        .background(reduceTransparency ? FolioPalette.surface.opacity(0.96) : .clear, in: .capsule)
        .glassEffect(controlGlass, in: .capsule)
        .glassEffectID("folio-save", in: glassNamespace)
        .glassEffectTransition(.matchedGeometry)
        .matchedTransitionSource(id: "quick-save", in: navigationNamespace)
        .animation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion), value: isExpanded)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.72), trigger: feedbackTrigger)
    }

    private func expand() {
        feedbackTrigger += 1
        withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
            isExpanded = true
        }
    }

    private func collapse() {
        feedbackTrigger += 1
        withAnimation(FolioMotion.toolbarMorph(reduceMotion: reduceMotion)) {
            isExpanded = false
        }
    }

    private func saveLink() {
        feedbackTrigger += 1
        onSave()
    }

    private func saveNote() {
        feedbackTrigger += 1
        onSave()
    }

    private var controlGlass: Glass {
        reduceTransparency ? .identity : .regular.interactive()
    }
}
