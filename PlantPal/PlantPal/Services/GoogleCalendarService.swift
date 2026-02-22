import Foundation

struct GoogleCalendarService {
    struct CalendarAPIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Creates events and returns the Google Calendar event IDs for each created event
    @discardableResult
    func createEvents(from plan: [CalendarPlanItem], accessToken: String) async throws -> [String] {
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events") else {
            throw CalendarAPIError(message: "Invalid calendar endpoint")
        }

        var eventIds: [String] = []

        for item in plan {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let dateFormatter = DateFormatter()
            dateFormatter.calendar = Calendar(identifier: .gregorian)
            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            dateFormatter.dateFormat = "yyyy-MM-dd"

            let startDate = dateFormatter.string(from: item.startDate)
            let endDate = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 1, to: item.startDate) ?? item.startDate)

            var payload: [String: Any] = [
                "summary": item.title,
                "description": item.guidance,
                "start": ["date": startDate],
                "end": ["date": endDate]
            ]
            if let rrule = item.rrule {
                payload["recurrence"] = ["RRULE:\(rrule)"]
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw CalendarAPIError(message: "Google Calendar error: HTTP \(http.statusCode)")
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let eventId = json["id"] as? String {
                eventIds.append(eventId)
            }
        }

        return eventIds
    }

    /// Deletes events from Google Calendar by their IDs
    func deleteEvents(ids: [String], accessToken: String) async throws {
        for id in ids {
            guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(id)") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) && http.statusCode != 410 {

                throw CalendarAPIError(message: "Failed to delete event: HTTP \(http.statusCode)")
            }
        }
    }
}

struct CalendarPlanItem: Identifiable {
    let id = UUID()
    let title: String
    let guidance: String
    let rrule: String?   // nil = one-time event, non-nil = recurring
    let startDate: Date
}
