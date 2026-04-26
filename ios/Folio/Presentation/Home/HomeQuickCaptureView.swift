import PhotosUI
import SwiftUI

struct HomeQuickCaptureView: View {
    let onPasteURL: (URL) -> Void
    let onTextTap: () -> Void
    let onPhotoSelected: (UIImage) -> Void

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 0) {
            captureButton(title: "链接", systemImage: "link", action: handlePaste)

            commandDivider

            captureButton(title: "文字", systemImage: "square.and.pencil", action: onTextTap)

            commandDivider

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("截图", systemImage: "camera")
                    .labelStyle(.iconOnly)
                    .font(.body)
                    .imageScale(.large)
                    .foregroundStyle(Color.folio.textPrimary)
                    .frame(width: 56)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.xxs)
        .background(Color.folio.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.folio.separator, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.lg)
        .onChange(of: selectedPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    onPhotoSelected(image)
                }
                selectedPhoto = nil
            }
        }
    }

    private func captureButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body)
                .imageScale(.medium)
                .foregroundStyle(Color.folio.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
            .buttonStyle(.plain)
    }

    private var commandDivider: some View {
        Rectangle()
            .fill(Color.folio.separator)
            .frame(width: 1, height: 24)
    }

    private func handlePaste() {
        let string = UIPasteboard.general.string ?? ""
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
            onPasteURL(url)
        }
    }
}
