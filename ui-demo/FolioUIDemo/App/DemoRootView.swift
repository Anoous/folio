import SwiftUI

struct DemoRootView: View {
    @State private var store: DemoStore

    init() {
        _store = State(initialValue: DemoStore(initialScreen: DemoScreen.launchValue))
    }

    var body: some View {
        Group {
            if store.isSignedIn {
                DemoNavigationView(store: store)
            } else {
                WelcomeView(
                    onAppleLogin: { store.signIn() },
                    onEmailLogin: { email in store.signIn(email: email) },
                    authMessage: store.authMessage
                )
            }
        }
        .tint(FolioPalette.inkGreen)
        .statusBarHidden(false)
    }
}

#Preview {
    DemoRootView()
}
