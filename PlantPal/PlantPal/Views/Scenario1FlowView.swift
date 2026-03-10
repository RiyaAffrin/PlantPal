import SwiftUI
import SwiftData

struct Scenario1FlowView: View {
    @Binding var selectedTab: Int
    // incremented by ContentView when History's "Start a chat" is tapped
    var resetTrigger: Binding<Int>? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var profiles: [PlantProfile]
    @Query(sort: \ConversationSummary.updatedAt, order: .reverse) private var summaries: [ConversationSummary]
    @Query(sort: \PlantMemory.updatedAt, order: .reverse) private var memories: [PlantMemory]
    @Query(sort: \CareTask.dueDate, order: .forward) private var allTasks: [CareTask]
    @Query(sort: \ChatMessage.createdAt, order: .forward) private var messages: [ChatMessage]

    @State private var agentName = "PlantPal"
    @State private var chatMessages: [SetupMessage] = [
        SetupMessage(role: .assistant, text: "Hi, I'm PlantPal."),
        SetupMessage(role: .assistant, text: "How can I help you today?")
    ]
    @State private var inputText = ""
    @State private var setupStep: SetupStep = .awaitingIntent
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var pendingPlan: PendingCarePlan?
    /// After the user selects the plan type, three paragraphs plus this option are displayed;
    //  after the user clicks "Review Plan," 
    // the value is assigned to the pending Plan and the user is redirected.
    @State private var planReadyForReview: PendingCarePlan?
    @State private var pendingAdjustmentDraft: PendingPlanAdjustment?
    @State private var adjustmentPreview: PendingPlanAdjustment?
    @State private var adjustmentIntake: AdjustmentIntake?

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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 36)
                        }

                        if let options = optionsForCurrentStep {
                            OptionCard(options: options) { selected in
                                inputText = selected
                                handleSend()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 36)
                        }

                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider()

                if let plan = planReadyForReview {
                    Button("Review Plan") {
                        pendingPlan = plan
                        planReadyForReview = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.horizontal)
                    .padding(.top, 12)
                } else if pendingAdjustmentDraft != nil {
                    Button("Preview Changes") {
                        adjustmentPreview = pendingAdjustmentDraft
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .padding(.horizontal)
                    .padding(.top, 12)
                }

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if chatMessages.count > 2 || setupStep != .awaitingIntent {
                        Button("New Chat") {
                            resetToInitialState()
                        }
                    }
                }
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
            .navigationDestination(item: $pendingPlan) { plan in
                ReviewPlanView(plantName: plan.plantName, draftPlan: plan, selectedTab: $selectedTab, onDismissAfterApply: { resetToInitialState() })
            }
            .navigationDestination(item: $adjustmentPreview) { plan in
                AdjustPlanPreviewView(selectedTab: $selectedTab, draft: plan)
            }
            .onChange(of: profiles.count) { oldCount, newCount in
                // reset local chat state when all data gets cleared
                if oldCount > 0 && newCount == 0 {
                    resetToInitialState()
                }
            }
            .onChange(of: resetTrigger?.wrappedValue ?? 0) { _, _ in
                // triggered when History's "Start a chat" is tapped
                resetToInitialState()
            }
        }
    }

    private func resetToInitialState() {
        chatMessages = [
            SetupMessage(role: .assistant, text: "Hi, I'm PlantPal."),
            SetupMessage(role: .assistant, text: "How can I help you today?")
        ]
        inputText = ""
        setupStep = .awaitingIntent
        pendingPlan = nil
        planReadyForReview = nil
        pendingAdjustmentDraft = nil
        adjustmentPreview = nil
        adjustmentIntake = nil
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
            // user just told us the plant name; move previous PlantPal-thread messages to this plant
            reassignMessages(from: "PlantPal", to: trimmed)
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: trimmed)
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
            addAssistantMessage("Last one: what kind of care plan do you prefer?", plantName: name)
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
        case .askingQuestion(let currentPlantName):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            let identifiedPlant = identifyPlant(from: trimmed) ?? currentPlantName
            let plantLabel = identifiedPlant ?? "PlantPal"
            persistMessage(role: "user", content: trimmed, plantName: plantLabel)

            if identifiedPlant != currentPlantName {
                setupStep = .askingQuestion(plantName: identifiedPlant)
            }

            Task {
                await answerQuestion(trimmed, identifiedPlant: identifiedPlant, plantLabel: plantLabel)
                isSending = false
            }
        case .adjustAskPlantName:
            let plantName = normalizedPlantName(from: trimmed) ?? trimmed
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: plantName)
            adjustmentIntake = AdjustmentIntake(plantName: plantName)
            addAssistantMessage("Got it. Do you need a short-term change or a long-term change?", plantName: plantName)
            if let context = adjustmentContext(for: plantName) {
                addAssistantMessage(context, plantName: plantName)
            }
            setupStep = .adjustAskChangeType(plantName: plantName)
            isSending = false
        case .adjustAskChangeType(let plantName):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: plantName)
            let lower = trimmed.lowercased()
            if lower.contains("short") {
                updateAdjustmentIntake {
                    $0.plantName = plantName
                    $0.changeType = .shortTerm
                }
                addAssistantMessage("What date range should I account for? (example: Jan 28 to Feb 3)", plantName: plantName)
                setupStep = .adjustAskDateRange(plantName: plantName)
            } else if lower.contains("long") || lower.contains("permanent") {
                updateAdjustmentIntake {
                    $0.plantName = plantName
                    $0.changeType = .longTerm
                }
                addAssistantMessage("What permanent update do you want? (example: water less often, from every 5 days to every 7 days)", plantName: plantName)
                setupStep = .adjustAskLongTermGoal(plantName: plantName)
            } else {
                addAssistantMessage("Please pick one: short-term or long-term.", plantName: plantName)
            }
            isSending = false
        case .adjustAskDateRange(let plantName):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: plantName)
            guard let range = parseDateRange(from: trimmed) else {
                addAssistantMessage("I couldn't parse that date range. Try something like Jan 28 to Feb 3.", plantName: plantName)
                isSending = false
                return
            }
            updateAdjustmentIntake {
                $0.plantName = plantName
                $0.dateRangeText = trimmed
                $0.awayStart = range.start
                $0.awayEnd = range.end
            }
            addAssistantMessage("Will anyone be able to water or check your plant while you're away?", plantName: plantName)
            setupStep = .adjustAskHelperAvailability(plantName: plantName)
            isSending = false
        case .adjustAskHelperAvailability(let plantName):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: plantName)
            let lower = trimmed.lowercased()
            if lower.contains("yes") {
                updateAdjustmentIntake { $0.helperAvailable = true }
            } else if lower.contains("no") {
                updateAdjustmentIntake { $0.helperAvailable = false }
            } else {
                addAssistantMessage("Please answer yes or no.", plantName: plantName)
                isSending = false
                return
            }
            addAssistantMessage("How should I handle the adjusted schedule?", plantName: plantName)
            setupStep = .adjustAskPlanStyle(plantName: plantName)
            isSending = false
        case .adjustAskPlanStyle(let plantName):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: plantName)
            let lower = trimmed.lowercased()
            if lower.contains("relax") {
                updateAdjustmentIntake { $0.style = .relaxed }
            } else if lower.contains("balanced") {
                updateAdjustmentIntake { $0.style = .balanced }
            } else if lower.contains("attentive") {
                updateAdjustmentIntake { $0.style = .attentive }
            } else {
                addAssistantMessage("Please choose one: Relaxed, Balanced, or Attentive.", plantName: plantName)
                isSending = false
                return
            }
            addAssistantMessage("Do you prefer watering earlier before you leave, or catching up after you return?", plantName: plantName)
            setupStep = .adjustAskTimingPreference(plantName: plantName)
            isSending = false
        case .adjustAskTimingPreference(let plantName):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: plantName)
            let lower = trimmed.lowercased()
            if lower.contains("earlier") || lower.contains("before") {
                updateAdjustmentIntake { $0.preferEarly = true }
            } else if lower.contains("catch") || lower.contains("after") {
                updateAdjustmentIntake { $0.preferEarly = false }
            } else {
                addAssistantMessage("Please choose one: earlier before leaving, or catch up after returning.", plantName: plantName)
                isSending = false
                return
            }
            Task {
                await finalizeAdjustment(for: plantName)
                isSending = false
            }
        case .adjustAskLongTermGoal(let plantName):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: plantName)
            updateAdjustmentIntake {
                $0.longTermGoal = trimmed
                $0.style = .balanced
                $0.preferEarly = false
            }
            Task {
                await finalizeAdjustment(for: plantName)
                isSending = false
            }
        case .adjustReadyForPreview:
            if trimmed.lowercased().contains("preview"), let draft = pendingAdjustmentDraft {
                adjustmentPreview = draft
            } else {
                addAssistantMessage("You can tap Preview Changes, or tell me another constraint and I can regenerate.", plantName: adjustmentIntake?.plantName ?? "PlantPal")
            }
            isSending = false
        }
    }

    private func handleIntentSelection(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        chatMessages.append(SetupMessage(role: .user, text: text))
        persistMessage(role: "user", content: text, plantName: "PlantPal")

        let lower = text.lowercased()
        if lower.contains("setup") || lower.contains("set up") {
            pendingAdjustmentDraft = nil
            adjustmentPreview = nil
            addAssistantMessage("Sure. What plant are you caring for?", plantName: "PlantPal")
            setupStep = .collectPlantName
            return
        }
        if lower.contains("question") || lower.contains("ask about") {
            pendingAdjustmentDraft = nil
            adjustmentPreview = nil
            if profiles.isEmpty {
                addAssistantMessage("What would you like to know? You can ask about general plant care.", plantName: "PlantPal")
            } else {
                let names = profiles.map(\.name).joined(separator: ", ")
                addAssistantMessage("What would you like to know? You can ask about \(names) or general plant care.", plantName: "PlantPal")
            }
            setupStep = .askingQuestion(plantName: nil)
            return
        }
        if lower.contains("modify") {
            pendingAdjustmentDraft = nil
            adjustmentPreview = nil

            if availablePlantNamesForAdjustment().isEmpty {
                addAssistantMessage("You currently have no plant care schedule to modify. Start a new chat to set up a new plant.", plantName: "PlantPal")
                setupStep = .awaitingIntent
            } else {
                addAssistantMessage("Which plant's care plan would you like to modify?", plantName: "PlantPal")
                setupStep = .adjustAskPlantName
            }
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
        let pendingTasks = scheduleResult.tasks.map {
            PendingCareTask(title: $0.title, notes: $0.notes, dueDate: $0.dueDate)
        }
        let plan = PendingCarePlan(
            plantName: name,
            tasks: pendingTasks,
            explanation: scheduleResult.explanation
        )
        planReadyForReview = plan

        addAssistantMessage("Done. I created a default plan for \(name).", plantName: name)
        if let explanation = scheduleResult.explanation, !explanation.isEmpty {
            addAssistantMessage(explanation, plantName: name)
        }
        addAssistantMessage("Please review and apply the plan first. It will appear in Care Today after you apply.", plantName: name)
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

    private var optionsForCurrentStep: [String]? {
        switch setupStep {
        case .adjustAskPlantName:
            let names = availablePlantNamesForAdjustment()
            return names.isEmpty ? nil : names
        case .adjustAskChangeType:
            return [
                "Short-term change (for a specific period)",
                "Long-term change (a permanent update)"
            ]
        case .adjustAskHelperAvailability:
            return ["Yes", "No"]
        case .collectCareGoal:
            return [
                "Relaxed — just the essentials, great if you're busy",
                "Balanced — regular watering, soil checks, and rotation",
                "Attentive — more frequent care to help your plant thrive"
            ]
        case .adjustAskPlanStyle:
            return [
                "Relaxed — spread tasks out, less pressure when you're back",
                "Balanced — resume at a normal pace",
                "Attentive — catch up quickly, tasks grouped closer together"
            ]
        case .adjustAskTimingPreference:
            return [
                "Water earlier before I leave",
                "Catch up after I return"
            ]
        default:
            return nil
        }
    }

    private func persistMessage(role: String, content: String, plantName: String) {
        let message = ChatMessage(role: role, content: content, plantName: plantName)
        modelContext.insert(message)
    }

    private func suggestedPlantForAdjustment() -> String? {
        availablePlantNamesForAdjustment().first
    }

    private func availablePlantNamesForAdjustment() -> [String] {
        var set = Set<String>()
        for profile in profiles {
            set.insert(profile.name)
        }
        for memory in memories {
            set.insert(memory.plantName)
        }
        for summary in summaries {
            set.insert(summary.plantName)
        }
        for task in allTasks {
            set.insert(task.plantName)
        }
        return Array(set).sorted()
    }

    private func reassignMessages(from oldName: String, to newName: String) {
        guard oldName.caseInsensitiveCompare(newName) != .orderedSame else { return }
        messages
            .filter { $0.plantName.caseInsensitiveCompare(oldName) == .orderedSame }
            .forEach { $0.plantName = newName }
    }

    private func normalizedPlantName(from raw: String) -> String? {
        profiles.first(where: { $0.name.caseInsensitiveCompare(raw) == .orderedSame })?.name
    }

    /// Matches user input against known plant names and types
    private func identifyPlant(from text: String) -> String? {
        let lower = text.lowercased()
        if let match = profiles.first(where: {
            lower.contains($0.name.lowercased()) || lower.contains($0.type.lowercased())
        }) {
            return match.name
        }
        if profiles.count == 1 {
            return profiles.first?.name
        }
        return nil
    }

    /// Builds context from profile, memory, summary, and current tasks for question mode
    private func buildQuestionContext(for plantName: String) -> String? {
        var parts: [String] = []

        if let profile = profiles.first(where: { $0.name.caseInsensitiveCompare(plantName) == .orderedSame }) {
            parts.append("Plant: \(profile.name), type: \(profile.type), location: \(profile.location).")
        }

        if let memory = memories.first(where: { $0.plantName.caseInsensitiveCompare(plantName) == .orderedSame }) {
            if let freq = memory.wateringFrequencyDays {
                parts.append("Watering frequency: every \(freq) days.")
            }
            if let light = memory.lightPreference {
                parts.append("Light/environment: \(light).")
            }
            if let reason = memory.latestAdjustmentReason {
                parts.append("Latest adjustment: \(reason).")
            }
        }

        if let summary = summaries.first(where: { $0.plantName.caseInsensitiveCompare(plantName) == .orderedSame }) {
            parts.append("Chat history summary: \(summary.summary)")
        }

        let plantTasks = allTasks
            .filter { $0.plantName.caseInsensitiveCompare(plantName) == .orderedSame }
            .sorted { $0.dueDate < $1.dueDate }
        if !plantTasks.isEmpty {
            let taskList = plantTasks.map { "- \($0.title): \(taskDateLabel($0.dueDate))" }.joined(separator: "\n")
            parts.append("Current care schedule:\n\(taskList)")
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n")
    }

    /// Brief summary of ALL user's plants — used when no specific plant is identified
    private func buildGeneralPlantContext() -> String {
        guard !profiles.isEmpty else { return "" }
        var parts: [String] = ["User's plants:"]
        for profile in profiles {
            var info = "- \(profile.name) (\(profile.type), \(profile.location))"
            if let memory = memories.first(where: { $0.plantName.caseInsensitiveCompare(profile.name) == .orderedSame }) {
                if let freq = memory.wateringFrequencyDays {
                    info += ", watering every \(freq) days"
                }
            }
            let taskCount = allTasks.filter { $0.plantName.caseInsensitiveCompare(profile.name) == .orderedSame }.count
            if taskCount > 0 {
                info += ", \(taskCount) scheduled tasks"
            }
            parts.append(info)
        }
        return parts.joined(separator: "\n")
    }

    /// Handles the full question-answer cycle: builds context, calls Gemini, shows response
    private func answerQuestion(_ question: String, identifiedPlant: String?, plantLabel: String) async {
        let context: String
        if let plantName = identifiedPlant {
            context = buildQuestionContext(for: plantName) ?? buildGeneralPlantContext()
        } else {
            context = buildGeneralPlantContext()
        }

        let recentMessages = chatMessages.suffix(10)
            .map { "\($0.role == .user ? "User" : "PlantPal"): \($0.text)" }
            .joined(separator: "\n")

        do {
            let answer = try await GeminiService().answerPlantQuestion(
                question: question,
                plantContext: context,
                recentConversation: recentMessages
            )
            addAssistantMessage(answer, plantName: plantLabel)
        } catch {
            print("[PlantPal] Question mode error: \(error)")
            addAssistantMessage("Sorry, I couldn't process that right now. Please try again.", plantName: plantLabel)
        }
    }

    private func adjustmentContext(for plantName: String) -> String? {
        var context: [String] = []
        if let profile = profiles.first(where: { $0.name.caseInsensitiveCompare(plantName) == .orderedSame }) {
            context.append("Saved setup: \(profile.type), kept at \(profile.location).")
        }
        if let memory = memories.first(where: { $0.plantName.caseInsensitiveCompare(plantName) == .orderedSame }),
           let freq = memory.wateringFrequencyDays {
            context.append("Recent preference: watering every \(freq) day(s).")
        }
        if let summary = summaries.first(where: { $0.plantName.caseInsensitiveCompare(plantName) == .orderedSame }) {
            let firstLine = summary.summary.split(separator: "\n").first.map(String.init) ?? summary.summary
            if !firstLine.isEmpty {
                context.append("From chat history: \(firstLine)")
            }
        }
        guard !context.isEmpty else { return nil }
        return "I'll use your saved setup + chat memory so we can skip repeated questions.\n" + context.joined(separator: " ")
    }

    private func updateAdjustmentIntake(_ update: (inout AdjustmentIntake) -> Void) {
        var intake = adjustmentIntake ?? AdjustmentIntake(plantName: suggestedPlantForAdjustment() ?? "My Plant")
        update(&intake)
        adjustmentIntake = intake
    }

    private func finalizeAdjustment(for plantName: String) async {
        guard var intake = adjustmentIntake else {
            addAssistantMessage("I couldn't collect enough information. Please try again.", plantName: plantName)
            return
        }
        intake.plantName = plantName
        adjustmentIntake = intake

        guard var draft = buildAdjustmentDraft(from: intake) else {
            addAssistantMessage("I could not find a current schedule yet. Please set up a plan first, then try modify plan again.", plantName: plantName)
            return
        }

        addAssistantMessage("Let me think about the best plan for \(plantName)...", plantName: plantName)

        let context = buildAIContext(for: plantName, intake: intake)
        let gemini = GeminiService()

        // generate "why" for each change
        let cal = Calendar.current
        var questionsList: [String] = []
        for (i, change) in draft.changes.enumerated() {
            let delayDays = cal.dateComponents([.day], from: change.originalTask.dueDate, to: change.proposedTask.dueDate).day ?? 0
            let taskType = change.originalTask.title.lowercased()

            let scienceQ: String
            if taskType.contains("water") && delayDays < 0 {
                scienceQ = "Pre-watering \(abs(delayDays)) day(s) before a dry period — how does deep watering help this species retain moisture in roots and soil?"
            } else if taskType.contains("water") {
                scienceQ = "Watering delayed \(delayDays) days — how does this species handle \(delayDays) days without water? Discuss drought tolerance, wilting thresholds, and root zone drying."
            } else if taskType.contains("fertil") {
                scienceQ = "Fertilization delayed \(delayDays) days — how long do nutrients remain bioavailable in soil? Does this species have high nutrient demands?"
            } else if taskType.contains("rotat") || taskType.contains("turn") {
                scienceQ = "Rotation delayed \(delayDays) days — how fast does phototropism cause leaning in this species? Is it reversible?"
            } else if taskType.contains("prun") || taskType.contains("trim") {
                scienceQ = "Pruning delayed \(delayDays) days — does timing matter for this species' growth phase? Any disease risk?"
            } else if taskType.contains("mist") || taskType.contains("humid") {
                scienceQ = "Misting delayed \(delayDays) days — how does this affect leaf transpiration and humidity needs for this species?"
            } else if taskType.contains("check") || taskType.contains("inspect") || taskType.contains("soil") {
                scienceQ = "Soil/leaf inspection delayed \(delayDays) days — what early signs of stress might be missed, and how resilient is this species over that gap?"
            } else {
                scienceQ = "\(change.originalTask.title) delayed \(delayDays) days — what is the biological impact on this species?"
            }

            questionsList.append("[\(i + 1)] \(change.originalTask.title) — \(scienceQ)")
        }

        do {
            let explanations = try await gemini.generateBatchWhyExplanations(
                context: context,
                questions: questionsList
            )
            for (i, explanation) in explanations.enumerated() where i < draft.changes.count {
                draft.changes[i].reason = explanation
            }
        } catch {
            print("[PlantPal] Batch WHY generation failed: \(error.localizedDescription)")
        }

        pendingAdjustmentDraft = draft
        addAssistantMessage("I prepared a proposed schedule update for \(plantName). Tap Preview Changes to review it before applying.", plantName: plantName)
        setupStep = .adjustReadyForPreview
    }

    private func buildAIContext(for plantName: String, intake: AdjustmentIntake) -> String {
        var parts: [String] = []
        if let profile = profiles.first(where: { $0.name.caseInsensitiveCompare(plantName) == .orderedSame }) {
            parts.append("Plant: \(profile.name), type: \(profile.type), location: \(profile.location).")
        }
        if let memory = memories.first(where: { $0.plantName.caseInsensitiveCompare(plantName) == .orderedSame }) {
            if let freq = memory.wateringFrequencyDays {
                parts.append("Watering frequency: every \(freq) days.")
            }
            if let light = memory.lightPreference {
                parts.append("Light/environment: \(light).")
            }
            if let reason = memory.latestAdjustmentReason {
                parts.append("Previous adjustment: \(reason).")
            }
        }
        if let summary = summaries.first(where: { $0.plantName.caseInsensitiveCompare(plantName) == .orderedSame }) {
            parts.append("Chat history: \(summary.summary)")
        }
        if let dateRange = intake.dateRangeText {
            parts.append("User is away: \(dateRange).")
        }
        if let helper = intake.helperAvailable {
            parts.append("Someone can help while away: \(helper ? "yes" : "no").")
        }
        if let style = intake.style {
            switch style {
            case .relaxed: parts.append("User prefers a relaxed plan (spread out, less pressure).")
            case .balanced: parts.append("User prefers a balanced approach (normal pace).")
            case .attentive: parts.append("User prefers an attentive plan (catch up quickly, more care).")
            }
        }
        if let early = intake.preferEarly {
            parts.append(early ? "User prefers watering earlier before leaving." : "User prefers catching up after returning.")
        }
        if let goal = intake.longTermGoal {
            parts.append("Long-term goal: \(goal).")
        }
        return parts.joined(separator: "\n")
    }

    private func taskDateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func buildAdjustmentDraft(from intake: AdjustmentIntake) -> PendingPlanAdjustment? {
        let currentTasks = allTasks
            .filter { $0.plantName.caseInsensitiveCompare(intake.plantName) == .orderedSame }
            .sorted { $0.dueDate < $1.dueDate }
            .map { PendingCareTask(title: $0.title, notes: $0.notes, dueDate: $0.dueDate) }

        guard !currentTasks.isEmpty else { return nil }

        switch intake.changeType {
        case .shortTerm:
            return buildShortTermDraft(from: intake, currentTasks: currentTasks)
        case .longTerm:
            return buildLongTermDraft(from: intake, currentTasks: currentTasks)
        case .none:
            return nil
        }
    }

    private func buildShortTermDraft(from intake: AdjustmentIntake, currentTasks: [PendingCareTask]) -> PendingPlanAdjustment? {
        guard let awayStart = intake.awayStart, let awayEnd = intake.awayEnd else { return nil }

        var proposed = currentTasks
        var changes: [PendingTaskChange] = []
        let calendar = Calendar.current
        let awayStartDay = calendar.startOfDay(for: awayStart)
        let awayEndDay = calendar.startOfDay(for: awayEnd)
        let dayBeforeAway = calendar.date(byAdding: .day, value: -1, to: awayStartDay) ?? awayStartDay
        var resumeDay = calendar.date(byAdding: .day, value: 1, to: awayEndDay) ?? awayEndDay

        let indicesInAway = proposed.indices.filter { idx in
            let due = calendar.startOfDay(for: proposed[idx].dueDate)
            return due >= awayStartDay && due <= awayEndDay
        }

        let preferEarly = intake.preferEarly ?? true
        var movedEarlyIndex: Int?
        let dateLabel = { (d: Date) -> String in d.formatted(.dateTime.month(.abbreviated).day()) }
        let awayLabel = "\(dateLabel(awayStart)) – \(dateLabel(awayEnd))"

        if preferEarly {
            movedEarlyIndex = indicesInAway.first(where: { proposed[$0].title.lowercased().contains("water") })
            if let idx = movedEarlyIndex {
                let original = proposed[idx]
                proposed[idx] = adjustedTask(from: original, newDate: dayBeforeAway, reason: "Moved earlier before absence.")
                let whyFallback = "Pre-watering deeply saturates the root zone, creating a moisture buffer that sustains the plant while you're away. Most houseplants can draw water from deeper soil layers for 7–10 days after a thorough soaking. This approach minimizes drought stress without the risk of overwatering."
                changes.append(PendingTaskChange(originalTask: original, proposedTask: proposed[idx], reason: whyFallback))
            }
        }

        let spacing = spacingDays(for: intake.style ?? .balanced)
        for idx in indicesInAway {
            if preferEarly, idx == movedEarlyIndex { continue }
            let original = proposed[idx]
            let delayDays = calendar.dateComponents([.day], from: original.dueDate, to: resumeDay).day ?? 0
            proposed[idx] = adjustedTask(from: original, newDate: resumeDay, reason: "Paused during absence, resumed after return.")
            let whyFallback = biologyFallback(for: original.title, delayDays: delayDays)
            changes.append(PendingTaskChange(originalTask: original, proposedTask: proposed[idx], reason: whyFallback))
            resumeDay = calendar.date(byAdding: .day, value: spacing, to: resumeDay) ?? resumeDay
        }

        proposed.sort { $0.dueDate < $1.dueDate }

        return PendingPlanAdjustment(
            plantName: intake.plantName,
            currentTasks: currentTasks,
            proposedTasks: proposed,
            changes: changes
        )
    }

    private func buildLongTermDraft(from intake: AdjustmentIntake, currentTasks: [PendingCareTask]) -> PendingPlanAdjustment? {
        var proposed = currentTasks
        var changes: [PendingTaskChange] = []

        let desiredInterval = extractFrequencyDays(from: intake.longTermGoal ?? "") ?? 7
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var nextWaterDate = today
        let dateLabel = { (d: Date) -> String in d.formatted(.dateTime.month(.abbreviated).day()) }
        var waterIndex = 1

        for idx in proposed.indices {
            guard proposed[idx].title.lowercased().contains("water") else { continue }
            let original = proposed[idx]
            proposed[idx] = adjustedTask(from: original, newDate: nextWaterDate, reason: "Adjusted to every-\(desiredInterval)-day schedule.")
            let whyFallback = "Shifting to an every-\(desiredInterval)-day watering cycle aligns with this plant's root absorption rate. Most soil mixes retain adequate moisture for \(desiredInterval)–\(desiredInterval + 3) days depending on pot size and humidity, so this frequency keeps the root zone consistently moist without waterlogging."
            changes.append(PendingTaskChange(originalTask: original, proposedTask: proposed[idx], reason: whyFallback))
            nextWaterDate = calendar.date(byAdding: .day, value: desiredInterval, to: nextWaterDate) ?? nextWaterDate
            waterIndex += 1
        }

        proposed.sort { $0.dueDate < $1.dueDate }

        return PendingPlanAdjustment(
            plantName: intake.plantName,
            currentTasks: currentTasks,
            proposedTasks: proposed,
            changes: changes
        )
    }

    private func adjustedTask(from task: PendingCareTask, newDate: Date, reason: String) -> PendingCareTask {
        let noteSuffix = task.notes.isEmpty ? "" : " "
        return PendingCareTask(
            title: task.title,
            notes: task.notes + noteSuffix + "[Adjusted] \(reason)",
            dueDate: newDate
        )
    }

    /// Pre-written plant biology fallback in case the AI call fails
    private func biologyFallback(for taskTitle: String, delayDays: Int) -> String {
        let lower = taskTitle.lowercased()
        if lower.contains("water") {
            return "Your plant's soil acts as a moisture reservoir — even as the top inch dries out, deeper roots continue accessing water. Most tropical houseplants tolerate \(delayDays)–\(delayDays + 3) days between waterings depending on pot size and ambient humidity. After this gap, a thorough watering will fully rehydrate the root zone without causing stress."
        } else if lower.contains("fertil") {
            return "Fertilizer salts dissolve slowly and remain bioavailable in the soil for 2–3 weeks, so a \(delayDays)-day delay has minimal impact on nutrient supply. Your plant's roots continuously absorb residual nitrogen, phosphorus, and potassium from the existing soil solution. Resuming on the new date keeps the nutrient cycle consistent."
        } else if lower.contains("rotat") || lower.contains("turn") {
            return "Plants exhibit phototropism — stems and leaves gradually bend toward light at roughly 10–20° per week. A \(delayDays)-day pause may cause slight asymmetric growth, but this is fully reversible once you resume rotation. Your plant's auxin distribution will rebalance within a few days of turning."
        } else if lower.contains("prun") || lower.contains("trim") {
            return "Pruning timing is flexible for most houseplants. Delaying by \(delayDays) days won't significantly affect branching patterns or disease susceptibility. The plant simply continues allocating energy to existing growth points, and pruning when you return will redirect that energy to new lateral shoots."
        } else if lower.contains("mist") || lower.contains("humid") {
            return "Leaf transpiration rates depend on ambient humidity — in dry indoor air, leaf edges may curl slightly after \(delayDays) days without misting. However, most houseplants adapt by partially closing stomata to conserve moisture. Resuming misting will restore normal transpiration within a day or two."
        } else {
            return "A \(delayDays)-day gap in this care routine is within the tolerance range of most houseplants. Plants naturally adapt their metabolic rates to environmental changes, and resuming the routine allows them to quickly return to their normal growth pattern."
        }
    }

    private func spacingDays(for style: AdjustmentStyle) -> Int {
        switch style {
        case .attentive:
            return 1
        case .balanced:
            return 1
        case .relaxed:
            return 2
        }
    }

    private func parseDateRange(from text: String) -> (start: Date, end: Date)? {
        let normalized = text
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: " to ", with: "-")
            .replacingOccurrences(of: " to", with: "-")
            .replacingOccurrences(of: "to ", with: "-")

        let parts = normalized
            .split(separator: "-", maxSplits: 1)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count == 2 else { return nil }

        guard let start = parseSingleDate(parts[0]), let end = parseSingleDate(parts[1]) else { return nil }

        if end >= start {
            return (start, end)
        }
        if let nextYearEnd = Calendar.current.date(byAdding: .year, value: 1, to: end), nextYearEnd >= start {
            return (start, nextYearEnd)
        }
        return nil
    }

    private func parseSingleDate(_ text: String) -> Date? {
        let formats = [
            "MMM d yyyy", "MMMM d yyyy", "M/d/yyyy",
            "MMM d", "MMMM d", "M/d"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.isLenient = true

        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: text) {
                if format.contains("yyyy") {
                    return Calendar.current.startOfDay(for: parsed)
                }
                var comps = Calendar.current.dateComponents([.month, .day], from: parsed)
                comps.year = Calendar.current.component(.year, from: Date())
                if let date = Calendar.current.date(from: comps) {
                    return Calendar.current.startOfDay(for: date)
                }
            }
        }
        return nil
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func extractFrequencyDays(from text: String) -> Int? {
        let lower = text.lowercased()
        if lower.contains("daily") || lower.contains("every day") { return 1 }
        if lower.contains("weekly") { return 7 }
        if lower.contains("biweekly") { return 14 }
        let numbers = lower.split { !$0.isNumber }
        if let first = numbers.first, let value = Int(first) {
            return max(1, value)
        }
        return nil
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
    case askingQuestion(plantName: String?)
    case adjustAskPlantName
    case adjustAskChangeType(plantName: String)
    case adjustAskDateRange(plantName: String)
    case adjustAskHelperAvailability(plantName: String)
    case adjustAskPlanStyle(plantName: String)
    case adjustAskTimingPreference(plantName: String)
    case adjustAskLongTermGoal(plantName: String)
    case adjustReadyForPreview
}

private enum SetupIntent: String, CaseIterable {
    case setupNewPlant = "Set up a new plant"
    case askAboutPlant = "Ask about a plant"
    case modifyCurrentPlan = "Modify current care plan"
}

private enum AdjustmentChangeType {
    case shortTerm
    case longTerm
}

private enum AdjustmentStyle {
    case relaxed
    case balanced
    case attentive
}

private struct AdjustmentIntake {
    var plantName: String
    var changeType: AdjustmentChangeType?
    var dateRangeText: String?
    var awayStart: Date?
    var awayEnd: Date?
    var helperAvailable: Bool?
    var style: AdjustmentStyle?
    var preferEarly: Bool?
    var longTermGoal: String?
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
    Scenario1FlowView(selectedTab: .constant(1))
        .modelContainer(for: [
            PlantProfile.self,
            ChatMessage.self,
            ConversationSummary.self,
            PlantMemory.self,
            CareTask.self
        ], inMemory: true)
}
