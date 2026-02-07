import Foundation

struct GoogleCalendarService {
    struct CalendarAPIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func createEvents(from plan: [CalendarPlanItem], accessToken: String) async throws {
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events") else {
            throw CalendarAPIError(message: "Invalid calendar endpoint")
        }

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

            let payload: [String: Any] = [
                "summary": item.title,
                "description": item.guidance,
                "start": ["date": startDate],
                "end": ["date": endDate],
                "recurrence": ["RRULE:\(item.rrule)"]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw CalendarAPIError(message: "Google Calendar error: HTTP \(http.statusCode)")
            }
        }
    }
}

struct CalendarPlanItem: Identifiable {
    let id = UUID()
    let title: String
    let guidance: String
    let rrule: String
    let startDate: Date
}
