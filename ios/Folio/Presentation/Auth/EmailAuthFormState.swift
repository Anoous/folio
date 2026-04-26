import Foundation

struct EmailAuthFormState: Equatable {
    var step: EmailAuthStep = .email
    var email = ""
    var code = ""
    var cooldownRemaining = 0

    var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmailValid: Bool {
        Self.isValidEmail(normalizedEmail)
    }

    var canSendCode: Bool {
        isEmailValid && cooldownRemaining == 0
    }

    var canVerifyCode: Bool {
        code.count == 6
    }

    var emailFieldMessage: String {
        if normalizedEmail.isEmpty {
            return "用于同步资料库、Ask Folio 和 Echo 复习。"
        }

        if isEmailValid {
            return "验证码会发送到这个邮箱。"
        }

        return "请输入有效的邮箱地址。"
    }

    mutating func moveToCodeStep() {
        step = .code
        code = ""
        startCooldown()
    }

    mutating func resetToEmailStep() {
        step = .email
        code = ""
        cooldownRemaining = 0
    }

    mutating func startCooldown(seconds: Int = 60) {
        cooldownRemaining = seconds
    }

    mutating func tickCooldown() {
        cooldownRemaining = max(0, cooldownRemaining - 1)
    }

    mutating func sanitizeCode() {
        code = Self.sanitizedCode(code)
    }

    static func sanitizedCode(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(6))
    }

    static func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let local = parts.first,
              let domain = parts.last,
              !local.isEmpty,
              domain.contains("."),
              !domain.hasPrefix("."),
              !domain.hasSuffix(".")
        else {
            return false
        }

        return !value.contains(" ")
    }
}
