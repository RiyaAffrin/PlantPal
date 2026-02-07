import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var profiles: [PlantProfile]
    @Query(sort: \ChatMessage.createdAt, order: .forward) private var messages: [ChatMessage]
    @Query(sort: \ConversationSummary.updatedAt, order: .reverse) private var summaries: [ConversationSummary]
    @Query(sort: \PlantMemory.updatedAt, order: .reverse) private var memories: [PlantMemory]

    @State private var inputText = ""
    @State private var setupStep: SetupStep = .askPlantName
    @State private var isSending = false
    @State private var errorMessage: String?

    private var activeProfile: PlantProfile? { profiles.first }
    private var activeSummary: ConversationSummary? {
        guard let plantName = activeProfile?.name else { return summaries.first }
        return summaries.first(where: { $0.plantName == plantName })
    }

    private var activeMemory: PlantMemory? {
        guard let plantName = activeProfile?.name else { return memories.first }
        return memories.first(where: { $0.plantName == plantName })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if let memory = activeMemory {
                                StructuredMemoryCard(memory: memory)
                                    .id("memory")
                            }

                            if let summary = activeSummary {
                                SummaryCard(summary: summary.summary)
                                    .id("summary")
                            }

                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if messages.isEmpty {
                                WelcomeCard()
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    TextField("Message PlantPal", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    Button("Send") {
                        handleSend()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle(activeProfile?.personaName ?? "PlantPal")
            .toolbar {
                if activeProfile != nil {
                    Button("New Plant") {
                        resetPlant()
                    }
                }
            }
            .onAppear {
                refreshSetupStep()
                seedIfNeeded()
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func seedIfNeeded() {
        if messages.isEmpty {
            addAgentMessage("Hi, I am PlantPal. What plant are you caring for?")
        }
    }

    private func refreshSetupStep() {
        if activeProfile == nil {
            setupStep = .askPlantName
        } else {
            setupStep = .complete
        }
    }

    private func handleSend() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""

        let userMessage = addUserMessage(trimmed)

        if activeProfile == nil {
            handleSetupResponse(trimmed)
        } else {
            isSending = true
            updateStructuredMemory(from: trimmed)
            Task {
                do {
                    let history = (messages + [userMessage]).suffix(20)
                    let reply = try await GeminiService().generateReply(
                        history: Array(history),
                        memory: activeMemory,
                        summary: activeSummary
                    )
                    addAgentMessage(reply)
                    updateSummary(with: trimmed)
                } catch {
                    errorMessage = error.localizedDescription
                }
                isSending = false
            }
        }
    }

    private func handleSetupResponse(_ text: String) {
        switch setupStep {
        case .askPlantName:
            addAgentMessage("Great. What type of plant is \(text)?")
            setupStep = .askPlantType(name: text)
        case .askPlantType(let name):
            addAgentMessage("Where is \(name) placed? (e.g., bright window)")
            setupStep = .askLocation(name: name, type: text)
        case .askLocation(let name, let type):
            let personaName = name
            let profile = PlantProfile(name: name, type: type, location: text, personaName: personaName)
            modelContext.insert(profile)
            addAgentMessage("Hi, I am \(personaName), your \(type). Ask me about care anytime.")
            setupStep = .complete
            updateSummary(with: "Plant: \(name) (\(type)) at \(text).")
            upsertMemory { memory in
                memory.lightPreference = text
            }
        case .complete:
            break
        }
    }

    private func updateSummary(with newLine: String) {
        guard let plantName = activeProfile?.name else { return }
        if let summary = activeSummary {
            summary.summary = summary.summary + "\n" + newLine
            summary.updatedAt = Date()
        } else {
            let summary = ConversationSummary(summary: newLine, plantName: plantName)
            modelContext.insert(summary)
        }
    }

    private func updateStructuredMemory(from text: String) {
        let lower = text.lowercased()
        if lower.contains("water") {
            let frequency = extractFrequencyDays(from: lower)
            if let frequency {
                upsertMemory { memory in
                    memory.wateringFrequencyDays = frequency
                }
            }
        }
        if lower.contains("light") || lower.contains("sun") {
            upsertMemory { memory in
                memory.lightPreference = text
            }
        }
        if lower.contains("adjust") || lower.contains("travel") || lower.contains("vacation") {
            upsertMemory { memory in
                memory.latestAdjustmentReason = text
            }
        }
    }

    private func upsertMemory(_ update: (PlantMemory) -> Void) {
        guard let plantName = activeProfile?.name else { return }
        let memory = activeMemory ?? PlantMemory(plantName: plantName)
        update(memory)
        memory.updatedAt = Date()
        if activeMemory == nil {
            modelContext.insert(memory)
        }
    }

    private func extractFrequencyDays(from text: String) -> Int? {
        if text.contains("daily") || text.contains("every day") { return 1 }
        if text.contains("weekly") { return 7 }
        if text.contains("biweekly") { return 14 }

        let parts = text.split { !$0.isNumber }
        if let first = parts.first, let value = Int(first) {
            return value
        }
        return nil
    }

    private func addUserMessage(_ text: String) -> ChatMessage {
        let plantName = activeProfile?.name ?? "PlantPal"
        let message = ChatMessage(role: "user", content: text, plantName: plantName)
        modelContext.insert(message)
        return message
    }

    private func addAgentMessage(_ text: String) {
        let plantName = activeProfile?.name ?? "PlantPal"
        let message = ChatMessage(role: "assistant", content: text, plantName: plantName)
        modelContext.insert(message)
    }

    private func resetPlant() {
        if let profile = activeProfile {
            modelContext.delete(profile)
        }
        messages.forEach { modelContext.delete($0) }
        summaries.forEach { modelContext.delete($0) }
        memories.forEach { modelContext.delete($0) }
        addAgentMessage("Hi, I am PlantPal. What plant are you caring for?")
        setupStep = .askPlantName
    }
}

private enum SetupStep: Equatable {
    case askPlantName
    case askPlantType(name: String)
    case askLocation(name: String, type: String)
    case complete
}

struct WelcomeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PlantPal Chat")
                .font(.headline)
            Text("Start by telling PlantPal what plant you are caring for. We'll build a memory from your chat history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SummaryCard: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversation Memory")
                .font(.headline)
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGreen).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct StructuredMemoryCard: View {
    let memory: PlantMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Structured Memory")
                .font(.headline)

            memoryRow("Watering frequency", value: frequencyText)
            memoryRow("Light preference", value: memory.lightPreference ?? "Not set")
            memoryRow("Latest adjustment", value: memory.latestAdjustmentReason ?? "Not set")
        }
        .padding()
        .background(Color(.systemGreen).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var frequencyText: String {
        guard let days = memory.wateringFrequencyDays else { return "Not set" }
        return "Every \(days) day(s)"
    }

    private func memoryRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "assistant" {
                bubble
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                bubble
            }
        }
    }

    private var bubble: some View {
        Text(message.content)
            .padding(12)
            .background(message.role == "assistant" ? Color(.systemGray6) : Color(.systemGreen).opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ChatView()
        .modelContainer(for: [
            PlantProfile.self,
            ChatMessage.self,
            ConversationSummary.self,
            PlantMemory.self
        ], inMemory: true)
}
