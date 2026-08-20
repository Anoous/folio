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
        XCTAssertTrue(app.staticTexts["从第一篇开始"].waitForExistence(timeout: 3))

        app.buttons["library-first-save"].tap()
        let firstSaveField = app.textFields["quick-save-url-field"]
        XCTAssertTrue(firstSaveField.waitForExistence(timeout: 3))
        firstSaveField.typeText("first.example.com/article")
        app.buttons["quick-save-send"].tap()
        XCTAssertTrue(app.staticTexts["quick-save-success"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["first.example.com/article"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["问答"].waitForExistence(timeout: 3))

        app.buttons["问答"].tap()
        XCTAssertTrue(app.staticTexts["问问你的收藏"].waitForExistence(timeout: 3))

        app.buttons["我保存的内容如何定义 AI 可信度？"].tap()
        XCTAssertTrue(app.staticTexts["回答"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["来源"].exists)
        XCTAssertTrue(app.staticTexts["问 Folio"].exists)
        XCTAssertTrue(app.buttons["资料库"].exists)
        XCTAssertTrue(app.buttons["问答"].exists)
        XCTAssertTrue(app.buttons["收藏链接"].exists)
        XCTAssertFalse(app.buttons["返回"].exists)

        app.buttons["如何设计可信的 AI 产品"].tap()
        XCTAssertTrue(app.staticTexts["核心洞察"].waitForExistence(timeout: 3))
        app.buttons["返回"].tap()
        XCTAssertTrue(app.staticTexts["回答"].waitForExistence(timeout: 3))

        app.buttons["资料库"].tap()
        XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testAskHomeUsesTextOnlyComposer() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "ask-home"]
        app.launch()

        let askTitle = app.staticTexts["问 Folio"]
        XCTAssertTrue(askTitle.waitForExistence(timeout: 3))
        XCTAssertLessThan(askTitle.frame.midX, app.frame.midX)
        XCTAssertTrue(app.staticTexts["可以这样问"].exists)
        XCTAssertFalse(app.buttons["语音输入"].exists)

        for suggestion in [
            "我保存的内容如何定义 AI 可信度？",
            "我读过哪些关于深度阅读的观点？",
            "SwiftUI 性能优化有哪些共同建议？"
        ] {
            XCTAssertTrue(app.buttons[suggestion].exists)
            XCTAssertTrue(app.buttons[suggestion].isHittable)
        }

        let sendButton = app.buttons["ask-send"]
        XCTAssertFalse(sendButton.isEnabled)

        let questionField = app.textFields["ask-question-field"]
        XCTAssertTrue(questionField.exists)
        let restingComposerMinY = questionField.frame.minY
        XCTAssertGreaterThan(
            questionField.frame.minY,
            app.buttons["SwiftUI 性能优化有哪些共同建议？"].frame.maxY
        )
        XCTAssertTrue(app.buttons["资料库"].exists)
        XCTAssertTrue(app.buttons["问答"].exists)
        XCTAssertTrue(app.buttons["收藏链接"].exists)
        questionField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["资料库"].exists)
        XCTAssertFalse(app.buttons["问答"].exists)
        XCTAssertFalse(app.buttons["收藏链接"].exists)

        let dismissKeyboardButton = app.buttons["ask-dismiss-keyboard"]
        XCTAssertTrue(dismissKeyboardButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["问 Folio"].exists)
        XCTAssertFalse(app.buttons["ask-input-back"].exists)
        dismissKeyboardButton.tap()

        let keyboardDismissed = NSPredicate(format: "exists == false")
        expectation(for: keyboardDismissed, evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.staticTexts["问 Folio"].exists)
        XCTAssertTrue(app.buttons["资料库"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["问答"].exists)
        XCTAssertTrue(app.buttons["收藏链接"].exists)
        XCTAssertFalse(dismissKeyboardButton.exists)
        XCTAssertEqual(questionField.frame.minY, restingComposerMinY, accuracy: 4)

        questionField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["资料库"].exists)
        questionField.typeText("为什么解释会降低可信度？")

        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()
        XCTAssertTrue(app.staticTexts["回答"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["问 Folio"].exists)
        XCTAssertTrue(app.staticTexts["ask-inline-response"].exists)
        XCTAssertTrue(app.buttons["资料库"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["问答"].exists)
        XCTAssertTrue(app.buttons["收藏链接"].exists)
        XCTAssertFalse(app.buttons["返回"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }

    @MainActor
    func testNestedTasksHidePrimaryNavigation() {
        continueAfterFailure = false

        for screen in ["reader", "ask-answer", "ask-insufficient", "settings"] {
            let app = XCUIApplication()
            app.launchArguments = ["-demoScreen", screen]
            app.launch()

            XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 3), "\(screen) 未正常启动")
            XCTAssertFalse(app.buttons["资料库"].exists, "\(screen) 不应显示资料库 Tab")
            XCTAssertFalse(app.buttons["问答"].exists, "\(screen) 不应显示问答 Tab")
            XCTAssertFalse(app.buttons["收藏链接"].exists, "\(screen) 不应显示快速收藏")

            app.terminate()
        }
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
    func testReaderReturnsWithExpandedBackSwipe() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "reader"]
        app.launch()

        XCTAssertTrue(app.staticTexts["为什么可信是 AI 产品的\n核心体验"].waitForExistence(timeout: 3))

        let swipeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let swipeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        swipeStart.press(forDuration: 0.05, thenDragTo: swipeEnd)

        XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testReaderArticleComposerFollowsScrollDirectionAndAnswersInline() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "reader"]
        app.launch()

        let composerField = app.textFields["article-ask-field"]
        XCTAssertTrue(composerField.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["article-ask-context"].exists)
        XCTAssertTrue(app.buttons["article-ask-voice"].exists)
        XCTAssertFalse(app.buttons["article-ask-send"].isEnabled)
        XCTAssertFalse(app.buttons["article-ask-mascot"].exists)

        let reader = app.scrollViews.firstMatch
        XCTAssertTrue(reader.exists)
        reader.swipeUp(velocity: .slow)

        let composerHidden = NSPredicate(format: "hittable == false")
        expectation(for: composerHidden, evaluatedWith: composerField)
        waitForExpectations(timeout: 3)

        reader.swipeDown(velocity: .slow)
        let composerRestored = NSPredicate(format: "hittable == true")
        expectation(for: composerRestored, evaluatedWith: composerField)
        waitForExpectations(timeout: 3)

        composerField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        composerField.typeText("这篇文章的核心观点是什么？")

        let sendButton = app.buttons["article-ask-send"]
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()

        XCTAssertTrue(
            app.staticTexts["article-ask-inline-answer"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["article-ask-question"].exists)
        XCTAssertTrue(app.buttons["article-ask-evidence"].exists)
        XCTAssertTrue(composerField.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["隐藏答疑"].exists)
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
    func testAllFifteenLibraryArticlesScrollAndOpenTheirOriginalContent() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "library"]
        app.launch()

        XCTAssertTrue(app.buttons["library-filter"].exists)

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

        for (index, article) in articles.enumerated() {
            let (title, readerTitle) = article

            if index > 0 {
                app.terminate()
                app.launch()
                XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
            }

            if index >= 8 {
                let loadMoreButton = app.buttons["library-load-more"]
                var loadMoreScrollAttempts = 0
                while !loadMoreButton.isHittable && loadMoreScrollAttempts < 12 {
                    app.swipeUp(velocity: .slow)
                    loadMoreScrollAttempts += 1
                }
                XCTAssertTrue(loadMoreButton.isHittable, "加载更多入口不可用")
                loadMoreButton.tap()
            }

            let articleButton = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", title)
            ).firstMatch

            var scrollAttempts = 0
            while (!articleButton.exists || !articleButton.isHittable) && scrollAttempts < 20 {
                app.swipeUp(velocity: .slow)
                scrollAttempts += 1
            }

            XCTAssertTrue(articleButton.exists, "资料库中缺少测试文章：\(title)")
            XCTAssertTrue(articleButton.isHittable, "测试文章无法点击：\(title)")
            articleButton.tap()

            let originalButton = app.buttons["原文"]
            XCTAssertTrue(originalButton.waitForExistence(timeout: 3), "文章未打开：\(title)")
            XCTAssertTrue(
                app.staticTexts[readerTitle].waitForExistence(timeout: 6),
                "原文测试数据未显示：\(title)"
            )

            app.buttons["返回"].tap()
            XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
            XCTAssertTrue(
                app.buttons["资料库"].waitForExistence(timeout: 2),
                "返回资料库后的短暂防误触状态未结束：\(title)"
            )
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
        let firstArticle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "如何设计可信的 AI 产品")
        ).firstMatch
        XCTAssertTrue(firstArticle.isHittable)
        newExpandButton.tap()

        let urlField = app.textFields["quick-save-url-field"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["问答"].exists)
        XCTAssertFalse(app.buttons["资料库"].exists)
        XCTAssertFalse(firstArticle.isHittable)
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
        XCTAssertTrue(firstArticle.isHittable)
        XCTAssertTrue(app.staticTexts["example.com/article"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["资料库"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testOfflineCaptureExplainsFailureAndRecoversSafely() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "settings"]
        app.launch()

        let networkSwitch = app.switches["网络可用"]
        var settingsScrollAttempts = 0
        while !networkSwitch.isHittable && settingsScrollAttempts < 8 {
            app.swipeUp(velocity: .slow)
            settingsScrollAttempts += 1
        }
        XCTAssertTrue(networkSwitch.isHittable)
        networkSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let networkDisabled = NSPredicate(format: "value == '0'")
        expectation(for: networkDisabled, evaluatedWith: networkSwitch)
        waitForExpectations(timeout: 2)

        app.buttons["返回"].tap()
        let offlineBanner = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "当前离线")
        ).firstMatch
        XCTAssertTrue(offlineBanner.waitForExistence(timeout: 3))

        app.buttons["收藏链接"].tap()
        let urlField = app.textFields["quick-save-url-field"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 3))
        urlField.typeText("offline-recovery.example/article")
        app.buttons["quick-save-send"].tap()

        XCTAssertTrue(app.buttons["quick-save-recover"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["尚未保存"].exists)
        app.buttons["quick-save-recover"].tap()

        XCTAssertTrue(app.staticTexts["quick-save-success"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["offline-recovery.example/article"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLibraryFiltersDeletesAndRestoresArticle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "library"]
        app.launch()

        let filterButton = app.buttons["library-filter"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 3))
        filterButton.tap()
        app.buttons["处理中"].tap()
        XCTAssertTrue(app.staticTexts["SwiftUI 性能优化指南"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["如何设计可信的 AI 产品"].exists)

        filterButton.tap()
        app.buttons["全部"].tap()

        let article = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "如何设计可信的 AI 产品")
        ).firstMatch
        XCTAssertTrue(article.waitForExistence(timeout: 3))
        article.swipeLeft()
        app.buttons["删除"].tap()

        XCTAssertTrue(app.buttons["撤销"].waitForExistence(timeout: 3))
        XCTAssertFalse(article.exists)
        app.buttons["撤销"].tap()
        XCTAssertTrue(article.waitForExistence(timeout: 3))
    }

    @MainActor
    func testProcessingFailureKeepsArticleAndSupportsRetry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "settings"]
        app.launch()

        let failNextSwitch = app.switches["下次处理失败"]
        var settingsScrollAttempts = 0
        while !failNextSwitch.isHittable && settingsScrollAttempts < 8 {
            app.swipeUp(velocity: .slow)
            settingsScrollAttempts += 1
        }
        XCTAssertTrue(failNextSwitch.isHittable)
        failNextSwitch.tap()
        app.buttons["返回"].tap()

        app.buttons["收藏链接"].tap()
        let urlField = app.textFields["quick-save-url-field"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 3))
        urlField.typeText("retryable.example/article")
        app.buttons["quick-save-send"].tap()
        XCTAssertTrue(app.staticTexts["quick-save-success"].waitForExistence(timeout: 3))

        let failedStatus = app.staticTexts["处理失败"]
        XCTAssertTrue(failedStatus.waitForExistence(timeout: 5))
        let article = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "retryable.example/article")
        ).firstMatch
        XCTAssertTrue(article.exists)
        article.swipeRight()
        app.buttons["重试"].tap()

        XCTAssertTrue(app.staticTexts["正文已保存 · 可以阅读"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testProcessingLibraryArticleOpensItsAvailableOriginal() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "library"]
        app.launch()

        let filterButton = app.buttons["library-filter"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 3))
        filterButton.tap()
        app.buttons["处理中"].tap()

        let article = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "移动交互中的 100 毫秒")
        ).firstMatch
        var articleScrollAttempts = 0
        while !article.isHittable && articleScrollAttempts < 4 {
            app.swipeUp(velocity: .slow)
            articleScrollAttempts += 1
        }
        XCTAssertTrue(article.isHittable)
        article.tap()

        XCTAssertTrue(app.buttons["原文"].waitForExistence(timeout: 3))
        let readerScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        readerScreenshot.name = "processing-article-reader"
        readerScreenshot.lifetime = .keepAlways
        add(readerScreenshot)
        let readerTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "让每次触控")
        ).firstMatch
        XCTAssertTrue(readerTitle.waitForExistence(timeout: 6))

        let firstParagraph = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "用户触摸屏幕后")
        ).firstMatch
        XCTAssertTrue(firstParagraph.waitForExistence(timeout: 3))
    }

    @MainActor
    func testEmailLoginDeviceRevocationAndSignOutRestoreAccount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demoScreen", "welcome"]
        app.launch()

        app.buttons["welcome.continueWithEmail"].tap()
        let emailField = app.textFields["email-sign-in-address"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 3))
        emailField.typeText("reader@example.com")
        app.buttons["email-sign-in-continue"].tap()

        let codeField = app.textFields["email-sign-in-code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 3))
        codeField.typeText("123456")
        app.buttons["email-sign-in-continue"].tap()
        XCTAssertTrue(app.staticTexts["从第一篇开始"].waitForExistence(timeout: 3))

        app.buttons["打开设置"].firstMatch.tap()
        app.buttons["settings-devices"].tap()
        XCTAssertTrue(app.staticTexts["MacBook Air"].waitForExistence(timeout: 3))
        app.buttons["device-revoke-macbook"].tap()
        XCTAssertTrue(app.alerts["设备已退出"].waitForExistence(timeout: 3))
        app.alerts["设备已退出"].buttons["好"].tap()
        XCTAssertFalse(app.staticTexts["MacBook Air"].exists)

        app.buttons["返回"].tap()
        var signOutScrollAttempts = 0
        let signOutButton = app.buttons["settings-sign-out"]
        while !signOutButton.isHittable && signOutScrollAttempts < 10 {
            app.swipeUp(velocity: .slow)
            signOutScrollAttempts += 1
        }
        XCTAssertTrue(signOutButton.isHittable)
        signOutButton.tap()
        XCTAssertTrue(app.staticTexts["welcome-auth-message"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已安全退出。重新登录后，云端资料仍会恢复。"].exists)
    }
}
