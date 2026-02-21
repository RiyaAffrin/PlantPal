import SwiftUI
import SwiftData

struct AdjustPlanPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CareTask.dueDate, order: .forward) private var allTasks: [CareTask]

    let draft: PendingPlanAdjustment

    @State private var showReasonAlert = false
    @State private var reasonAlertText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review Changes")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                HStack(alignment: .top, spacing: 14) {
                    taskColumn(title: "Current care plan", tasks: draft.currentTasks, showChangeActions: false)
                    Divider()
                    taskColumn(title: "Proposed care plan", tasks: draft.proposedTasks, showChangeActions: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Suggested plan")
                        .font(.headline)
                    ForEach(draft.strategySummary, id: \.self) { line in
                        Text("- \(line)")
                            .font(.subheadline)
                    }
                    if let optionalTip = draft.optionalTip, !optionalTip.isEmpty {
                        Text("Optional: \(optionalTip)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button("Apply Changes") {
                    applyChanges()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .frame(maxWidth: .infinity)

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationTitle(draft.plantName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Why this change", isPresented: $showReasonAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reasonAlertText)
        }
    }

    private func taskColumn(title: String, tasks: [PendingCareTask], showChangeActions: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 4) {
                    Text("• \(taskDateText(task.dueDate)) - \(task.title)")
                        .font(.subheadline)

                    if showChangeActions, let change = draft.changes.first(where: { $0.proposedTask == task }) {
                        HStack(spacing: 8) {
                            Button("WHY") {
                                reasonAlertText = change.reason
                                showReasonAlert = true
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)

                            Button("EDIT") {
                                // Placeholder only for now; edit action will be added later.
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func applyChanges() {
        let existing = allTasks.filter { $0.plantName.localizedCaseInsensitiveCompare(draft.plantName) == .orderedSame }
        existing.forEach { modelContext.delete($0) }

        draft.proposedTasks.forEach { task in
            modelContext.insert(
                CareTask(
                    plantName: draft.plantName,
                    title: task.title,
                    notes: task.notes,
                    dueDate: task.dueDate
                )
            )
        }
    }

    private func taskDateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

#Preview {
    AdjustPlanPreviewView(
        draft: PendingPlanAdjustment(
            plantName: "Janie",
            currentTasks: [
                PendingCareTask(title: "Water", notes: "", dueDate: .daysFromNow(0)),
                PendingCareTask(title: "Water", notes: "", dueDate: .daysFromNow(6))
            ],
            proposedTasks: [
                PendingCareTask(title: "Water", notes: "", dueDate: .daysFromNow(-1)),
                PendingCareTask(title: "Water", notes: "", dueDate: .daysFromNow(7))
            ],
            strategySummary: [
                "Water once before your trip.",
                "Pause reminders while you are away.",
                "Resume your regular schedule after you return."
            ],
            optionalTip: "Add one mid-trip soil check if someone can help.",
            changes: []
        )
    )
    .modelContainer(for: [CareTask.self], inMemory: true)
}
