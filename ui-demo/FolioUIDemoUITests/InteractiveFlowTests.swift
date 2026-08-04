import XCTest

final class InteractiveFlowTests: XCTestCase {
    @MainActor
    private func assertWelcomeCopy(
        language: String,
        locale: String,
        headline: String,
        valueProposition: String,
        privacy: String
    ) {
        let app = XCUIApplication()
        app.launchArguments = [
            "-demoScreen", "welcome",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        app.launch()

        let headlineText = app.staticTexts["welcome.headline"]
        XCTAssertTrue(headlineText.waitForExistence(timeout: 3))
        XCTAssertEqual(headlineText.label, headline)
        XCTAssertEqual(app.staticTexts["welcome.valueProposition"].label, valueProposition)
        XCTAssertEqual(app.staticTexts["welcome.privacy"].label, privacy)

        XCTAssertTrue(app.buttons["welcome.continueWithApple"].exists)
        XCTAssertTrue(app.buttons["welcome.continueWithEmail"].exists)
        app.terminate()
    }

    @MainActor
    func testDefaultLaunchSupportsPrimaryNavigation() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        let loginButton = app.buttons["welcome.continueWithApple"]
        XCTAssertTrue(loginButton.waitForExistence(timeout: 3))
        loginButton.tap()

        XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))

        app.buttons["问答"].tap()
        XCTAssertTrue(app.staticTexts["问问你保存过的内容"].waitForExistence(timeout: 3))

        app.buttons["我保存的内容如何定义 AI 可信度？"].tap()
        XCTAssertTrue(app.staticTexts["回答"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["来源"].exists)

        app.buttons["阅读"].tap()
        XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testWelcomeCopySupportsEnglishAndSimplifiedChinese() {
        assertWelcomeCopy(
            language: "en",
            locale: "en_US",
            headline: "Keep what's worth returning to.",
            valueProposition: "Every answer leads back to its source.",
            privacy: "Your library. Yours alone."
        )

        assertWelcomeCopy(
            language: "zh-Hans",
            locale: "zh_CN",
            headline: "读有所藏，问有所据。",
            valueProposition: "留下读过的，也留下它的来处。",
            privacy: "所藏皆私有，去留皆由你。"
        )
    }

    @MainActor
    func testDemoScreenLaunchRemainsInteractive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "library"]
        app.launch()

        XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "如何设计可信的 AI 产品")).firstMatch.tap()

        XCTAssertTrue(app.staticTexts["为什么可信是 AI 产品的\n核心体验"].waitForExistence(timeout: 3))
        app.buttons["洞察"].tap()
        XCTAssertTrue(app.staticTexts["核心洞察"].waitForExistence(timeout: 3))
        app.buttons["原文"].tap()
        XCTAssertTrue(app.staticTexts["为什么可信是 AI 产品的\n核心体验"].waitForExistence(timeout: 3))

        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testReaderLaunchSwitchesToInsightWithoutAddingNavigationDepth() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "reader"]
        app.launch()

        XCTAssertTrue(app.staticTexts["为什么可信是 AI 产品的\n核心体验"].waitForExistence(timeout: 3))
        app.buttons["洞察"].tap()
        XCTAssertTrue(app.staticTexts["核心洞察"].waitForExistence(timeout: 3))

        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testReaderAppearanceChangesFontAndBackground() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "reader"]
        app.launch()

        let appearanceButton = app.buttons["阅读外观"]
        XCTAssertTrue(appearanceButton.waitForExistence(timeout: 3))
        appearanceButton.tap()

        XCTAssertTrue(app.staticTexts["阅读外观"].waitForExistence(timeout: 3))
        app.buttons["薄荷"].tap()

        let roundedFontButton = app.buttons["系统圆体"]
        var scrollAttempts = 0
        while !roundedFontButton.isHittable && scrollAttempts < 3 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(roundedFontButton.isHittable)
        roundedFontButton.tap()
        app.buttons["完成"].tap()

        let updatedAppearance = NSPredicate(format: "value == %@", "薄荷，系统圆体")
        expectation(for: updatedAppearance, evaluatedWith: appearanceButton)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.staticTexts["为什么可信是 AI 产品的\n核心体验"].exists)

        app.buttons["洞察"].tap()
        let insightBody = app.staticTexts["insight-body"]
        XCTAssertTrue(insightBody.waitForExistence(timeout: 3))
        XCTAssertEqual(insightBody.value as? String, "薄荷，系统圆体")

        let firstInsightPoint = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "可信来自边界清晰")
        ).firstMatch
        XCTAssertTrue(firstInsightPoint.waitForExistence(timeout: 3))
        firstInsightPoint.tap()
        let evidenceQuote = app.staticTexts["evidence-quote"]
        XCTAssertTrue(evidenceQuote.waitForExistence(timeout: 3))
        XCTAssertEqual(evidenceQuote.value as? String, "薄荷，系统圆体")
    }

    @MainActor
    func testLibraryFilterChangesVisibleMockData() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "library"]
        app.launch()

        let filterButton = app.buttons["筛选"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 3))
        filterButton.tap()
        app.buttons["处理中"].tap()

        XCTAssertTrue(app.staticTexts["SwiftUI 性能优化指南"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["如何设计可信的 AI 产品"].exists)
    }

    @MainActor
    func testAllFifteenLibraryArticlesScrollAndOpenTheirOriginalContent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "library"]
        app.launch()

        let articles = [
            ("如何设计可信的 AI 产品", "为什么可信是 AI 产品的\n核心体验"),
            ("SwiftUI 性能优化指南", "让 SwiftUI 列表保持流畅的四个层次"),
            ("一篇暂时无法解析的文章", "即使解析失败，也要保住可阅读的正文"),
            ("Local-first 笔记为何更让人安心", "Local-first 不只是离线可用"),
            ("Agent 工具调用的安全边界", "从会回答到能行动：Agent 的权限设计"),
            ("中文移动阅读的字号与行距", "小屏中文排版不是把桌面页面缩小"),
            ("如何做可追溯的深度研究", "研究笔记应当保留证据链"),
            ("错误提示应该告诉用户下一步", "把错误状态设计成恢复路径"),
            ("RAG 评估不能只看答案像不像", "拆开评估检索与生成，才能定位 RAG 问题"),
            ("克制的界面如何建立使用信心", "安静的界面不是没有个性"),
            ("Dynamic Type 不是放大镜模式", "为大字号重新安排信息结构"),
            ("稍后读清单为什么总会失控", "从收藏积压到可持续阅读"),
            ("个人知识库需要定期维护吗", "让知识库随着使用自然生长"),
            ("移动交互中的 100 毫秒", "让每次触控都得到及时回应"),
            ("离线编辑后的冲突该怎么解释", "同步冲突不应该悄悄吞掉修改")
        ]

        for (title, readerTitle) in articles {
            let articleButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", title)
            ).firstMatch

            var scrollAttempts = 0
            while !articleButton.exists && scrollAttempts < 8 {
                app.swipeUp()
                scrollAttempts += 1
            }

            XCTAssertTrue(articleButton.exists, "资料库中缺少测试文章：\(title)")
            articleButton.tap()

            let originalButton = app.buttons["原文"]
            XCTAssertTrue(originalButton.waitForExistence(timeout: 3), "文章未打开：\(title)")
            XCTAssertTrue(
                app.staticTexts[readerTitle].waitForExistence(timeout: 3),
                "原文测试数据未显示：\(title)"
            )

            app.buttons["返回"].tap()
            XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
        }
    }

    @MainActor
    func testLiquidToolbarMorphsIntoURLComposerAndCompletesQuickSave() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "library"]
        app.launch()

        let newExpandButton = app.buttons["收藏链接"]
        XCTAssertTrue(newExpandButton.waitForExistence(timeout: 3))
        newExpandButton.tap()

        let urlField = app.textFields["quick-save-url-field"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["问答"].exists)
        urlField.typeText("example.com/article")

        let composerScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        composerScreenshot.name = "quick-save-composer"
        composerScreenshot.lifetime = .keepAlways
        add(composerScreenshot)

        let sendButton = app.buttons["quick-save-send"]
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()

        XCTAssertTrue(app.staticTexts["quick-save-success"].waitForExistence(timeout: 3))
        XCTAssertTrue(newExpandButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["example.com/article"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
    }
}
