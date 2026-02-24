import SwiftUI
import SwiftData

struct ChatView: View {
    var onStartChat: () -> Void = {}
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var profiles: [PlantProfile]
    @Query(sort: \ChatMessage.createdAt, order: .forward) private var messages: [ChatMessage]
    @Query(sort: \ConversationSummary.updatedAt, order: .reverse) private var summaries: [ConversationSummary]
    @Query(sort: \PlantMemory.updatedAt, order: .reverse) private var memories: [PlantMemory]
    @Query(sort: \CareTask.createdAt, order: .forward) private var allTasks: [CareTask]

    @State private var inputText = ""
    @State private var setupStep: SetupStep = .askPlantName
    @State private var selectedPlantName = "PlantPal"
    @State private var isInConversation = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var threadToDelete: ChatThread?

    private var availablePlantNames: [String] {
        let profileNames = profiles.map(\.name)
        let messageNames = messages.map(\.plantName).filter { $0 != "PlantPal" }
        let merged = Set(profileNames + messageNames)
        return merged.sorted()
    }

    private var activeProfile: PlantProfile? {
        profiles.first(where: { $0.name == selectedPlantName })
    }

    private var visibleMessages: [ChatMessage] {
        messages.filter { $0.plantName == selectedPlantName || ($0.plantName == "PlantPal" && selectedPlantName == "PlantPal") }
    }

    private var activeSummary: ConversationSummary? {
        summaries.first(where: { $0.plantName == selectedPlantName })
    }

    private var activeMemory: PlantMemory? {
        memories.first(where: { $0.plantName == selectedPlantName })
    }

    private var threads: [ChatThread] {
        let plantsFromMessages = Set(messages.map(\.plantName))
        let plantsFromProfiles = Set(profiles.map(\.name))
        let allPlants = plantsFromMessages.union(plantsFromProfiles)

        return allPlants.map { plantName in
            let plantMessages = messages.filter { $0.plantName == plantName }
            return ChatThread(
                plantName: plantName,
                lastMessage: plantMessages.last?.content ?? "No messages yet",
                lastUpdatedAt: plantMessages.last?.createdAt ?? Date.distantPast
            )
        }
        .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isInConversation {
                    conversationView
                } else {
                    historyListView
                }
            }
            .navigationTitle("History")
            .toolbar { chatToolbar }
            .onAppear {
                if !availablePlantNames.contains(selectedPlantName) {
                    selectedPlantName = availablePlantNames.first ?? "PlantPal"
                }
                refreshSetupStep()
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
            .alert("Delete Chat", isPresented: Binding(
                get: { threadToDelete != nil },
                set: { if !$0 { threadToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { threadToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let thread = threadToDelete {
                        deleteAllDataForPlant(thread.plantName)
                        if isInConversation && selectedPlantName == thread.plantName {
                            isInConversation = false
                            selectedPlantName = availablePlantNames.first ?? "PlantPal"
                        }
                        threadToDelete = nil
                    }
                }
            } message: {
                if let thread = threadToDelete {
                    Text("Delete all chat history for \(thread.plantName)? This cannot be undone.")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var chatToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            if isInConversation {
                Button("Back") {
                    isInConversation = false
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if isInConversation && activeProfile != nil {
                Button("New Plant") {
                    resetPlant()
                }
            }
        }
    }

    private var historyListView: some View {
        VStack(spacing: 0) {
            List {
                if threads.isEmpty {
                    Text("No chat history yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(threads) { thread in
                        Button {
                            openConversation(for: thread.plantName)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chat about \(thread.plantName) plant")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(thread.lastMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                threadToDelete = thread
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Button("Start a chat") {
                onStartChat()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    private var conversationView: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Chat about \(selectedPlantName) plant")
                            .font(.headline)
                            .padding(.top, 4)

                        if let memory = activeMemory {
                            StructuredMemoryCard(memory: memory)
                                .id("memory")
                        }

                        if let summary = activeSummary {
                            SummaryCard(summary: summary.summary)
                                .id("summary")
                        }

                        ForEach(visibleMessages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        if visibleMessages.isEmpty {
                            WelcomeCard()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                }
                .onChange(of: visibleMessages.count) { _, _ in
                    if let last = visibleMessages.last {
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
    }

    private func seedIfNeeded() {
        if visibleMessages.isEmpty {
            if let profile = activeProfile {
                addAgentMessage("Hi, I'm PlantPal. How can I help with your \(profile.name) today?")
            } else {
                addAgentMessage("Hi, I am PlantPal. What plant are you caring for?")
            }
        }
    }

    private func openConversation(for plantName: String) {
        selectedPlantName = plantName
        refreshSetupStep()
        isInConversation = true
        seedIfNeeded()
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

        if activeProfile == nil {
            _ = addUserMessage(trimmed)
            isSending = true
            Task {
                await handleSetupResponse(trimmed)
                isSending = false
            }
        } else {
            let userMessage = addUserMessage(trimmed)
            isSending = true
            updateStructuredMemory(from: trimmed)
            Task {
                do {
                    let history = (visibleMessages + [userMessage]).suffix(20)
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

    private func handleSetupResponse(_ text: String) async {
        switch setupStep {
        case .askPlantName:
            selectedPlantName = text
            addAgentMessage("Great. What type of plant is \(text)?")
            setupStep = .askPlantType(name: text)
        case .askPlantType(let name):
            addAgentMessage("Where is \(name) placed? (e.g., bright window)")
            setupStep = .askLocation(name: name, type: text)
        case .askLocation(let name, let type):
            let personaName = name
            let profile = PlantProfile(name: name, type: type, location: text, personaName: personaName)
            modelContext.insert(profile)
            selectedPlantName = name
            addAgentMessage("Hi, I am \(personaName), your \(type). Ask me about care anytime.")
            let frequency = wateringFrequencyDays(for: type)
            let tasks = await generatedTasksFromGemini(
                name: name,
                type: type,
                location: text,
                frequencyDays: frequency
            )
            replaceTasks(for: name, with: tasks)
            setupStep = .complete
            updateSummary(with: "Plant: \(name) (\(type)) at \(text).")
            upsertMemory { memory in
                memory.wateringFrequencyDays = frequency
                memory.lightPreference = text
            }
        case .complete:
            break
        }
    }

    private func generatedTasksFromGemini(name: String, type: String, location: String, frequencyDays: Int) async -> [CareTask] {
        do {
            let aiTasks = try await GeminiService().generateCareSchedule(
                plantName: name,
                plantType: type,
                location: location
            )
            return aiTasks.map { task in
                let dueDate = Calendar.current.date(byAdding: .day, value: task.dayOffset, to: Date()) ?? Date()
                return CareTask(
                    plantName: name,
                    title: task.title,
                    notes: task.notes,
                    dueDate: dueDate
                )
            }
        } catch {
            return generatedTasks(name: name, type: type, location: location, frequencyDays: frequencyDays)
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

    private func generatedTasks(name: String, type: String, location: String, frequencyDays: Int) -> [CareTask] {
        let entries: [(title: String, notes: String, dayOffset: Int)] = [
            ("Water \(name)", "Water thoroughly if top soil feels dry. Location: \(location).", 0),
            ("Check soil moisture for \(name)", "Touch the top 2 inches of soil before watering.", max(1, frequencyDays / 2)),
            ("Inspect leaves of \(name)", "Look for yellowing, curling, or pests.", 2),
            ("Rotate \(name)", "Rotate the pot to even out light exposure.", 7),
            ("Water \(name)", "Regular watering cycle for \(type).", frequencyDays)
        ]

        return entries.map { entry in
            let dueDate = Calendar.current.date(byAdding: .day, value: entry.dayOffset, to: Date()) ?? Date()
            return CareTask(plantName: name, title: entry.title, notes: entry.notes, dueDate: dueDate)
        }
    }

    private func replaceTasks(for plantName: String, with tasks: [CareTask]) {
        let existing = allTasks.filter { $0.plantName == plantName }
        existing.forEach { modelContext.delete($0) }
        tasks.forEach { modelContext.insert($0) }
    }

    private func wateringFrequencyDays(for plantType: String) -> Int {
        let lower = plantType.lowercased()
        if lower.contains("cactus") || lower.contains("succulent") {
            return 10
        }
        if lower.contains("fern") || lower.contains("calathea") {
            return 3
        }
        return 5
    }

    private func addUserMessage(_ text: String) -> ChatMessage {
        let plantName = selectedPlantName
        let message = ChatMessage(role: "user", content: text, plantName: plantName)
        modelContext.insert(message)
        return message
    }

    private func addAgentMessage(_ text: String) {
        let plantName = selectedPlantName
        let message = ChatMessage(role: "assistant", content: text, plantName: plantName)
        modelContext.insert(message)
    }

    private func deleteAllDataForPlant(_ plantName: String) {
        if let profile = profiles.first(where: { $0.name == plantName }) {
            modelContext.delete(profile)
        }
        messages.filter { $0.plantName == plantName }.forEach { modelContext.delete($0) }
        summaries.filter { $0.plantName == plantName }.forEach { modelContext.delete($0) }
        memories.filter { $0.plantName == plantName }.forEach { modelContext.delete($0) }
        allTasks.filter { $0.plantName == plantName }.forEach { modelContext.delete($0) }
    }

    private func resetPlant() {
        let targetPlant = selectedPlantName
        deleteAllDataForPlant(targetPlant)
        selectedPlantName = "PlantPal"
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

private struct ChatThread: Identifiable {
    var id: String { plantName }
    let plantName: String
    let lastMessage: String
    let lastUpdatedAt: Date
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
            memoryRow("Light preference", value: lightPreferenceText)
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

    private var lightPreferenceText: String {
        guard let raw = memory.lightPreference, !raw.isEmpty else { return "Not set" }
        let firstSentence = raw.split(separator: ".").first.map(String.init) ?? raw
        let trimmed = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? raw : trimmed
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
    ChatView(onStartChat: {})
        .modelContainer(for: [
            PlantProfile.self,
            ChatMessage.self,
            ConversationSummary.self,
            PlantMemory.self,
            CareTask.self
        ], inMemory: true)
}
