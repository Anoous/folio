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

            _ = try manager.saveArticle(url: urlString)
            SharedDataManager.incrementQuota()
            showState(.saved)
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
