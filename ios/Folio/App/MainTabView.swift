import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label(String(localized: "tab.library"), systemImage: "book")
            }

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label(String(localized: "tab.search"), systemImage: "magnifyingglass")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(String(localized: "tab.settings"), systemImage: "gearshape")
            }
        }
    }
}

#Preview {
    MainTabView()
}
