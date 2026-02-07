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
