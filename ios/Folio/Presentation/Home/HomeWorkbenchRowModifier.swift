import SwiftUI

struct HomeWorkbenchRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
