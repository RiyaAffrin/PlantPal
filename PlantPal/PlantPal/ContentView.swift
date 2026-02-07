import SwiftUI

struct ContentView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                TabView {
                    HomeView()
                        .tabItem { Label("Home", systemImage: "house") }

                    Scenario1FlowView()
                        .tabItem { Label("Setup", systemImage: "sparkles") }

                    ChatView()
                        .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

                    TodayView()
                        .tabItem { Label("Today", systemImage: "calendar") }

                    MeView()
                        .tabItem { Label("Me", systemImage: "person.crop.circle") }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

#Preview {
    ContentView()
}
