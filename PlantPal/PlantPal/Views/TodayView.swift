import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \CareTask.dueDate, order: .forward) private var tasks: [CareTask]
    @State private var checkInSelection: String?

    private var todaysTasks: [CareTask] {
        tasks.filter { Calendar.current.isDateInToday($0.dueDate) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    if todaysTasks.isEmpty {
                        Text("No care tasks for today yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(todaysTasks) { task in
                            ReminderCard(
                                title: "\(task.title) (\(task.plantName))",
                                dueDate: task.dueDate,
                                notes: task.notes,
                                isCompleted: task.isCompleted
                            ) {
                                toggleComplete(task)
                            }
                        }
                    }
                }

                Section("Check-in") {
                    Text("How did your plant respond after the last watering?")
                        .font(.subheadline)
                    Button("It looks healthier") { checkInSelection = "It looks healthier" }
                    Button("No change yet") { checkInSelection = "No change yet" }
                    Button("Leaves look worse") { checkInSelection = "Leaves look worse" }
                    if let checkInSelection {
                        Text("Selected: \(checkInSelection)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Care Today")
        }
    }

    private func toggleComplete(_ task: CareTask) {
        task.isCompleted.toggle()
    }
}

struct ReviewPlanView: View {
    let plantName: String?
    @Query(sort: \CareTask.dueDate, order: .forward) private var tasks: [CareTask]
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var profiles: [PlantProfile]
    @StateObject private var googleAuth = GoogleAuthManager()
    @State private var syncStatusMessage = ""
    @State private var showSyncAlert = false

    init(plantName: String? = nil) {
        self.plantName = plantName
    }

    private var activePlantName: String {
        if let plantName, !plantName.isEmpty {
            return plantName
        }
        return profiles.first?.name ?? tasks.first?.plantName ?? "My Plant"
    }

    private var activeTasks: [CareTask] {
        tasks.filter { $0.plantName.localizedCaseInsensitiveCompare(activePlantName) == .orderedSame }
    }

    private var sourceTasks: [CareTask] {
        if let plantName, !plantName.isEmpty {
            return activeTasks
        }
        return activeTasks.isEmpty ? tasks : activeTasks
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review Plan")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Default plan first. You can customize later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                PlanCardView(
                    title: "Water",
                    frequencyText: frequencyText(for: "water", fallback: "About once a week"),
                    nextDate: nextDate(for: "water"),
                    tipText: tipText(for: "water", fallback: "Water in the morning/evening; avoid noon heat."),
                    confidenceText: confidenceText(for: "water")
                )

                PlanCardView(
                    title: "Fertilize",
                    frequencyText: frequencyText(for: "fertiliz", fallback: "Once a month"),
                    nextDate: nextDate(for: "fertiliz"),
                    tipText: tipText(for: "fertiliz", fallback: "Skip in winter if growth slows.")
                )

                PlanCardView(
                    title: "Soil Check",
                    frequencyText: frequencyText(for: "soil", fallback: "Every 1-2 weeks"),
                    nextDate: nextDate(for: "soil"),
                    tipText: tipText(for: "soil", fallback: "Only water if top soil feels dry.")
                )

                Button("Sync to Google Calendar") {
                    syncToGoogleCalendar()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(maxWidth: .infinity)

                Text("Only plant-care events are synced.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(activePlantName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Calendar Sync", isPresented: $showSyncAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(syncStatusMessage)
        }
        .onReceive(googleAuth.$errorMessage) { message in
            guard let message, !message.isEmpty else { return }
            syncStatusMessage = message
            showSyncAlert = true
        }
    }

    private func syncToGoogleCalendar() {
        Task {
            await googleAuth.signIn()
            guard googleAuth.isSignedIn, let token = googleAuth.accessToken else {
                return
            }

            let plan = sourceTasks.prefix(20).map { task in
                CalendarPlanItem(
                    title: task.title,
                    guidance: task.notes,
                    rrule: "FREQ=WEEKLY;INTERVAL=1",
                    startDate: task.dueDate
                )
            }

            do {
                try await GoogleCalendarService().createEvents(from: plan, accessToken: token)
                syncStatusMessage = "Synced \(plan.count) care events to Google Calendar."
            } catch {
                syncStatusMessage = error.localizedDescription
            }
            showSyncAlert = true
        }
    }

    private func matchingTasks(_ keyword: String) -> [CareTask] {
        return sourceTasks
            .filter { $0.title.lowercased().contains(keyword) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private func frequencyText(for keyword: String, fallback: String) -> String {
        let matched = matchingTasks(keyword)
        if matched.count >= 2 {
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: matched[0].dueDate),
                to: Calendar.current.startOfDay(for: matched[1].dueDate)
            ).day ?? 0
            if days > 0 && days <= 3 { return "Every \(days) days" }
            if days == 7 { return "About once a week" }
            if days >= 28 { return "Once a month" }
            if days > 0 { return "Every \(days) days" }
        }
        return fallback
    }

    private func nextDate(for keyword: String) -> Date? {
        matchingTasks(keyword).first?.dueDate
    }

    private func tipText(for keyword: String, fallback: String) -> String {
        matchingTasks(keyword).first(where: { !$0.notes.isEmpty })?.notes ?? fallback
    }

    private func confidenceText(for keyword: String) -> String {
        let count = matchingTasks(keyword).count
        if count >= 3 { return "High" }
        if count >= 2 { return "Medium" }
        return "Medium"
    }
}

private struct PlanCardView: View {
    let title: String
    let frequencyText: String
    let nextDate: Date?
    let tipText: String
    var confidenceText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title) - \(frequencyText)")
                .font(.headline)

            if let nextDate {
                HStack(spacing: 6) {
                    Text("Next:")
                    Text(nextDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                }
                .font(.subheadline)
            }

            Text("Tip:")
                .font(.subheadline.weight(.semibold))
            Text(tipText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let confidenceText {
                Text("Confidence: \(confidenceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [
            PlantProfile.self,
            ChatMessage.self,
            ConversationSummary.self,
            PlantMemory.self,
            CareTask.self
        ], inMemory: true)
}
