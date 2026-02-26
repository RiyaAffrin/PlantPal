import SwiftUI
import SwiftData

@main
struct PlantPalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var googleAuth = GoogleAuthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(googleAuth)
        }
        .modelContainer(for: [
            PlantProfile.self,
            ChatMessage.self,
            ConversationSummary.self,
            PlantMemory.self,
            CareTask.self,
            PlantReferencePhoto.self
        ])
    }
}
