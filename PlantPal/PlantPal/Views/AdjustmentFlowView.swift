import SwiftUI
import SwiftData

struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var plants: [PlantProfile]
    @Query(sort: \ChatMessage.createdAt, order: .forward) private var messages: [ChatMessage]
    @Query(sort: \ConversationSummary.updatedAt, order: .reverse) private var summaries: [ConversationSummary]
    @Query(sort: \PlantMemory.updatedAt, order: .reverse) private var memories: [PlantMemory]
    @Query(sort: \CareTask.createdAt, order: .forward) private var allTasks: [CareTask]
    @StateObject private var googleAuth = GoogleAuthManager()
    @State private var geminiAlertMessage = ""
    @State private var showGeminiAlert = false
    @State private var calendarStatusMessage: String?
    @State private var showCalendarAlert = false
    @State private var plantToDelete: PlantProfile?

    var body: some View {
        NavigationStack {
            List {
                Section("My Plants") {
                    if plants.isEmpty {
                        Text("No plants yet. Add one in Setup.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(plants) { plant in
                            NavigationLink {
                                ReviewPlanView(plantName: plant.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(plant.name)
                                        .font(.headline)
                                    Text("\(plant.type) · \(plant.location)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
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
            }
            .navigationTitle("Me")
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

#Preview {
    MeView()
}

private extension MeView {
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
            guard googleAuth.isSignedIn, let token = googleAuth.accessToken else {
                return
            }

            let plan = [
                CalendarPlanItem(
                    title: "Water plants",
                    guidance: "Water your plants and check soil moisture.",
                    rrule: "FREQ=WEEKLY;INTERVAL=1",
                    startDate: Date()
                ),
                CalendarPlanItem(
                    title: "Rotate pots",
                    guidance: "Rotate pots for even light exposure.",
                    rrule: "FREQ=WEEKLY;INTERVAL=2",
                    startDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
                )
            ]

            do {
                try await GoogleCalendarService().createEvents(from: plan, accessToken: token)
                calendarStatusMessage = "Sample reminder has been connected and created."
                showCalendarAlert = true
            } catch {
                calendarStatusMessage = error.localizedDescription
                showCalendarAlert = true
            }
        }
    }
}
