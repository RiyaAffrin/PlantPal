import SwiftUI

struct TodayView: View {
    @State private var reminders: [ReminderItem] = [
        ReminderItem(title: "Water Monstera", dueDate: .daysFromNow(0), isCompleted: false),
        ReminderItem(title: "Mist Fern", dueDate: .daysFromNow(0), isCompleted: false)
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    ForEach(reminders) { item in
                        ReminderCard(item: item) {
                            toggleComplete(item)
                        }
                    }
                }

                Section("Check-in") {
                    Text("How did your plant respond after the last watering?")
                        .font(.subheadline)
                    Button("It looks healthier") {}
                    Button("No change yet") {}
                    Button("Leaves look worse") {}
                }
            }
            .navigationTitle("Care Today")
        }
    }

    private func toggleComplete(_ item: ReminderItem) {
        guard let index = reminders.firstIndex(where: { $0.id == item.id }) else { return }
        reminders[index].isCompleted.toggle()
    }
}

#Preview {
    TodayView()
}
