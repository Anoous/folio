import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "book.pages")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Folio")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
