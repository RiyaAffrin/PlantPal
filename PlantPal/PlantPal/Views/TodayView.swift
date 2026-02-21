import SwiftUI
import SwiftData

struct TodayView: View {
    @Binding var selectedTab: Int
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var profiles: [PlantProfile]
    @Query(sort: \CareTask.dueDate, order: .forward) private var tasks: [CareTask]
    @State private var checkInSelection: String?

    private var todaysTasks: [CareTask] {
        tasks.filter { Calendar.current.isDateInToday($0.dueDate) }
    }

    var body: some View {
        NavigationStack {
            if profiles.isEmpty {
                noPlantView
            } else {
                taskListView
            }
        }
    }

    // shown before any plant is set up — mirrors the old HomeView
    private var noPlantView: some View {
        VStack {
            Spacer(minLength: 12)

            Text("PlantPal")
                .font(.system(size: 34, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(red: 0.86, green: 0.97, blue: 0.84))
                .clipShape(RoundedRectangle(cornerRadius: 24))

            Text("We'll create a simple schedule you can follow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer()

            Image(systemName: "leaf.fill")
                .font(.system(size: 96))
                .foregroundStyle(Color(red: 0.35, green: 0.62, blue: 0.32))
                .padding(.vertical, 24)

            Spacer()

            Button("Start setup") {
                selectedTab = 1
            }
            .font(.headline)
            .frame(maxWidth: 240)
            .padding(.vertical, 12)
            .background(Color(red: 0.72, green: 0.95, blue: 0.63))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Text("You can customize later.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // shown once at least one plant exists
    private var taskListView: some View {
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

    private func toggleComplete(_ task: CareTask) {
        task.isCompleted.toggle()
    }
}

struct ReviewPlanView: View {
    @Environment(\.modelContext) private var modelContext
    let plantName: String?
    let draftPlan: PendingCarePlan?
    @Query(sort: \CareTask.dueDate, order: .forward) private var tasks: [CareTask]
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var profiles: [PlantProfile]
    @EnvironmentObject private var googleAuth: GoogleAuthManager
    @State private var isApplying = false
    @State private var syncStatusMessage = ""
    @State private var showSyncAlert = false

    init(plantName: String? = nil, draftPlan: PendingCarePlan? = nil) {
        self.plantName = plantName
        self.draftPlan = draftPlan
    }

    private var activePlantName: String {
        if let draftPlan {
            return draftPlan.plantName
        }
        if let plantName, !plantName.isEmpty {
            return plantName
        }
        return profiles.first?.name ?? tasks.first?.plantName ?? "My Plant"
    }

    private var activeTasks: [PendingCareTask] {
        if let draftPlan {
            return draftPlan.tasks
        }
        return tasks
            .filter { $0.plantName.localizedCaseInsensitiveCompare(activePlantName) == .orderedSame }
            .map { PendingCareTask(title: $0.title, notes: $0.notes, dueDate: $0.dueDate) }
    }

    private var sourceTasks: [PendingCareTask] {
        if draftPlan != nil {
            return activeTasks
        }
        if let plantName, !plantName.isEmpty {
            return activeTasks
        }
        if activeTasks.isEmpty {
            return tasks.map { PendingCareTask(title: $0.title, notes: $0.notes, dueDate: $0.dueDate) }
        }
        return activeTasks
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

                if draftPlan != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(googleAuth.isSignedIn ? "Connected to Google Calendar." : "Not connected to Google Calendar yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if !googleAuth.isSignedIn {
                            Button("Connect to Google Calendar") {
                                Task { await googleAuth.signIn() }
                            }
                            .buttonStyle(.bordered)
                        }

                        Button(isApplying ? "Applying..." : "Apply Plan") {
                            Task { await applyDraftPlan() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .frame(maxWidth: .infinity)
                        .disabled(!googleAuth.isSignedIn || isApplying || sourceTasks.isEmpty)
                    }
                } else {
                    Button("Sync to Google Calendar (Demo)") {
                        syncToGoogleCalendarDemo()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .frame(maxWidth: .infinity)

                    Text("Only plant-care events are synced. Demo mode does not call Google APIs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

    private func syncToGoogleCalendarDemo() {
        let count = min(20, sourceTasks.count)
        syncStatusMessage = "Demo mode: simulated sync of \(count) care events to Google Calendar."
        showSyncAlert = true
    }

    private func applyDraftPlan() async {
        guard let draftPlan, let token = googleAuth.accessToken else { return }
        isApplying = true

        // save to SwiftData first
        replaceTasks(for: draftPlan.plantName, with: draftPlan.tasks)

        // push each task as a one-time event to Google Calendar
        let calendarItems = draftPlan.tasks.map { task in
            CalendarPlanItem(
                title: task.title,
                guidance: task.notes,
                rrule: nil,
                startDate: task.dueDate
            )
        }

        do {
            try await GoogleCalendarService().createEvents(from: calendarItems, accessToken: token)
            syncStatusMessage = "Plan applied and \(calendarItems.count) events added to Google Calendar."
        } catch {
            syncStatusMessage = "Plan saved locally, but calendar sync failed: \(error.localizedDescription)"
        }

        showSyncAlert = true
        isApplying = false
    }

    private func replaceTasks(for plantName: String, with pendingTasks: [PendingCareTask]) {
        let existing = tasks.filter { $0.plantName.localizedCaseInsensitiveCompare(plantName) == .orderedSame }
        existing.forEach { modelContext.delete($0) }

        pendingTasks.forEach { task in
            modelContext.insert(
                CareTask(
                    plantName: plantName,
                    title: task.title,
                    notes: task.notes,
                    dueDate: task.dueDate
                )
            )
        }
    }

    private func matchingTasks(_ keyword: String) -> [PendingCareTask] {
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
    TodayView(selectedTab: .constant(0))
        .modelContainer(for: [
            PlantProfile.self,
            ChatMessage.self,
            ConversationSummary.self,
            PlantMemory.self,
            CareTask.self
        ], inMemory: true)
}
