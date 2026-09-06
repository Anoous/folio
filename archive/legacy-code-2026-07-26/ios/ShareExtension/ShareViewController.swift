import UIKit
import SwiftUI
import UniformTypeIdentifiers
import SwiftData

class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<CompactShareView>?
    private var dismissWorkItem: DispatchWorkItem?

    private lazy var modelContainer: ModelContainer? = {
        try? DataManager.createSharedContainer()
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
                                    self?.saveManualContent(trimmed)
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

        // Collect all image providers across all extension items
        var imageProviders: [NSItemProvider] = []
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    imageProviders.append(provider)
                }
            }
        }

        if !imageProviders.isEmpty {
            Task { @MainActor in
                await self.processImages(imageProviders)
            }
            return
        }

        dismiss()
    }

    @MainActor
    private func saveURL(_ urlString: String) {
        guard let container = modelContainer else {
            FolioLogger.data.error("share: ModelContainer unavailable")
            showAndDismiss(.error, delay: 1.2)
            return
        }

        switch makeIntakeWorkflow(container: container).saveURL(urlString) {
        case .saved(let receipt):
            FolioLogger.data.info("share: saved — \(urlString)")
            showAndDismiss(.saved(domain: receipt.displayName))
        case .duplicate(let receipt):
            FolioLogger.data.info("share: duplicate — \(urlString)")
            showAndDismiss(.duplicate(domain: receipt.displayName))
        case .quotaExceeded:
            FolioLogger.data.info("share: quota exceeded — \(urlString)")
            showAndDismiss(.quotaExceeded, delay: 1.5)
        case .error(let error):
            FolioLogger.data.error("share: failed — \(error)")
            showAndDismiss(.error, delay: 1.2)
        }
    }

    @MainActor
    private func saveManualContent(_ text: String) {
        guard let container = modelContainer else {
            FolioLogger.data.error("share: ModelContainer unavailable")
            showAndDismiss(.error, delay: 1.2)
            return
        }

        switch makeIntakeWorkflow(container: container).saveManualContent(text) {
        case .saved(let receipt):
            let preview = String(text.prefix(20))
            FolioLogger.data.info("share: saved manual content — \(preview)")
            showAndDismiss(.saved(domain: receipt.displayName))
        case .duplicate(let receipt):
            showAndDismiss(.duplicate(domain: receipt.displayName))
        case .quotaExceeded:
            FolioLogger.data.info("share: quota exceeded — manual content")
            showAndDismiss(.quotaExceeded, delay: 1.5)
        case .error(let error):
            FolioLogger.data.error("share: manual content failed — \(error)")
            showAndDismiss(.error, delay: 1.2)
        }
    }

    // MARK: - Image Processing

    @MainActor
    private func processImages(_ providers: [NSItemProvider]) async {
        let isPro = UserDefaults.appGroup.bool(forKey: SharedDataManager.isProUserKey)
        guard SharedDataManager.canSave(isPro: isPro) else {
            FolioLogger.data.info("share: quota exceeded — image")
            showAndDismiss(.quotaExceeded, delay: 1.5)
            return
        }

        guard let container = modelContainer else {
            FolioLogger.data.error("share: ModelContainer unavailable")
            showAndDismiss(.error, delay: 1.2)
            return
        }

        showAndDismiss(.processing, delay: 30)

        var savedCount = 0
        for provider in providers {
            guard let image = await loadImage(from: provider) else { continue }
            if await processImage(image, container: container) {
                savedCount += 1
            }
        }

        guard savedCount > 0 else {
            updateState(.error, delay: 1.2)
            return
        }

        let domain = savedCount == 1
            ? String(localized: "share.screenshot", defaultValue: "截图")
            : "\(savedCount) " + String(localized: "share.screenshots", defaultValue: "张截图")
        updateState(.saved(domain: domain))
    }

    private func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let error {
                    FolioLogger.data.error("share: loadItem(image) failed — \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                if let url = item as? URL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else if let data = item as? Data, let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                } else if let image = item as? UIImage {
                    continuation.resume(returning: image)
                } else {
                    FolioLogger.data.error("share: loadItem(image) — unsupported item type")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    @MainActor
    private func processImage(_ image: UIImage, container: ModelContainer) async -> Bool {
        let result = await makeIntakeWorkflow(container: container).saveScreenshotAfterOCR(image)
        switch result {
        case .saved(let receipt):
            FolioLogger.data.info("share: screenshot saved — \(receipt.article.displayTitle)")
            return true
        case .quotaExceeded:
            FolioLogger.data.info("share: quota exceeded — image")
            return false
        case .duplicate:
            return false
        case .error(let error):
            FolioLogger.data.error("share: image processing failed — \(error)")
            return false
        }
    }

    @MainActor
    private func makeIntakeWorkflow(container: ModelContainer) -> ContentIntakeWorkflow {
        ContentIntakeWorkflow(
            context: container.mainContext,
            onSaveCompleted: {
                UserDefaults.appGroup.set(true, forKey: AppConstants.shareExtensionDidSaveKey)
            }
        )
    }

    @MainActor
    private func updateState(_ state: ShareState, delay: TimeInterval = 1.0) {
        // Remove existing hosting controller and show new state
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil

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

        scheduleDismiss(delay: delay)
    }

    private func showAndDismiss(_ state: ShareState, delay: TimeInterval = 1.0) {
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

        scheduleDismiss(delay: delay)
    }

    private func scheduleDismiss(delay: TimeInterval) {
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
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
