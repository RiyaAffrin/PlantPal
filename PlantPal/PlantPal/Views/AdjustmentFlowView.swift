import SwiftUI
import SwiftData
import UserNotifications


struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var plants: [PlantProfile]
    @Query(sort: \ChatMessage.createdAt, order: .forward) private var messages: [ChatMessage]
    @Query(sort: \ConversationSummary.updatedAt, order: .reverse) private var summaries: [ConversationSummary]
    @Query(sort: \PlantMemory.updatedAt, order: .reverse) private var memories: [PlantMemory]
    @Query(sort: \CareTask.createdAt, order: .forward) private var allTasks: [CareTask]
    @EnvironmentObject private var googleAuth: GoogleAuthManager
    @State private var geminiAlertMessage = ""
    @State private var showGeminiAlert = false
    @State private var calendarStatusMessage: String?
    @State private var showCalendarAlert = false
    @State private var plantToDelete: PlantProfile?

    @AppStorage("userName") private var userName: String = ""
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("selectedTheme") private var selectedTheme: String = "System"
    @State private var isEditingName = false
    @State private var editingNameText = ""

    var body: some View {
        NavigationStack {
            List {

                // MARK: Profile Header
                Section {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.86, green: 0.97, blue: 0.84))
                                .frame(width: 80, height: 80)
                            Image(systemName: "person.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color(red: 0.35, green: 0.62, blue: 0.32))
                        }

                        if isEditingName {
                            TextField("Enter your name", text: $editingNameText)
                                .multilineTextAlignment(.center)
                                .font(.headline)
                                .onSubmit {
                                    userName = editingNameText
                                    isEditingName = false
                                }
                        } else {
                            Text(userName.isEmpty ? "Add your name" : userName)
                                .font(.headline)
                                .foregroundStyle(userName.isEmpty ? .secondary : .primary)
                        }

                        Button(isEditingName ? "Save" : "Edit Profile") {
                            if isEditingName {
                                userName = editingNameText
                                isEditingName = false
                            } else {
                                editingNameText = userName
                                isEditingName = true
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .tint(Color(red: 0.35, green: 0.62, blue: 0.32))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                
                // MARK: My Plants
                Section(header: Text("My Plants"), footer: Text("Swipe left on a plant to remove it.")) {
                    if plants.isEmpty {
                        Text("No plants yet. Add one in Setup.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(plants) { plant in
                            NavigationLink {
                                ReviewPlanView(plantName: plant.name)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(red: 0.86, green: 0.97, blue: 0.84))
                                            .frame(width: 40, height: 40)
                                        Image(systemName: "leaf.fill")
                                            .foregroundStyle(Color(red: 0.35, green: 0.62, blue: 0.32))
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(plant.name)
                                            .font(.headline)
                                        Text("\(plant.type) · \(plant.location)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    plantToDelete = plant
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }


                #if DEBUG
                Section("Debug") {
                    Button("Clear All Data", role: .destructive) {
                        clearAllData()
                    }
                }
                #endif



                // MARK: Connections (unchanged)

                Section("Connections") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect to Gemini API to power your plant insights and chats.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Connect to Gemini API") {
                            connectGemini()
                        }
                    }
                    .padding(.vertical, 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect to Google Calendar to sync reminders and care schedules.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Connect to Google Calendar") {
                            connectGoogleCalendar()
                        }
                        if let calendarStatusMessage {
                            Text(calendarStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // MARK: About
                Section("About") {
                    HStack{
                        Label("Theme", systemImage: "paintbrush.fill")
                        Spacer()
                        Picker("", selection: $selectedTheme){
                            Text("System").tag("System")
                            Text("Light").tag("Light")
                            Text("Dark").tag("Dark")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    
                    NavigationLink{
                        PrivacyView()
                    }label: {
                        Label("Privacy", systemImage: "hand.raised.fill")
                    }
                    
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Profile")
        }
        .alert("Gemini", isPresented: $showGeminiAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(geminiAlertMessage)
        }
        .alert("Google Calendar", isPresented: $showCalendarAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calendarStatusMessage ?? "")
        }
        .alert("Delete Plant", isPresented: Binding(
            get: { plantToDelete != nil },
            set: { if !$0 { plantToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { plantToDelete = nil }
            Button("Delete", role: .destructive) {
                if let plant = plantToDelete {
                    deletePlantAndRelatedData(plant)
                    plantToDelete = nil
                }
            }
        } message: {
            if let plant = plantToDelete {
                Text("Remove \"\(plant.name)\" and all its chat history, memories, and care tasks? This cannot be undone.")
            }
        }
        .onReceive(googleAuth.$errorMessage) { message in
            guard let message, !message.isEmpty else { return }
            calendarStatusMessage = message
            showCalendarAlert = true
        }
    }
}

// MARK: Privacy View
struct PrivacyView: View {
    var body: some View {
        List {
            Section("Data") {
                Label("All plant data is stored locally on your device.", systemImage: "iphone")
                    .font(.subheadline)
                Label("Chat history is used only to generate care advice.", systemImage: "bubble.left.and.bubble.right")
                    .font(.subheadline)
            }
            Section("API Usage") {
                Label("Messages sent to Gemini are not stored by PlantPal.", systemImage: "lock.shield")
                    .font(.subheadline)
            }
        }
        .navigationTitle("Privacy")
    }
}

#Preview {
    MeView()
        .modelContainer(for: [PlantProfile.self, CareTask.self], inMemory: true)
}

private extension MeView {
    func clearAllData() {
        plants.forEach { modelContext.delete($0) }
        messages.forEach { modelContext.delete($0) }
        summaries.forEach { modelContext.delete($0) }
        memories.forEach { modelContext.delete($0) }
        allTasks.forEach { modelContext.delete($0) }
    }

    func deletePlantAndRelatedData(_ plant: PlantProfile) {
        let name = plant.name
        modelContext.delete(plant)
        messages.filter { $0.plantName == name }.forEach { modelContext.delete($0) }
        summaries.filter { $0.plantName == name }.forEach { modelContext.delete($0) }
        memories.filter { $0.plantName == name }.forEach { modelContext.delete($0) }
        allTasks.filter { $0.plantName == name }.forEach { modelContext.delete($0) }
    }

    func connectGemini() {
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String
        if let apiKey, !apiKey.isEmpty, !apiKey.hasPrefix("<#") {
            geminiAlertMessage = "GEMINI_API_KEY detected. Gemini is ready to use."
        } else {
            geminiAlertMessage = "GEMINI_API_KEY is missing. Please set it in Secrets.xcconfig."
        }
        showGeminiAlert = true
    }

    func connectGoogleCalendar() {
        calendarStatusMessage = "Now connecting Google..."
        Task {
            await googleAuth.signIn()
            guard googleAuth.isSignedIn, let _ = googleAuth.accessToken else {
                return
            }

            calendarStatusMessage = "Connected to Google Calendar."
            showCalendarAlert = true
        }
    }
}
