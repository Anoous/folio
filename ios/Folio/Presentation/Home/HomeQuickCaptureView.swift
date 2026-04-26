import PhotosUI
import SwiftUI

struct HomeQuickCaptureView: View {
    let onPasteURL: (URL) -> Void
    let onTextTap: () -> Void
    let onPhotoSelected: (UIImage) -> Void

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        GlassPillView(cornerRadius: 34) {
            HStack(spacing: 0) {
                Button(action: onTextTap) {
                    Text("保存链接、文字或截图")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color.gray.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存文字")

                commandDivider

                captureButton(title: "保存链接", systemImage: "link", action: handlePaste)

                commandDivider

                Button(action: onTextTap) {
                    CaptureTextIcon()
                        .frame(width: 64, height: 60)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存文字")

                commandDivider

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "camera")
                        .font(.system(size: 23, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(FolioPaperPalette.ink)
                        .frame(width: 64, height: 60)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("保存截图")
            }
            .frame(height: 68)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
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
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(FolioPaperPalette.ink)
                .frame(width: 64, height: 60)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var commandDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.10))
            .frame(width: 1, height: 30)
    }

    private func handlePaste() {
        let string = UIPasteboard.general.string ?? ""
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
            onPasteURL(url)
        }
    }
}

private struct CaptureTextIcon: View {
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.monochrome)

            Text("A")
                .font(.system(size: 22, weight: .regular))
        }
        .foregroundStyle(FolioPaperPalette.ink)
    }
}
