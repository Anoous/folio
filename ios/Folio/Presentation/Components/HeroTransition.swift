import SwiftUI

// MARK: - Hero Namespace Environment

private struct HeroNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var heroNamespace: Namespace.ID? {
        get { self[HeroNamespaceKey.self] }
        set { self[HeroNamespaceKey.self] = newValue }
    }
}

// MARK: - Article Selection Environment

struct SelectArticleAction {
    let action: (Article) -> Void
    func callAsFunction(_ article: Article) { action(article) }
}

private struct SelectArticleKey: EnvironmentKey {
    static let defaultValue = SelectArticleAction { _ in }
}

extension EnvironmentValues {
    var selectArticle: SelectArticleAction {
        get { self[SelectArticleKey.self] }
        set { self[SelectArticleKey.self] = newValue }
    }
}

// MARK: - Hero Geometry Modifier

struct HeroGeometryModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let ns = namespace {
            content.matchedGeometryEffect(id: id, in: ns)
        } else {
            content
        }
    }
}
