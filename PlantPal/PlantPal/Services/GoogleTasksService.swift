import Foundation

struct GoogleTasksService {
    struct TasksAPIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Creates tasks and returns the Google Tasks IDs for each created task
    @discardableResult
    func createTasks(from plan: [TaskPlanItem], accessToken: String) async throws -> [String] {
        var taskIds: [String] = []

        for item in plan {
            guard let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks") else {
                throw TasksAPIError(message: "Invalid tasks endpoint")
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Use local calendar date so Google shows the same day as the app (avoids timezone off-by-one)
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: item.dueDate)
            let dateToSend = cal.date(from: comps) ?? item.dueDate
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let dueDate = dateFormatter.string(from: dateToSend)

            let payload: [String: Any] = [
                "title": item.title,
                "notes": item.notes,
                "due": dueDate,
                "status": "needsAction"
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw TasksAPIError(message: "Google Tasks error: HTTP \(http.statusCode) - \(text)")
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let taskId = json["id"] as? String {
                taskIds.append(taskId)
            }
        }

        return taskIds
    }

    /// Deletes tasks from Google Tasks by their IDs
    func deleteTasks(ids: [String], accessToken: String) async throws {
        for id in ids {
            guard let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks/\(id)") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) && http.statusCode != 404 {
                throw TasksAPIError(message: "Failed to delete task: HTTP \(http.statusCode)")
            }
        }
    }
    
    /// Updates a task's completion status
    func updateTaskStatus(taskId: String, isCompleted: Bool, accessToken: String) async throws {
        guard let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks/\(taskId)") else {
            throw TasksAPIError(message: "Invalid tasks endpoint")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "status": isCompleted ? "completed" : "needsAction"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw TasksAPIError(message: "Failed to update task status: HTTP \(http.statusCode) - \(text)")
        }
    }

    /// Fetches completion status for all tasks in the default list (for syncing Google → App).
    func fetchTasksStatus(accessToken: String) async throws -> [String: Bool] {
        var result: [String: Bool] = [:]
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks")!
            components.queryItems = [
                URLQueryItem(name: "maxResults", value: "100"),
                URLQueryItem(name: "showCompleted", value: "true")
            ]
            if let token = pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: token))
            }
            guard let url = components.url else { throw TasksAPIError(message: "Invalid tasks list URL") }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let text = String(data: data, encoding: .utf8) ?? ""
                throw TasksAPIError(message: "Google Tasks list error: HTTP \(http.statusCode) - \(text)")
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }
            let items = json["items"] as? [[String: Any]] ?? []
            for item in items {
                guard let id = item["id"] as? String,
                      let status = item["status"] as? String else { continue }
                result[id] = (status == "completed")
            }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil
        return result
    }
}

struct TaskPlanItem: Identifiable {
    let id = UUID()
    let title: String
    let notes: String
    let dueDate: Date
}
