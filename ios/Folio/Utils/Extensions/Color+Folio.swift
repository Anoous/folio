import SwiftUI

extension Color {
    static let folio = FolioColors()
}

struct FolioColors {
    // MARK: - Backgrounds
    let background = Color("Colors/background")
    let cardBackground = Color("Colors/cardBackground")

    // MARK: - Text
    let textPrimary = Color("Colors/textPrimary")
    let textSecondary = Color("Colors/textSecondary")
    let textTertiary = Color("Colors/textTertiary")

    // MARK: - UI Elements
    let separator = Color("Colors/separator")
    let accent = Color("Colors/accent")
    let link = Color("Colors/link")
    let unread = Color("Colors/unread")

    // MARK: - Status
    let success = Color("Colors/success")
    let warning = Color("Colors/warning")
    let error = Color("Colors/error")

    // MARK: - Tags
    let tagBackground = Color("Colors/tagBackground")
    let tagText = Color("Colors/tagText")

    // MARK: - Highlights
    let highlightYellow = Color("Colors/highlightYellow")
    let highlightGreen = Color("Colors/highlightGreen")
    let highlightBlue = Color("Colors/highlightBlue")
    let highlightRed = Color("Colors/highlightRed")
}
