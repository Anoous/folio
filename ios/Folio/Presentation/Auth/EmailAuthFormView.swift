import SwiftUI

struct EmailAuthFormView: View {
    @Binding var form: EmailAuthFormState
    let isLoading: Bool
    let onSendCode: () -> Void
    let onVerify: () -> Void
    let onResend: () -> Void
    let onChangeEmail: () -> Void

    var body: some View {
        switch form.step {
        case .email:
            EmailAuthEmailStepView(
                form: $form,
                isLoading: isLoading,
                onSendCode: onSendCode
            )
        case .code:
            EmailAuthCodeStepView(
                form: $form,
                isLoading: isLoading,
                onVerify: onVerify,
                onResend: onResend,
                onChangeEmail: onChangeEmail
            )
        }
    }
}

#Preview {
    EmailAuthFormView(
        form: .constant(EmailAuthFormState()),
        isLoading: false,
        onSendCode: {},
        onVerify: {},
        onResend: {},
        onChangeEmail: {}
    )
    .padding()
    .background(Color.folio.background)
}
