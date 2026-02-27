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
        You are a plant care specialist creating a HIGHLY PERSONALIZED care plan for a mobile app.
        
        CRITICAL: Each plant species requires DIFFERENT care. Analyze the specific needs of this plant type and create a plan that reflects its unique requirements.
        
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

        PLANT INFORMATION:
        - Plant name: \(plantName)
        - Plant type/species: \(plantType)
        - Environment: \(location)

        PERSONALIZATION RULES:
        
        1. PLANT-SPECIFIC REQUIREMENTS:
           - Research the EXACT care needs for "\(plantType)". Different plants have vastly different needs:
             * Succulents/cacti: infrequent watering (every 2-3 weeks), bright light, well-draining soil
             * Tropical plants (Monstera, Pothos): frequent watering (every 5-7 days), humidity, indirect light
             * Ferns: constant moisture, high humidity, low-medium light
             * Snake plants/ZZ plants: drought-tolerant, infrequent watering (every 2-4 weeks)
           - Tailor watering frequency, fertilizing schedule, and care tasks to THIS SPECIFIC PLANT TYPE.
        
        2. TEMPERATURE & CLIMATE ADAPTATION:
           - Parse the temperature from the environment info
           - Higher temperatures = more frequent watering (faster evaporation)
           - Lower temperatures = less frequent watering (slower growth)
           - Adjust care frequency based on temperature
        
        3. CARE GOAL INTENSITY:
           - Parse the "Goal" from environment info:
             * "Relaxed": 3-4 tasks, essentials only (watering, major issues), longer intervals
             * "Balanced": 5-6 tasks, regular care (watering, fertilizing, rotation, pruning)
             * "Attentive": 7-8 tasks, detailed care (all of above + humidity checks, pest inspections, leaf cleaning)
        
        4. LOCATION-BASED CARE:
           - Consider the city/region's climate and current season
           - Mention specific seasonal considerations in the explanation
        
        5. TASK VARIETY & TIMING:
           - Include at least ONE task with dayOffset = 0 (today)
           - Vary dayOffsets to spread tasks throughout the month (0, 3, 7, 14, 21, 28, etc.)
           - Include diverse task types based on plant needs:
             * Watering (frequency varies by plant type)
             * Fertilizing (timing varies by plant type)
             * Pruning/trimming (if needed for this species)
             * Rotating (for even light exposure)
             * Pest inspection (especially for pest-prone species)
             * Humidity check (for tropical plants)
             * Leaf cleaning (for large-leaf plants)
             * Soil check (for plants sensitive to overwatering)
        
        6. NOTES QUALITY:
           - Each task's "notes" should explain WHY this task matters for THIS SPECIFIC PLANT
           - Reference the plant's name and botanical characteristics
           - Be specific, not generic
        
        7. EXPLANATION:
           - Mention the city/region and current season's impact on care
           - State the specific watering and fertilizing frequency for THIS PLANT TYPE
           - Reference the care goal (Relaxed/Balanced/Attentive)
           - Sound warm and conversational (2-3 sentences)
        
        EXAMPLE OF GOOD PERSONALIZATION:
        - For a Monstera in San Francisco with Balanced care goal and 18-24C temp:
          * Watering every 7 days (tropical plant, moderate temp)
          * Fertilizing every 28 days during growing season
          * Weekly leaf cleaning (large leaves collect dust)
          * Rotation every 14 days (for even growth)
        
        - For a Succulent in Phoenix with Relaxed care goal and 24-30C temp:
          * Watering every 14-21 days (drought-tolerant, high temp increases frequency slightly)
          * Fertilizing every 60 days (slow grower)
          * Occasional soil check (prevent overwatering)
        
        Generate a plan that someone would IMMEDIATELY recognize as tailored to their specific plant, not a generic template.
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

    /// Free-form Q&A: answers plant questions using plant context and conversation history
    func answerPlantQuestion(question: String, plantContext: String, recentConversation: String) async throws -> String {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String,
              !apiKey.isEmpty, !apiKey.hasPrefix("<#") else {
            throw GeminiError(message: "Missing GEMINI_API_KEY. Set it in Secrets.xcconfig.")
        }

        var prompt = """
        You are PlantPal, a friendly and knowledgeable plant care advisor.

        RULES:
        - Answer the user's question with specific, actionable advice.
        - If plant context is provided, base your answer on the specific plant's needs, environment, and current care schedule.
        - If the user asks a general question and you know which plants they own, tailor your answer to their specific plants.
        - If you believe the care plan should be adjusted:
          * State CLEARLY what change you recommend (e.g., "reduce watering from every 5 days to every 7 days").
          * Explain whether this is a short-term fix (with duration, e.g., "2-3 weeks") or a permanent change, and why.
          * Tell the user: You can use "Modify current care plan" to apply this change.
        - Do NOT make any changes yourself. Only provide advice and suggestions.
        - Be warm and conversational. Reference plant species with botanical reasoning.
        - Keep your response concise (3-6 sentences). No markdown.
        """

        if !plantContext.isEmpty {
            prompt += "\n\nPlant context:\n\(plantContext)"
        }

        prompt += "\n\nUser's question: \(question)"

        if !recentConversation.isEmpty {
            prompt += "\n\nRecent conversation:\n\(recentConversation)"
        }

        print("[PlantPal] Question prompt length: \(prompt.count) chars")

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

        if let http = response as? HTTPURLResponse {
            print("[PlantPal] Question API status: \(http.statusCode)")
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[PlantPal] Question API error body: \(body)")
                throw GeminiError(message: "Gemini API error: HTTP \(http.statusCode)")
            }
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates.first?.content.parts.first?.text else {
            let raw = String(data: data, encoding: .utf8) ?? "nil"
            print("[PlantPal] No candidates in response: \(raw)")
            throw GeminiError(message: "No response text from Gemini")
        }
        return text
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
