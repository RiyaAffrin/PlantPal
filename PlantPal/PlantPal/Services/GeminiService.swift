import Foundation

struct GeminiService {
    struct GeminiError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let modelName = "gemini-2.0-flash"

    func generateReply(history: [ChatMessage], memory: PlantMemory?, summary: ConversationSummary?) async throws -> String {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
              !apiKey.isEmpty,
              !apiKey.hasPrefix("<#") else {
            throw GeminiError(message: "Missing GEMINI_API_KEY. Set it in Secrets.xcconfig.")
        }

        let systemInstruction = buildSystemInstruction(memory: memory, summary: summary)
        var contents: [GeminiContent] = []

        if let systemInstruction, !systemInstruction.isEmpty {
            contents.append(GeminiContent(role: "user", parts: [GeminiPart(text: systemInstruction)]))
        }

        contents.append(contentsOf: history.map { message in
            GeminiContent(
                role: message.role == "assistant" ? "model" : "user",
                parts: [GeminiPart(text: message.content)]
            )
        })

        let requestBody = GeminiRequest(contents: contents)

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1/models/\(modelName):generateContent?key=\(apiKey)") else {
            throw GeminiError(message: "Invalid Gemini endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError(message: "Gemini API error: HTTP \(http.statusCode) \(text)")
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.first?.text else {
            throw GeminiError(message: "No response text from Gemini")
        }
        return text
    }

    func generateCareSchedule(plantName: String, plantType: String, location: String) async throws -> [GeminiScheduleTask] {
        let plan = try await generateCareSchedulePlan(plantName: plantName, plantType: plantType, location: location)
        return plan.tasks
    }

    func generateCareSchedulePlan(plantName: String, plantType: String, location: String) async throws -> GeminiCareSchedulePlan {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
              !apiKey.isEmpty,
              !apiKey.hasPrefix("<#") else {
            throw GeminiError(message: "Missing GEMINI_API_KEY. Set it in Secrets.xcconfig.")
        }

        let prompt = """
        You are generating a plant care plan for a mobile app.
        Return JSON only, no markdown.
        JSON schema:
        {
          "explanation": "string",
          "tasks": [
            {
              "title": "string",
              "notes": "string",
              "dayOffset": 0
            }
          ]
        }

        Constraints:
        - Return 5 tasks.
        - dayOffset must be an integer >= 0.
        - Include at least one task with dayOffset = 0.
        - Include at least one watering task and one fertilizing task.
        - Keep title short and actionable.
        - explanation must mention city/region climate and current season, plus watering and fertilizing frequency.
        - explanation should sound friendly and conversational, in 1-2 short sentences.

        Plant name: \(plantName)
        Plant type: \(plantType)
        Location: \(location)
        """

        let requestBody = GeminiRequest(contents: [
            GeminiContent(role: "user", parts: [GeminiPart(text: prompt)])
        ])

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1/models/\(modelName):generateContent?key=\(apiKey)") else {
            throw GeminiError(message: "Invalid Gemini endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError(message: "Gemini API error: HTTP \(http.statusCode) \(text)")
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.first?.text else {
            throw GeminiError(message: "No response text from Gemini")
        }

        return try parseSchedulePlan(from: text)
    }

    /// Generates explanation for why a specific schedule change was proposed
    func generateBatchWhyExplanations(context: String, questions: [String]) async throws -> [String] {
        let numberedQuestions = questions.joined(separator: "\n")
        let prompt = """
        You are a plant biologist explaining care decisions to a plant owner.

        Below are \(questions.count) care schedule changes. For EACH one, write a unique 3-4 sentence explanation rooted in plant biology.

        STRICT RULES:
        - DO NOT mention specific dates, trip dates, or travel plans.
        - DO NOT say "rescheduled to", "moved to", or "falls during your trip".
        - Focus on plant science: root absorption, soil moisture curves, nutrient half-life, phototropism, transpiration, drought tolerance, growth stages.
        - Reference the plant species by name with botanical facts specific to that species.
        - Each explanation must be DIFFERENT in content and structure — do not repeat the same points across explanations.
        - Be warm and conversational. No markdown.

        FORMAT YOUR RESPONSE EXACTLY LIKE THIS (use ---1---, ---2---, etc. as separators):
        ---1---
        [explanation for change 1]
        ---2---
        [explanation for change 2]
        (and so on for each change)

        Plant context:
        \(context)

        Changes:
        \(numberedQuestions)
        """

        let raw = try await sendPrompt(prompt)
        return parseBatchExplanations(raw, expectedCount: questions.count)
    }

    private func parseBatchExplanations(_ text: String, expectedCount: Int) -> [String] {
        var results: [String] = []
        for i in 1...expectedCount {
            let marker = "---\(i)---"
            let nextMarker = "---\(i + 1)---"
            guard let startRange = text.range(of: marker) else { continue }
            let after = text[startRange.upperBound...]
            let content: String
            if let endRange = after.range(of: nextMarker) {
                content = String(after[..<endRange.lowerBound])
            } else {
                content = String(after)
            }
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                results.append(trimmed)
            }
        }
        return results
    }

    // shared helper to fire a single-prompt request to Gemini
    private func sendPrompt(_ prompt: String) async throws -> String {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
              !apiKey.isEmpty, !apiKey.hasPrefix("<#") else {
            throw GeminiError(message: "Missing GEMINI_API_KEY. Set it in Secrets.xcconfig.")
        }

        let requestBody = GeminiRequest(contents: [
            GeminiContent(role: "user", parts: [GeminiPart(text: prompt)])
        ])

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1/models/\(modelName):generateContent?key=\(apiKey)") else {
            throw GeminiError(message: "Invalid Gemini endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError(message: "Gemini API error: HTTP \(http.statusCode) \(text)")
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.first?.text else {
            throw GeminiError(message: "No response text from Gemini")
        }
        return text
    }

    private func buildSystemInstruction(memory: PlantMemory?, summary: ConversationSummary?) -> String? {
        var lines: [String] = [
            "You are PlantPal, an AI plant-care agent.",
            "Respond with clear, concise guidance and follow-up questions when needed.",
            "Use the user's prior plant context if available."
        ]

        if let memory {
            if let freq = memory.wateringFrequencyDays {
                lines.append("Watering frequency: every \(freq) days.")
            }
            if let light = memory.lightPreference {
                lines.append("Light preference: \(light).")
            }
            if let reason = memory.latestAdjustmentReason {
                lines.append("Latest adjustment reason: \(reason).")
            }
        }

        if let summary {
            lines.append("Conversation summary: \(summary.summary)")
        }

        return lines.joined(separator: "\n")
    }

    private func parseScheduleTasks(from text: String) throws -> [GeminiScheduleTask] {
        let plan = try parseSchedulePlan(from: text)
        return plan.tasks
    }

    private func parseSchedulePlan(from text: String) throws -> GeminiCareSchedulePlan {
        let candidates = [
            text,
            extractJSONBlock(from: text),
            extractJSONObject(from: text)
        ].compactMap { $0 }

        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(GeminiScheduleResponse.self, from: data) {
                let tasks = decoded.tasks
                    .map { GeminiScheduleTask(title: $0.title, notes: $0.notes, dayOffset: max(0, $0.dayOffset)) }
                    .prefix(8)
                if !tasks.isEmpty {
                    return GeminiCareSchedulePlan(
                        tasks: Array(tasks),
                        explanation: decoded.explanation?.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
            }
        }

        throw GeminiError(message: "Unable to parse schedule JSON from Gemini response.")
    }

    private func extractJSONBlock(from text: String) -> String? {
        guard let blockStart = text.range(of: "```json") ?? text.range(of: "```") else { return nil }
        let afterStart = text[blockStart.upperBound...]
        guard let blockEnd = afterStart.range(of: "```") else { return nil }
        return String(afterStart[..<blockEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") else { return nil }
        return String(text[first...last])
    }
}

struct GeminiRequest: Codable {
    let contents: [GeminiContent]

    enum CodingKeys: String, CodingKey {
        case contents
    }
}

struct GeminiContent: Codable {
    let role: String
    let parts: [GeminiPart]
}

struct GeminiPart: Codable {
    let text: String
}

struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]
}

struct GeminiCandidate: Codable {
    let content: GeminiContent
}

struct GeminiScheduleTask: Codable, Hashable {
    let title: String
    let notes: String
    let dayOffset: Int
}

struct GeminiScheduleResponse: Codable {
    let explanation: String?
    let tasks: [GeminiScheduleTask]
}

struct GeminiCareSchedulePlan: Codable {
    let tasks: [GeminiScheduleTask]
    let explanation: String?
}
