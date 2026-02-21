import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(selectedTab: $selectedTab)
                .tabItem { Label("Today", systemImage: "leaf.fill") }
                .tag(0)

            Scenario1FlowView()
                .tabItem { Label("Chat", systemImage: "sparkles") }
                .tag(1)

            ChatView(onStartChat: { selectedTab = 1 })
                .tabItem { Label("History", systemImage: "bubble.left.and.bubble.right") }
                .tag(2)

            MeView()
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
}
