import UIKit
import SwiftUI
import UniformTypeIdentifiers
import SwiftData

class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<CompactShareView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        showState(.saving)
        processInput()
    }

    private func processInput() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            dismiss()
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        if let url = item as? URL {
                            Task { @MainActor in
                                self?.saveURL(url.absoluteString)
                            }
                        }
                    }
                    return
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                        if let text = item as? String {
                            Task { @MainActor in
                                self?.saveURL(text)
                            }
                        }
                    }
                    return
                }
            }
        }

        dismiss()
    }

    @MainActor
    private func saveURL(_ urlString: String) {
        do {
            let schema = Schema([Article.self, Tag.self, Category.self])
            let config: ModelConfiguration
            if let _ = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.folio.app") {
                config = ModelConfiguration(
                    "Folio",
                    schema: schema,
                    groupContainer: .identifier("group.com.folio.app")
                )
            } else {
                config = ModelConfiguration("Folio", schema: schema)
            }
            let container = try ModelContainer(for: schema, configurations: [config])
            let manager = SharedDataManager(context: container.mainContext)

            // Check quota before saving
            let isPro = UserDefaults.appGroup.bool(forKey: "is_pro_user")
            guard SharedDataManager.canSave(isPro: isPro) else {
                showState(.quotaExceeded)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    self?.dismiss()
                }
                return
            }

            let article = try manager.saveArticle(url: urlString)
            SharedDataManager.incrementQuota()

            // Check if nearing quota limit for warning
            let currentCount = SharedDataManager.currentMonthCount()
            let quota = SharedDataManager.freeMonthlyQuota
            if !isPro && currentCount >= Int(Double(quota) * 0.9) {
                showState(.quotaWarning(remaining: quota - currentCount))
            } else {
                showState(.saved)
            }

            // Start client-side extraction if supported
            if article.sourceType.supportsClientExtraction {
                showState(.extracting)
                let articleURL = article.url
                Task {
                    do {
                        guard let url = URL(string: articleURL) else { return }
                        let result = try await ContentExtractor().extract(url: url)
                        try manager.updateWithExtraction(result, for: article)
                        self.showState(.extracted)
                    } catch {
                        // Extraction failed — stay with saved state, server will process
                        self.showState(.saved)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.dismiss()
                    }
                }
                // Hard limit: dismiss after 10s regardless
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                    self?.dismiss()
                }
                return
            }
        } catch SharedDataError.duplicateURL {
            showState(.duplicate)
        } catch {
            showState(.offline)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dismiss()
        }
    }

    private func showState(_ state: ShareState) {
        // Haptic feedback based on state
        switch state {
        case .saved, .quotaWarning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .extracted:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .duplicate:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        case .quotaExceeded:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        case .offline:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case .saving, .extracting:
            break
        }

        if let hostingController {
            hostingController.rootView = CompactShareView(state: state, onDismiss: { [weak self] in
                self?.dismiss()
            })
        } else {
            let shareView = CompactShareView(state: state, onDismiss: { [weak self] in
                self?.dismiss()
            })
            let hc = UIHostingController(rootView: shareView)
            addChild(hc)
            view.addSubview(hc.view)
            hc.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hc.view.topAnchor.constraint(equalTo: view.topAnchor),
                hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
            hc.didMove(toParent: self)
            hostingController = hc
        }
    }

    private func dismiss() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
