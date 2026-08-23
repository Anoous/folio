import Foundation

struct DemoHighlight: Identifiable, Hashable {
    let id: UUID
    let articleID: UUID
    let paragraphIndex: Int
    let rangeLocation: Int
    let rangeLength: Int
    let quote: String
    var note: String

    init(
        id: UUID = UUID(),
        articleID: UUID,
        paragraphIndex: Int,
        rangeLocation: Int,
        rangeLength: Int,
        quote: String,
        note: String = ""
    ) {
        self.id = id
        self.articleID = articleID
        self.paragraphIndex = paragraphIndex
        self.rangeLocation = rangeLocation
        self.rangeLength = rangeLength
        self.quote = quote
        self.note = note
    }

    var range: NSRange {
        NSRange(location: rangeLocation, length: rangeLength)
    }
}
