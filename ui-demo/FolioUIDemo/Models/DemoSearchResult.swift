import Foundation

struct DemoSearchResult: Identifiable, Hashable {
    let id: String
    let article: DemoArticle
    let scope: String
    let snippet: String
    let paragraphIndex: Int?
}
