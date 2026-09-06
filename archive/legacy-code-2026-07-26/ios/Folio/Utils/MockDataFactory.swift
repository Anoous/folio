import Foundation
import SwiftData

enum MockDataFactory {

    static func generateArticles(count: Int) -> [Article] {
        let titles: [(String, SourceType)] = [
            ("SwiftUI 最佳实践指南", .web),
            ("Understanding Swift Concurrency", .web),
            ("微信小程序开发入门", .wechat),
            ("深度学习在 NLP 中的应用", .web),
            ("Rust vs Go: 2025 年对比", .web),
            ("如何构建高可用系统", .web),
            ("Product-Market Fit 方法论", .twitter),
            ("React Server Components 深度解析", .web),
            ("创业融资的 10 个误区", .weibo),
            ("Kubernetes 集群管理实战", .web),
            ("设计系统构建指南", .web),
            ("机器学习模型部署最佳实践", .zhihu),
            ("TypeScript 5.0 新特性", .web),
            ("iOS 17 新 API 一览", .web),
            ("Docker Compose 高级用法", .web),
            ("GPT-5 技术解读", .twitter),
            ("Python 异步编程详解", .web),
            ("数据库索引优化策略", .web),
            ("用户增长的底层逻辑", .wechat),
            ("Figma 插件开发教程", .web),
            ("分布式系统一致性", .web),
            ("SwiftData 入门到精通", .web),
            ("WebAssembly 前沿探索", .web),
            ("移动端性能优化", .zhihu),
            ("SaaS 商业模式分析", .web),
            ("Flutter vs SwiftUI 2025", .web),
            ("GraphQL 架构设计", .web),
            ("AI 辅助编程的未来", .twitter),
            ("云原生应用开发", .web),
            ("阅读的艺术与方法", .wechat),
        ]

        let summaries = [
            "本文详细介绍了现代 iOS 开发中的最佳实践和设计模式。",
            "A comprehensive guide to building concurrent applications in Swift.",
            "深入浅出地讲解核心概念和实际应用场景。",
            "Exploring cutting-edge techniques and practical implementations.",
            "从实际案例出发，分析技术选型和架构决策。",
        ]

        let statuses: [ArticleStatus] = [.ready, .ready, .ready, .pending, .processing, .failed]
        let siteNames = ["Swift Blog", "Medium", "SwiftGG", "InfoQ", "掘金", "少数派", "GitHub Blog", "Hacker News"]

        return (0..<count).map { i in
            let idx = i % titles.count
            let (title, sourceType) = titles[idx]
            let article = Article(url: "https://example.com/article/\(i)", title: title, sourceType: sourceType)
            article.summary = summaries[i % summaries.count]
            article.siteName = siteNames[i % siteNames.count]
            article.status = statuses[i % statuses.count]
            article.isFavorite = i % 5 == 0
            article.readProgress = statuses[i % statuses.count] == .ready ? (i % 3 == 0 ? 0 : Double.random(in: 0.1...1.0)) : 0
            article.createdAt = Date(timeIntervalSinceNow: Double(-i) * 3600 * 6)
            return article
        }
    }

    static func generateTags() -> [Tag] {
        let tagNames = [
            "Swift", "iOS", "SwiftUI", "Rust", "Go",
            "AI", "机器学习", "产品设计", "创业", "后端",
            "前端", "React", "Python", "DevOps", "数据库",
            "架构", "性能优化", "TypeScript",
        ]
        return tagNames.map { Tag(name: $0) }
    }

    @MainActor
    static func populateSampleData(context: ModelContext) {
        let tags = generateTags()
        for tag in tags {
            context.insert(tag)
        }

        let articles = generateArticles(count: 30)
        for (i, article) in articles.enumerated() {
            context.insert(article)

            // Assign 1-3 random tags
            let tagCount = (i % 3) + 1
            let startIdx = i % tags.count
            for j in 0..<tagCount {
                let tag = tags[(startIdx + j) % tags.count]
                article.tags.append(tag)
                tag.articleCount += 1
            }

            // Assign category from preloaded defaults
            let descriptor = FetchDescriptor<Folio.Category>()
            if let categories = try? context.fetch(descriptor), !categories.isEmpty {
                article.category = categories[i % categories.count]
            }
        }

        try? context.save()
    }
}
