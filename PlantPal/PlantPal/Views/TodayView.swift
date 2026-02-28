import SwiftUI
import SwiftData
import PhotosUI

struct TodayView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject private var googleAuth: GoogleAuthManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var profiles: [PlantProfile]
    @Query(sort: \CareTask.dueDate, order: .forward) private var tasks: [CareTask]
    @Query private var referencePhotos: [PlantReferencePhoto]
    @State private var checkInSelection: String?
    @State private var checkInNewPhotoData: Data?
    @State private var checkInSelectedPhotoItem: PhotosPickerItem?
    @State private var showCheckInPhotoSource = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    
    @State private var checkInPhotoPromptPlantName: String?
    
    @State private var checkInContextPlantName: String?
    
    @State private var listRefreshID = UUID()

    private var todaysTasks: [CareTask] {
        tasks.filter { Calendar.current.isDateInToday($0.dueDate) }
    }


    private func todaysTasks(for plantName: String) -> [CareTask] {
        todaysTasks.filter { $0.plantName.localizedCaseInsensitiveCompare(plantName) == .orderedSame }
    }

    private var primaryPlantName: String? {
        profiles.first?.name
    }

    /// The "old" photo from last check-in (or last time user took a photo for this plant).
    private var checkInReferencePhoto: PlantReferencePhoto? {
        guard let name = primaryPlantName else { return nil }
        return referencePhotos.first { $0.plantName.localizedCaseInsensitiveCompare(name) == .orderedSame && $0.imageData != nil }
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

                if let ref = checkInReferencePhoto, let data = ref.imageData, let uiImage = UIImage(data: data) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        if let date = ref.photoDate {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if let newData = checkInNewPhotoData, let uiImage = UIImage(data: newData) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text("Today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Button {
                    showCheckInPhotoSource = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera")
                        Text("Take or select a photo")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .popover(isPresented: $showCheckInPhotoSource, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Add a photo to compare next time.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 8)
                        Button {
                            showCheckInPhotoSource = false
                            showCamera = true
                        } label: {
                            Text("Take Photo")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        Button {
                            showCheckInPhotoSource = false
                            showPhotoPicker = true
                        } label: {
                            Text("Choose from Library")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        Divider()
                        Button("Cancel", role: .cancel) {
                            showCheckInPhotoSource = false
                            checkInContextPlantName = nil
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .presentationCompactAdaptation(.popover)
                }

                checkInOptionButton(title: "It looks healthier")
                checkInOptionButton(title: "No change yet")
                checkInOptionButton(title: "Leaves look worse")

                if let checkInSelection {
                    Text("Selected: \(checkInSelection)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .id(listRefreshID)
        .navigationTitle("Care Today")
        .refreshable {
            await syncCompletionFromGoogle(afterSync: { listRefreshID = UUID() })
        }
        .sheet(isPresented: $showCamera) {
            CameraImagePicker(imageData: $checkInNewPhotoData)
        }
        .sheet(isPresented: $showPhotoPicker) {
            NavigationStack {
                PhotosPicker(selection: $checkInSelectedPhotoItem, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .onChange(of: checkInSelectedPhotoItem) { _, _ in
                    showPhotoPicker = false
                }
                .padding()
                .navigationTitle("Select Photo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showPhotoPicker = false
                        }
                    }
                }
            }
        }
        .onChange(of: checkInSelectedPhotoItem) { _, newItem in
            Task {
                guard let item = newItem else { return }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { checkInNewPhotoData = data }
                }
            }
        }
        .onChange(of: checkInSelection) { _, newValue in
            if newValue != nil {
                saveCheckInPhotoIfNeeded()
            }
        }
        .task(id: googleAuth.isSignedIn) {
            await syncCompletionFromGoogle(afterSync: { listRefreshID = UUID() })
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 0 {
                Task { await syncCompletionFromGoogle(afterSync: { listRefreshID = UUID() }) }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await syncCompletionFromGoogle(afterSync: { listRefreshID = UUID() }) }
            }
        }
        .onAppear {
            Task { await syncCompletionFromGoogle(afterSync: { listRefreshID = UUID() }) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await syncCompletionFromGoogle(afterSync: { listRefreshID = UUID() }) }
        }
        .alert("今日任务都完成啦", isPresented: Binding(
            get: { checkInPhotoPromptPlantName != nil },
            set: { if !$0 { checkInPhotoPromptPlantName = nil } }
        )) {
            Button("拍照记录") {
                if let plant = checkInPhotoPromptPlantName {
                    checkInContextPlantName = plant
                    checkInPhotoPromptPlantName = nil
                    showCheckInPhotoSource = true
                }
            }
            Button("稍后", role: .cancel) {
                checkInPhotoPromptPlantName = nil
            }
        } message: {
            if let plant = checkInPhotoPromptPlantName {
                Text("给 \(plant) 拍一张照片做 check-in 吧？")
            }
        }
    }

    private func checkInOptionButton(title: String) -> some View {
        Button {
            checkInSelection = title
        } label: {
            HStack {
                Text(title)
                Spacer()
                if checkInSelection == title {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    /// When user has selected a response, save the new photo (if any) as the reference for next check-in.
    private func saveCheckInPhotoIfNeeded() {
        let plantName = checkInContextPlantName ?? primaryPlantName
        guard let plantName, let data = checkInNewPhotoData, !data.isEmpty else {
            checkInNewPhotoData = nil
            checkInSelectedPhotoItem = nil
            return
        }
        let existing = referencePhotos.first { $0.plantName.localizedCaseInsensitiveCompare(plantName) == .orderedSame }
        if let existing {
            existing.imageData = data
            existing.photoDate = Date()
        } else {
            let ref = PlantReferencePhoto(plantName: plantName, imageData: data, photoDate: Date())
            modelContext.insert(ref)
        }
        checkInNewPhotoData = nil
        checkInSelectedPhotoItem = nil
        checkInContextPlantName = nil
    }

    private func toggleComplete(_ task: CareTask) {
        let wasCompleted = task.isCompleted
        task.isCompleted.toggle()
        
        if !wasCompleted && task.isCompleted {
            let forPlant = todaysTasks(for: task.plantName)
            if !forPlant.isEmpty && forPlant.allSatisfy(\.isCompleted) {
                checkInPhotoPromptPlantName = task.plantName
            }
        }
        Task { await syncCompletionToGoogle(task) }
    }

    /// App → Google: when user marks complete in the app, update Google Task.
    private func syncCompletionToGoogle(_ task: CareTask) async {
        guard let taskId = task.googleEventId,
              let token = googleAuth.accessToken else { return }
        do {
            try await GoogleTasksService().updateTaskStatus(taskId: taskId, isCompleted: task.isCompleted, accessToken: token)
        } catch {
            // Optionally surface error (e.g. toast); for now fail silently to avoid blocking UI
        }
    }


    private func syncCompletionFromGoogle(afterSync: (@Sendable () -> Void)? = nil) async {
        guard googleAuth.isSignedIn, let token = googleAuth.accessToken else { return }
        do {
            let statusMap = try await GoogleTasksService().fetchTasksStatus(accessToken: token)
            await MainActor.run {
                for task in tasks where task.googleEventId != nil {
                    guard let id = task.googleEventId, let completed = statusMap[id] else { continue }
                    if task.isCompleted != completed {
                        task.isCompleted = completed
                    }
                }
                try? modelContext.save()
                afterSync?()
            }
        } catch {
            // Optionally surface error
        }
    }
}

struct ReviewPlanView: View {
    @Environment(\.modelContext) private var modelContext
    let plantName: String?
    let draftPlan: PendingCarePlan?
    /// When entering from the Chat flow, click OK in the Calendar Sync pop-up and switch back to Today.
    var selectedTab: Binding<Int>? = nil
    /// Called when user taps OK after Apply Plan (e.g. reset Chat to a new conversation).
    var onDismissAfterApply: (() -> Void)? = nil
    @Query(sort: \CareTask.dueDate, order: .forward) private var tasks: [CareTask]
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var profiles: [PlantProfile]
    @EnvironmentObject private var googleAuth: GoogleAuthManager
    @State private var isApplying = false
    @State private var isSyncing = false
    @State private var syncStatusMessage = ""
    @State private var showSyncAlert = false

    init(plantName: String? = nil, draftPlan: PendingCarePlan? = nil, selectedTab: Binding<Int>? = nil, onDismissAfterApply: (() -> Void)? = nil) {
        self.plantName = plantName
        self.draftPlan = draftPlan
        self.selectedTab = selectedTab
        self.onDismissAfterApply = onDismissAfterApply
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

    private var sortedTasksByDate: [PendingCareTask] {
        sourceTasks.sorted { $0.dueDate < $1.dueDate }
    }

    /// CareTask array that matches the displayed plan (for syncing to Google Tasks).
    private var careTasksForSync: [CareTask] {
        let forPlant = tasks.filter { $0.plantName.localizedCaseInsensitiveCompare(activePlantName) == .orderedSame }.sorted { $0.dueDate < $1.dueDate }
        if forPlant.isEmpty && !tasks.isEmpty {
            return tasks.sorted { $0.dueDate < $1.dueDate }
        }
        return forPlant
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Full Care Schedule")
                        .font(.headline)

                    ForEach(sortedTasksByDate) { task in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(task.dueDate, format: .dateTime.month(.abbreviated).day()) - \(task.title)")
                                    .font(.subheadline)
                                if !task.notes.isEmpty {
                                    Text(task.notes)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 16))

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

                        Button(isSyncing ? "Syncing..." : "Sync to Google Calendar") {
                            Task { await syncToGoogleCalendar() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .frame(maxWidth: .infinity)
                        .disabled(!googleAuth.isSignedIn || isSyncing || careTasksForSync.isEmpty)
                    }

                    Text("Only plant-care events are synced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(activePlantName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Calendar Sync", isPresented: $showSyncAlert) {
            Button("OK", role: .cancel) {
                selectedTab?.wrappedValue = 0
                onDismissAfterApply?()
            }
        } message: {
            Text(syncStatusMessage)
        }
        .onReceive(googleAuth.$errorMessage) { message in
            guard let message, !message.isEmpty else { return }
            syncStatusMessage = message
            showSyncAlert = true
        }
    }

    private func syncToGoogleCalendar() async {
        guard let token = googleAuth.accessToken else {
            syncStatusMessage = "Please connect to Google Calendar first."
            showSyncAlert = true
            return
        }
        let careTasksToSync = careTasksForSync
        if careTasksToSync.isEmpty {
            syncStatusMessage = "No care tasks to sync."
            showSyncAlert = true
            return
        }
        isSyncing = true
        let tasksService = GoogleTasksService()
        let oldTaskIds = careTasksToSync.compactMap(\.googleEventId)
        if !oldTaskIds.isEmpty {
            try? await tasksService.deleteTasks(ids: oldTaskIds, accessToken: token)
        }
        let taskItems = careTasksToSync.map { TaskPlanItem(title: $0.title, notes: $0.notes, dueDate: $0.dueDate) }
        do {
            let taskIds = try await tasksService.createTasks(from: taskItems, accessToken: token)
            for (i, id) in taskIds.enumerated() where i < careTasksToSync.count {
                careTasksToSync[i].googleEventId = id
            }
            syncStatusMessage = "Synced \(taskIds.count) care events to Google Tasks."
        } catch {
            syncStatusMessage = "Sync failed: \(error.localizedDescription)"
        }
        showSyncAlert = true
        isSyncing = false
    }

    private func applyDraftPlan() async {
        guard let draftPlan, let token = googleAuth.accessToken else { return }
        isApplying = true

        let existing = tasks.filter { $0.plantName.localizedCaseInsensitiveCompare(draftPlan.plantName) == .orderedSame }
        let tasksService = GoogleTasksService()

        // delete previous Google tasks if they exist
        let oldTaskIds = existing.compactMap(\.googleEventId)
        if !oldTaskIds.isEmpty {
            try? await tasksService.deleteTasks(ids: oldTaskIds, accessToken: token)
        }

        existing.forEach { modelContext.delete($0) }

        // create new CareTask objects
        var newCareTasks: [CareTask] = []
        for task in draftPlan.tasks {
            let ct = CareTask(plantName: draftPlan.plantName, title: task.title, notes: task.notes, dueDate: task.dueDate)
            modelContext.insert(ct)
            newCareTasks.append(ct)
        }

        // push to Google Tasks and store task IDs
        let taskItems = draftPlan.tasks.map { task in
            TaskPlanItem(title: task.title, notes: task.notes, dueDate: task.dueDate)
        }

        do {
            let taskIds = try await tasksService.createTasks(from: taskItems, accessToken: token)
            for (i, id) in taskIds.enumerated() where i < newCareTasks.count {
                newCareTasks[i].googleEventId = id
            }
            syncStatusMessage = "Plan applied and \(taskItems.count) tasks added to Google Tasks."
        } catch {
            syncStatusMessage = "Plan saved locally, but Google Tasks sync failed: \(error.localizedDescription)"
        }

        showSyncAlert = true
        isApplying = false
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
        .environmentObject(GoogleAuthManager())
        .modelContainer(for: [
            PlantProfile.self,
            ChatMessage.self,
            ConversationSummary.self,
            PlantMemory.self,
            CareTask.self,
            PlantReferencePhoto.self
        ], inMemory: true)
}
