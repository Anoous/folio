import PhotosUI
import SwiftUI

struct HomeQuickCaptureView: View {
    let onPasteURL: (URL) -> Void
    let onTextTap: () -> Void
    let onMicTap: () -> Void
    let onPhotoSelected: (UIImage) -> Void

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            captureButton(
                title: "链接",
                systemImage: "link",
                action: handlePaste
            )

            captureButton(
                title: "文字",
                systemImage: "square.and.pencil",
                action: onTextTap
            )

            iconButton(
                title: "语音",
                systemImage: "mic",
                action: onMicTap
            )

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "camera")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.folio.textPrimary)
                    .frame(width: 46, height: 46)
                    .background(Color.folio.echoBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("截图")
            }
        }
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
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
        Button(title, systemImage: systemImage, action: action)
            .font(Typography.body)
            .foregroundStyle(Color.folio.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.folio.echoBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .buttonStyle(.plain)
    }

    private func iconButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.folio.textPrimary)
            .frame(width: 46, height: 46)
            .background(Color.folio.echoBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .buttonStyle(.plain)
            .accessibilityLabel(title)
    }

    private func handlePaste() {
        let string = UIPasteboard.general.string ?? ""
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
            onPasteURL(url)
        }
    }
}
