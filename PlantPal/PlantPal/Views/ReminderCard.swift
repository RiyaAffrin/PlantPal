import SwiftUI

struct ReminderCard: View {
    let title: String
    let dueDate: Date
    let notes: String
    let isCompleted: Bool
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isCompleted ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(dueDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    ReminderCard(
        title: "Water Monstera",
        dueDate: .daysFromNow(0),
        notes: "Check top 2 inches of soil first.",
        isCompleted: false
    ) {
        // Preview action
    }
}
