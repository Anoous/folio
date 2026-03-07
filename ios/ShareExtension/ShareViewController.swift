import UIKit
import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import os

class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<CompactShareView>?

    private lazy var modelContainer: ModelContainer? = {
        let schema = Schema([Article.self, Tag.self, Category.self])
        let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier)
        let config = groupURL != nil
            ? ModelConfiguration("Folio", schema: schema, groupContainer: .identifier(AppConstants.appGroupIdentifier))
            : ModelConfiguration("Folio", schema: schema)
        return try? ModelContainer(for: schema, configurations: [config])
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
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
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
                        Task { @MainActor in
                            if let url = item as? URL {
                                self?.saveURL(url.absoluteString)
                            } else {
                                FolioLogger.data.error("share: loadItem(url) failed — \(error?.localizedDescription ?? "nil item")")
                                self?.showAndDismiss(.error, delay: 1.2)
                            }
                        }
                    }
                    return
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, error in
                        Task { @MainActor in
                            if let text = item as? String {
                                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                if let url = URL(string: trimmed), let scheme = url.scheme, scheme.hasPrefix("http") {
                                    self?.saveURL(trimmed)
                                } else if let extracted = Self.extractURL(from: trimmed) {
                                    self?.saveURL(extracted)
                                } else {
                                    self?.dismiss()
                                }
                            } else {
                                FolioLogger.data.error("share: loadItem(text) failed — \(error?.localizedDescription ?? "nil item")")
                                self?.showAndDismiss(.error, delay: 1.2)
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
        let domain = URL(string: urlString).flatMap { $0.host()?.replacingOccurrences(of: "www.", with: "") } ?? urlString

        let isPro = UserDefaults.appGroup.bool(forKey: SharedDataManager.isProUserKey)
        guard SharedDataManager.canSave(isPro: isPro) else {
            FolioLogger.data.info("share: quota exceeded — \(urlString)")
            showAndDismiss(.quotaExceeded, delay: 1.5)
            return
        }

        guard let container = modelContainer else {
            FolioLogger.data.error("share: ModelContainer unavailable")
            showAndDismiss(.error, delay: 1.2)
            return
        }

        do {
            let manager = SharedDataManager(context: container.mainContext)

            _ = try manager.saveArticle(url: urlString)
            SharedDataManager.incrementQuota()
            UserDefaults.appGroup.set(true, forKey: AppConstants.shareExtensionDidSaveKey)
            FolioLogger.data.info("share: saved — \(urlString)")

            showAndDismiss(.saved(domain: domain))
        } catch SharedDataError.duplicateURL {
            FolioLogger.data.info("share: duplicate — \(urlString)")
            showAndDismiss(.duplicate(domain: domain))
        } catch {
            FolioLogger.data.error("share: failed — \(error)")
            showAndDismiss(.error, delay: 1.2)
        }
    }

    private func showAndDismiss(_ state: ShareState, delay: TimeInterval = 1.0) {
        switch state {
        case .saved:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .duplicate:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .quotaExceeded:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }

        let shareView = CompactShareView(state: state)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.dismiss()
        }
    }

    private static func extractURL(from text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        if let match = detector?.firstMatch(in: text, options: [], range: range),
           let url = match.url, url.scheme?.hasPrefix("http") == true {
            return url.absoluteString
        }
        return nil
    }

    private func dismiss() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
