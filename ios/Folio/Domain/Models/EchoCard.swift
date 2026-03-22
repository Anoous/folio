import Foundation
import SwiftData

@Model
final class EchoCard {
    @Attribute(.unique) var id: UUID
    var serverID: String?
    var articleID: UUID
    var articleTitle: String
    var cardTypeRaw: String
    var question: String
    var answer: String
    var sourceContext: String?
    var nextReviewAt: Date
    var intervalDays: Int
    var reviewCount: Int
    var correctCount: Int
    var createdAt: Date

    var cardType: EchoCardType {
        EchoCardType(rawValue: cardTypeRaw) ?? .insight
    }

    init(id: UUID = UUID(), serverID: String? = nil, articleID: UUID, articleTitle: String,
         cardType: EchoCardType = .insight, question: String, answer: String,
         sourceContext: String? = nil, nextReviewAt: Date = Date().addingTimeInterval(86400),
         intervalDays: Int = 1, reviewCount: Int = 0, correctCount: Int = 0) {
        self.id = id
        self.serverID = serverID
        self.articleID = articleID
        self.articleTitle = articleTitle
        self.cardTypeRaw = cardType.rawValue
        self.question = question
        self.answer = answer
        self.sourceContext = sourceContext
        self.nextReviewAt = nextReviewAt
        self.intervalDays = intervalDays
        self.reviewCount = reviewCount
        self.correctCount = correctCount
        self.createdAt = Date()
    }
}

enum EchoCardType: String {
    case insight
    case highlight
    case related
}
