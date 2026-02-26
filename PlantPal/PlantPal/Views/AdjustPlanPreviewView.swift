import SwiftUI
import SwiftData

struct AdjustPlanPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var googleAuth: GoogleAuthManager
    @Query(sort: \CareTask.dueDate, order: .forward) private var allTasks: [CareTask]

    @Binding var selectedTab: Int
    @State var draft: PendingPlanAdjustment

    // WHY / EDIT panel state
    @State private var expandedWhyId: UUID?
    @State private var editingChangeId: UUID?
    @State private var editPickerDate = Date()

    // apply / revert state
    @State private var isApplied = false
    @State private var isApplying = false
    @State private var previousTasks: [PendingCareTask] = []
    @State private var isReverting = false
    @State private var syncError: String?
    @State private var showSyncAlert = false

    var body: some View {
        ScrollView {
            if isApplied {
                appliedView
            } else {
                reviewView
            }
        }
        .navigationTitle(draft.plantName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sync Status", isPresented: $showSyncAlert) {
            Button("OK") {}
        } message: {
            Text(syncError ?? "")
        }
    }

    // MARK: - Review (before apply)

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Changes")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            HStack(alignment: .top, spacing: 14) {
                taskColumn(title: "Current care plan", tasks: draft.currentTasks, isProposed: false)
                Divider()
                taskColumn(title: "Proposed care plan", tasks: draft.proposedTasks, isProposed: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let whyId = expandedWhyId,
               let change = draft.changes.first(where: { $0.id == whyId }) {
                whyPanel(for: change)
            }

            if let editId = editingChangeId,
               let changeIndex = draft.changes.firstIndex(where: { $0.id == editId }) {
                editPanel(for: changeIndex)
            }

            Button(isApplying ? "Applying..." : "Apply Changes") {
                Task { await applyChanges() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .frame(maxWidth: .infinity)
            .disabled(isApplying)

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    // Applied confirmation

    private var appliedView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Changes Applied!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Synced to Google Calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.green.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // brief summary of what changed
            if !draft.changes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.headline)

                    ForEach(draft.changes) { change in
                        let from = taskDateText(change.originalTask.dueDate)
                        let to = taskDateText(change.proposedTask.dueDate)
                        Text("• \(change.proposedTask.title): \(from) → \(to)")
                            .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            // calendar schedule
            VStack(alignment: .leading, spacing: 8) {
                Text("Calendar")
                    .font(.headline)

                ForEach(draft.proposedTasks) { task in
                    HStack {
                        Text("•")
                        Text(taskDateText(task.dueDate))
                            .bold()
                        Text("–")
                        Text(task.title)
                    }
                    .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Button(isReverting ? "Reverting..." : "Revert Changes") {
                Task { await revertChanges() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .frame(maxWidth: .infinity)
            .disabled(isReverting)

            Button("Back to Home") {
                selectedTab = 0
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    // Task columns

    private func taskColumn(title: String, tasks: [PendingCareTask], isProposed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(isProposed ? .green : .primary)

            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 4) {
                    Text("• \(taskDateText(task.dueDate)) - \(task.title)")
                        .font(.subheadline)

                    if isProposed, let change = draft.changes.first(where: { $0.proposedTask == task }) {
                        HStack(spacing: 8) {
                            Button("EDIT") {
                                withAnimation {
                                    expandedWhyId = nil
                                    editPickerDate = change.proposedTask.dueDate
                                    editingChangeId = editingChangeId == change.id ? nil : change.id
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)
                            .font(.caption)

                            Button("WHY") {
                                withAnimation {
                                    editingChangeId = nil
                                    expandedWhyId = expandedWhyId == change.id ? nil : change.id
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // WHY panel

    private func whyPanel(for change: PendingTaskChange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why this change?")
                .font(.headline)

            Text(change.reason)
                .font(.subheadline)

            Text("You can edit or remove this change if it doesn't fit your schedule.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemYellow).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // EDIT panel

    private func editPanel(for changeIndex: Int) -> some View {
        let change = draft.changes[changeIndex]
        let calendar = Calendar.current
        let proposedDate = change.proposedTask.dueDate
        let oneDayEarlier = calendar.date(byAdding: .day, value: -1, to: proposedDate) ?? proposedDate
        let twoDaysEarlier = calendar.date(byAdding: .day, value: -2, to: proposedDate) ?? proposedDate

        return VStack(alignment: .leading, spacing: 10) {
            Text("Edit: \(change.proposedTask.title)")
                .font(.headline)

            Button {
                editPickerDate = oneDayEarlier
            } label: {
                HStack {
                    Image(systemName: calendar.isDate(editPickerDate, inSameDayAs: oneDayEarlier) ? "largecircle.fill.circle" : "circle")
                    Text("One day earlier (\(taskDateText(oneDayEarlier)))")
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)

            Button {
                editPickerDate = twoDaysEarlier
            } label: {
                HStack {
                    Image(systemName: calendar.isDate(editPickerDate, inSameDayAs: twoDaysEarlier) ? "largecircle.fill.circle" : "circle")
                    Text("Two days earlier (\(taskDateText(twoDaysEarlier)))")
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)

            HStack {
                let isCustom = !calendar.isDate(editPickerDate, inSameDayAs: oneDayEarlier)
                    && !calendar.isDate(editPickerDate, inSameDayAs: twoDaysEarlier)
                Image(systemName: isCustom ? "largecircle.fill.circle" : "circle")
                Text("Choose date")
                    .font(.subheadline)
                DatePicker("", selection: $editPickerDate, displayedComponents: .date)
                    .labelsHidden()
            }

            HStack(spacing: 12) {
                Button("Confirm") {
                    withAnimation {
                        commitDateEdit(changeIndex: changeIndex, newDate: editPickerDate)
                        editingChangeId = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .font(.subheadline)

                Button("Cancel") {
                    withAnimation {
                        editingChangeId = nil
                    }
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func commitDateEdit(changeIndex: Int, newDate: Date) {
        let change = draft.changes[changeIndex]
        let oldProposed = change.proposedTask

        if let taskIdx = draft.proposedTasks.firstIndex(of: oldProposed) {
            let updated = PendingCareTask(title: oldProposed.title, notes: oldProposed.notes, dueDate: newDate)
            draft.proposedTasks[taskIdx] = updated
            draft.changes[changeIndex].proposedTask = updated
            draft.proposedTasks.sort { $0.dueDate < $1.dueDate }
        }
    }

    // Apply changes (SwiftData + Google Calendar)

    private func applyChanges() async {
        isApplying = true
        previousTasks = draft.currentTasks

        let existing = allTasks.filter { $0.plantName.localizedCaseInsensitiveCompare(draft.plantName) == .orderedSame }
        let tasksService = GoogleTasksService()

        // delete old tasks from Google Tasks before removing local data
        if let token = googleAuth.accessToken {
            let oldTaskIds = existing.compactMap(\.googleEventId)
            if !oldTaskIds.isEmpty {
                try? await tasksService.deleteTasks(ids: oldTaskIds, accessToken: token)
            }
        }

        existing.forEach { modelContext.delete($0) }

        // create new CareTask objects
        var newCareTasks: [CareTask] = []
        for task in draft.proposedTasks {
            let ct = CareTask(plantName: draft.plantName, title: task.title, notes: task.notes, dueDate: task.dueDate)
            modelContext.insert(ct)
            newCareTasks.append(ct)
        }

        // push new tasks and store their Google IDs for future deletion
        if let token = googleAuth.accessToken {
            let taskItems = draft.proposedTasks.map { task in
                TaskPlanItem(title: task.title, notes: task.notes, dueDate: task.dueDate)
            }
            do {
                let taskIds = try await tasksService.createTasks(from: taskItems, accessToken: token)
                for (i, id) in taskIds.enumerated() where i < newCareTasks.count {
                    newCareTasks[i].googleEventId = id
                }
            } catch {
                syncError = "Plan saved locally, but Google Tasks sync failed: \(error.localizedDescription)"
                showSyncAlert = true
            }
        }

        isApplying = false
        withAnimation { isApplied = true }
    }

    // Revert changes

    private func revertChanges() async {
        isReverting = true

        let existing = allTasks.filter { $0.plantName.localizedCaseInsensitiveCompare(draft.plantName) == .orderedSame }
        let tasksService = GoogleTasksService()

        // delete the applied tasks from Google Tasks
        if let token = googleAuth.accessToken {
            let currentTaskIds = existing.compactMap(\.googleEventId)
            if !currentTaskIds.isEmpty {
                try? await tasksService.deleteTasks(ids: currentTaskIds, accessToken: token)
            }
        }

        existing.forEach { modelContext.delete($0) }

        // restore previous tasks
        var restoredCareTasks: [CareTask] = []
        for task in previousTasks {
            let ct = CareTask(plantName: draft.plantName, title: task.title, notes: task.notes, dueDate: task.dueDate)
            modelContext.insert(ct)
            restoredCareTasks.append(ct)
        }

        // push reverted plan and store task IDs
        if let token = googleAuth.accessToken {
            let taskItems = previousTasks.map { task in
                TaskPlanItem(title: task.title, notes: task.notes, dueDate: task.dueDate)
            }
            do {
                let taskIds = try await tasksService.createTasks(from: taskItems, accessToken: token)
                for (i, id) in taskIds.enumerated() where i < restoredCareTasks.count {
                    restoredCareTasks[i].googleEventId = id
                }
            } catch {
                syncError = "Tasks reverted locally, but Google Tasks sync failed: \(error.localizedDescription)"
                showSyncAlert = true
            }
        }

        isReverting = false
        selectedTab = 0
        dismiss()
    }

    private func taskDateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}
