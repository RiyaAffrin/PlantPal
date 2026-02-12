import SwiftUI
import SwiftData

struct Scenario1FlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var profiles: [PlantProfile]
    @Query(sort: \CareTask.createdAt, order: .forward) private var allTasks: [CareTask]
    @Query(sort: \ConversationSummary.updatedAt, order: .reverse) private var summaries: [ConversationSummary]
    @Query(sort: \PlantMemory.updatedAt, order: .reverse) private var memories: [PlantMemory]

    @State private var agentName = "PlantPal"
    @State private var chatMessages: [SetupMessage] = [
        SetupMessage(role: .assistant, text: "Hi, I'm PlantPal."),
        SetupMessage(role: .assistant, text: "How can I help you today?")
    ]
    @State private var inputText = ""
    @State private var setupStep: SetupStep = .awaitingIntent
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(chatMessages) { message in
                            HStack {
                                if message.role == .assistant {
                                    AgentBubble(text: message.text)
                                    Spacer(minLength: 40)
                                } else {
                                    Spacer(minLength: 40)
                                    chatBubble(message.text, isAssistant: false)
                                }
                            }
                        }

                        if setupStep == .awaitingIntent, shouldShowIntentOptions {
                            OptionCard(options: SetupIntent.allCases.map(\.rawValue)) { selected in
                                handleIntentSelection(selected)
                            }
                            .frame(maxWidth: 340)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider()

                HStack(spacing: 12) {
                    TextField("Type your answer", text: $inputText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)

                    Button("Send") { handleSend() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSending || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle(agentName)
            .navigationBarTitleDisplayMode(.inline)
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

    private func handleSend() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""

        isSending = true

        switch setupStep {
        case .awaitingIntent:
            handleIntentSelection(trimmed)
            isSending = false
        case .collectPlantName:
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: "PlantPal")
            addAssistantMessage("Got it. What type/species is \(trimmed)?", plantName: trimmed)
            setupStep = .collectPlantType(name: trimmed)
            isSending = false
        case .collectPlantType(let name):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: name)
            addAssistantMessage("Where do you keep \(name)? (e.g. bedroom window, balcony)", plantName: name)
            setupStep = .collectLocation(name: name, type: trimmed)
            isSending = false
        case .collectLocation(let name, let type):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: name)
            addAssistantMessage("Which city are you in?", plantName: name)
            setupStep = .collectCity(name: name, type: type, placement: trimmed)
            isSending = false
        case .collectCity(let name, let type, let placement):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: name)
            addAssistantMessage("What is the usual temperature around the plant? (e.g. 18-24C / 65-75F)", plantName: name)
            setupStep = .collectTemperature(name: name, type: type, placement: placement, city: trimmed)
            isSending = false
        case .collectTemperature(let name, let type, let placement, let city):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: name)
            addAssistantMessage("Last one: do you want a low-maintenance plan, balanced plan, or growth-focused plan?", plantName: name)
            setupStep = .collectCareGoal(
                name: name,
                type: type,
                placement: placement,
                city: city,
                temperature: trimmed
            )
            isSending = false
        case .collectCareGoal(let name, let type, let placement, let city, let temperature):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: name)
            Task {
                await createPlantAndSchedule(
                    name: name,
                    type: type,
                    location: placement,
                    city: city,
                    temperature: temperature,
                    goal: trimmed
                )
                setupStep = .awaitingIntent
                isSending = false
            }
        }
    }

    private func handleIntentSelection(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        chatMessages.append(SetupMessage(role: .user, text: text))
        persistMessage(role: "user", content: text, plantName: "PlantPal")

        let lower = text.lowercased()
        if lower.contains("setup") || lower.contains("set up") {
            addAssistantMessage("Sure. What plant are you caring for?", plantName: "PlantPal")
            setupStep = .collectPlantName
            return
        }
        if lower.contains("question") {
            addAssistantMessage("Sure. Which plant is this about?", plantName: "PlantPal")
            setupStep = .collectPlantName
            return
        }
        if lower.contains("modify") {
            addAssistantMessage("Okay. Which plant's plan should I modify?", plantName: "PlantPal")
            setupStep = .collectPlantName
            return
        }

        addAssistantMessage("Please choose one option above.", plantName: "PlantPal")
        setupStep = .awaitingIntent
    }

    private func createPlantAndSchedule(
        name: String,
        type: String,
        location: String,
        city: String,
        temperature: String,
        goal: String
    ) async {
        let existingProfile = profiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        let locationWithCity = "\(location), \(city)"
        let careContext = "\(locationWithCity). Temp: \(temperature). Goal: \(goal)."
        let profile = existingProfile ?? PlantProfile(name: name, type: type, location: locationWithCity, personaName: name)
        if existingProfile == nil {
            modelContext.insert(profile)
        } else {
            profile.type = type
            profile.location = locationWithCity
        }

        let frequency = wateringFrequencyDays(for: type)
        upsertSummary(
            for: name,
            line: "Plant profile: \(name) (\(type)); location: \(location); city: \(city); temp: \(temperature); goal: \(goal)."
        )
        upsertMemory(for: name, frequencyDays: frequency, lightPreference: careContext)
        let scheduleResult = await generatedTasksFromGemini(
            name: name,
            type: type,
            location: careContext,
            city: city,
            frequencyDays: frequency
        )
        replaceTasks(for: name, with: scheduleResult.tasks)

        addAssistantMessage("Done. Schedule created for \(name).", plantName: name)
        if let explanation = scheduleResult.explanation, !explanation.isEmpty {
            addAssistantMessage(explanation, plantName: name)
        }
        addAssistantMessage("Check it in Today.", plantName: name)
    }

    private func generatedTasksFromGemini(
        name: String,
        type: String,
        location: String,
        city: String,
        frequencyDays: Int
    ) async -> (tasks: [CareTask], explanation: String?) {
        do {
            let plan = try await GeminiService().generateCareSchedulePlan(
                plantName: name,
                plantType: type,
                location: location
            )
            let tasks = plan.tasks.map { task in
                let dueDate = Calendar.current.date(byAdding: .day, value: task.dayOffset, to: Date()) ?? Date()
                return CareTask(
                    plantName: name,
                    title: task.title,
                    notes: task.notes,
                    dueDate: dueDate
                )
            }
            let explanation = plan.explanation ?? buildFallbackExplanation(
                plantName: name,
                city: city,
                tasks: tasks
            )
            return (tasks: tasks, explanation: explanation)
        } catch {
            let fallbackTasks = generatedTasks(name: name, type: type, location: location, frequencyDays: frequencyDays)
            let explanation = buildFallbackExplanation(plantName: name, city: city, tasks: fallbackTasks)
            return (tasks: fallbackTasks, explanation: explanation)
        }
    }

    private func generatedTasks(name: String, type: String, location: String, frequencyDays: Int) -> [CareTask] {
        let entries: [(title: String, notes: String, dayOffset: Int)] = [
            ("Water \(name)", "Water thoroughly if top soil feels dry. Location: \(location).", 0),
            ("Check soil moisture for \(name)", "Touch the top 2 inches of soil before watering.", max(1, frequencyDays / 2)),
            ("Inspect leaves of \(name)", "Look for yellowing, curling, or pests.", 2),
            ("Rotate \(name)", "Rotate the pot to even out light exposure.", 7),
            ("Water \(name)", "Regular watering cycle for \(type).", frequencyDays),
            ("Fertilize \(name)", "Use diluted balanced fertilizer during active growth.", max(14, frequencyDays * 3))
        ]

        return entries.map { entry in
            let dueDate = Calendar.current.date(byAdding: .day, value: entry.dayOffset, to: Date()) ?? Date()
            return CareTask(plantName: name, title: entry.title, notes: entry.notes, dueDate: dueDate)
        }
    }

    private func buildFallbackExplanation(plantName: String, city: String, tasks: [CareTask]) -> String {
        let season = currentSeason()
        let wateringInterval = inferredInterval(for: "water", in: tasks) ?? 3
        let fertilizeInterval = inferredInterval(for: "fertilize", in: tasks) ?? 14
        return "In \(city), it's \(season) right now, so temperature can change how fast the soil dries. Start with watering \(plantName) every \(wateringInterval) days and fertilizing every \(fertilizeInterval) days, then we can fine-tune based on how it responds."
    }

    private func currentSeason() -> String {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 12, 1, 2:
            return "winter"
        case 3, 4, 5:
            return "spring"
        case 6, 7, 8:
            return "summer"
        default:
            return "fall"
        }
    }

    private func inferredInterval(for keyword: String, in tasks: [CareTask]) -> Int? {
        let offsets = tasks
            .filter { $0.title.lowercased().contains(keyword) }
            .map { max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: $0.dueDate)).day ?? 0) }
            .sorted()
        guard offsets.count >= 2 else { return nil }
        let interval = offsets[1] - offsets[0]
        return interval > 0 ? interval : nil
    }

    private func replaceTasks(for plantName: String, with tasks: [CareTask]) {
        let existing = allTasks.filter { $0.plantName == plantName }
        existing.forEach { modelContext.delete($0) }
        tasks.forEach { modelContext.insert($0) }
    }

    private func upsertSummary(for plantName: String, line: String) {
        if let summary = summaries.first(where: { $0.plantName == plantName }) {
            summary.summary = line
            summary.updatedAt = Date()
        } else {
            modelContext.insert(ConversationSummary(summary: line, plantName: plantName))
        }
    }

    private func upsertMemory(for plantName: String, frequencyDays: Int, lightPreference: String) {
        if let memory = memories.first(where: { $0.plantName == plantName }) {
            memory.wateringFrequencyDays = frequencyDays
            memory.lightPreference = lightPreference
            memory.updatedAt = Date()
        } else {
            modelContext.insert(
                PlantMemory(
                    plantName: plantName,
                    wateringFrequencyDays: frequencyDays,
                    lightPreference: lightPreference
                )
            )
        }
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

    private func addAssistantMessage(_ text: String, plantName: String) {
        chatMessages.append(SetupMessage(role: .assistant, text: text))
        persistMessage(role: "assistant", content: text, plantName: plantName)
    }

    private var shouldShowIntentOptions: Bool {
        chatMessages.last?.role == .assistant && chatMessages.last?.text == "How can I help you today?"
    }

    private func persistMessage(role: String, content: String, plantName: String) {
        let message = ChatMessage(role: role, content: content, plantName: plantName)
        modelContext.insert(message)
    }

    private func chatBubble(_ text: String, isAssistant: Bool) -> some View {
        Text(text)
            .padding(12)
            .background(isAssistant ? Color(.systemGray6) : Color(red: 0.74, green: 0.82, blue: 0.48))
            .foregroundColor(isAssistant ? .primary : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .frame(maxWidth: 260, alignment: isAssistant ? .leading : .trailing)
    }
}

private struct SetupMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let text: String
}

private enum MessageRole {
    case user
    case assistant
}

private enum SetupStep: Equatable {
    case awaitingIntent
    case collectPlantName
    case collectPlantType(name: String)
    case collectLocation(name: String, type: String)
    case collectCity(name: String, type: String, placement: String)
    case collectTemperature(name: String, type: String, placement: String, city: String)
    case collectCareGoal(name: String, type: String, placement: String, city: String, temperature: String)
}

private enum SetupIntent: String, CaseIterable {
    case setupNewPlant = "Set up a new plant"
    case questionNewPlant = "Question about a new plant"
    case modifyCurrentPlan = "Modify current care plan"
}

private struct AgentBubble: View {
    let text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(.systemGray5), lineWidth: 1))

            Text(text)
                .padding(12)
                .background(Color(.systemGray6))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 260, alignment: .leading)
        }
    }
}

private struct OptionCard: View {
    let options: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                Button {
                    onSelect(option)
                } label: {
                    HStack {
                        Text(option)
                            .font(.body)
                            .foregroundStyle(.blue)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                if index < options.count - 1 {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    Scenario1FlowView()
        .modelContainer(for: [
            PlantProfile.self,
            ChatMessage.self,
            ConversationSummary.self,
            PlantMemory.self,
            CareTask.self
        ], inMemory: true)
}
