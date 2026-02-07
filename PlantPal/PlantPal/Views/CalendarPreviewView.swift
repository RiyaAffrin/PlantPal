import SwiftUI

struct CalendarPreviewView: View {
    private let items: [ReminderItem] = [
        ReminderItem(title: "Water Monstera", dueDate: .daysFromNow(1), isCompleted: false),
        ReminderItem(title: "Check soil moisture", dueDate: .daysFromNow(3), isCompleted: false),
        ReminderItem(title: "Rotate pot", dueDate: .daysFromNow(7), isCompleted: false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(item.title)
                        Text(item.dueDate, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
}

#Preview {
    CalendarPreviewView()
}
