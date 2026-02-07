import SwiftUI

struct ReminderCard: View {
    let item: ReminderItem
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(item.dueDate, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Snooze") {
                // Placeholder for snooze logic.
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    ReminderCard(item: ReminderItem(title: "Water Monstera", dueDate: .daysFromNow(0), isCompleted: false)) {
        // Preview action
    }
}
