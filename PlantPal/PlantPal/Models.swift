import Foundation
import SwiftData

@Model
final class PlantProfile {
    var name: String
    var type: String
    var location: String
    var personaName: String
    var createdAt: Date

    init(name: String, type: String, location: String, personaName: String) {
        self.name = name
        self.type = type
        self.location = location
        self.personaName = personaName
        self.createdAt = Date()
    }
}

@Model
final class ChatMessage {
    var role: String
    var content: String
    var createdAt: Date
    var plantName: String

    init(role: String, content: String, plantName: String) {
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.plantName = plantName
    }
}

@Model
final class ConversationSummary {
    var summary: String
    var plantName: String
    var updatedAt: Date

    init(summary: String, plantName: String) {
        self.summary = summary
        self.plantName = plantName
        self.updatedAt = Date()
    }
}

@Model
final class PlantMemory {
    var plantName: String
    var wateringFrequencyDays: Int?
    var lightPreference: String?
    var latestAdjustmentReason: String?
    var updatedAt: Date

    init(plantName: String,
         wateringFrequencyDays: Int? = nil,
         lightPreference: String? = nil,
         latestAdjustmentReason: String? = nil) {
        self.plantName = plantName
        self.wateringFrequencyDays = wateringFrequencyDays
        self.lightPreference = lightPreference
        self.latestAdjustmentReason = latestAdjustmentReason
        self.updatedAt = Date()
    }
}

@Model
final class CareTask {
    var plantName: String
    var title: String
    var notes: String
    var dueDate: Date
    var isCompleted: Bool
    var createdAt: Date

    init(plantName: String,
         title: String,
         notes: String,
         dueDate: Date,
         isCompleted: Bool = false) {
        self.plantName = plantName
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.createdAt = Date()
    }
}

struct ReminderItem: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var dueDate: Date
    var isCompleted: Bool
}

struct PendingCareTask: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var notes: String
    var dueDate: Date
}

struct PendingCarePlan: Identifiable, Hashable {
    let id = UUID()
    var plantName: String
    var tasks: [PendingCareTask]
    var explanation: String?
}

extension Date {
    static func daysFromNow(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
    }
}
