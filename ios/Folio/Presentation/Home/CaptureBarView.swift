import PhotosUI
import SwiftUI

struct CaptureBarView: View {
    let onMicTap: () -> Void
    let onTextTap: () -> Void
    let onPhotoSelected: (UIImage) -> Void

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Mic button
            Button(action: onMicTap) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.folio.textSecondary)
                    .frame(width: 36, height: 36)
            }

            // Text input area (tap to expand ManualNoteSheet)
            Button(action: onTextTap) {
                Text("记录一个想法...")
                    .font(Typography.caption)
                    .foregroundStyle(Color.folio.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.folio.echoBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Camera/Photo picker
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.folio.textSecondary)
                    .frame(width: 36, height: 36)
            }
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
        .padding(.horizontal, Spacing.screenPadding)
        .padding(.vertical, Spacing.sm)
        .background(Color.folio.cardBackground)
    }
}
