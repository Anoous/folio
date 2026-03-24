import UIKit

extension UIImage {
    /// Resize to fit within maxWidth maintaining aspect ratio, then compress as JPEG.
    /// Returns nil if compression fails.
    func compressed(maxWidth: CGFloat, quality: CGFloat) -> Data? {
        let ratio = maxWidth / size.width
        guard ratio < 1 else {
            return jpegData(compressionQuality: quality)
        }
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
