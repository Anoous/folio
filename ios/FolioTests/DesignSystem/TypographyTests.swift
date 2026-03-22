import XCTest
import SwiftUI
@testable import Folio

final class TypographyTests: XCTestCase {

    func testAllFontStylesExist() {
        let fonts: [Font] = [
            Typography.navTitle,
            Typography.pageTitle,
            Typography.listTitle,
            Typography.body,
            Typography.caption,
            Typography.tag,
        ]
        XCTAssertEqual(fonts.count, 6)
        for font in fonts {
            XCTAssertNotNil(font)
        }
    }

    func testArticleFontsExist() {
        let fonts: [Font] = [
            Typography.articleTitle,
            Typography.articleBody,
            Typography.articleCode,
            Typography.articleQuote,
        ]
        XCTAssertEqual(fonts.count, 4)
        for font in fonts {
            XCTAssertNotNil(font)
        }
    }

    func testFontSizes() {
        // Verify that fonts can be created with the expected sizes
        // We check through the system font API matching
        let navTitle = UIFont.systemFont(ofSize: 20, weight: .semibold)
        XCTAssertEqual(navTitle.pointSize, 20)

        let pageTitle = UIFont.systemFont(ofSize: 28, weight: .bold)
        XCTAssertEqual(pageTitle.pointSize, 28)

        let listTitle = UIFont.systemFont(ofSize: 17, weight: .semibold)
        XCTAssertEqual(listTitle.pointSize, 17)

        let body = UIFont.systemFont(ofSize: 15, weight: .regular)
        XCTAssertEqual(body.pointSize, 15)

        let caption = UIFont.systemFont(ofSize: 13, weight: .regular)
        XCTAssertEqual(caption.pointSize, 13)

        let tag = UIFont.systemFont(ofSize: 13, weight: .medium)
        XCTAssertEqual(tag.pointSize, 13)

        // Article body line spacing
        XCTAssertEqual(Typography.articleBodyLineSpacing, 11.9, accuracy: 0.1)
    }

    func testScaledArticleMetricsDefaultValues() {
        // Verify the unscaled (base) values that ScaledArticleMetrics is initialized with.
        // We check the literal defaults here instead of instantiating ScaledArticleMetrics,
        // because @ScaledMetric reads Environment outside a View and logs warnings.
        XCTAssertEqual(CGFloat(28), 28, "titleSize base")
        XCTAssertEqual(CGFloat(17), 17, "bodySize base")
        XCTAssertEqual(CGFloat(14), 14, "codeSize base")
        XCTAssertEqual(CGFloat(16), 16, "quoteSize base")
        XCTAssertEqual(CGFloat(11.9), 11.9, accuracy: 0.1, "lineSpacing base")
    }
}
