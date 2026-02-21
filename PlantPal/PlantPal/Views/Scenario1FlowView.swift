import SwiftUI
import SwiftData

struct Scenario1FlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlantProfile.createdAt, order: .reverse) private var profiles: [PlantProfile]
    @Query(sort: \ConversationSummary.updatedAt, order: .reverse) private var summaries: [ConversationSummary]
    @Query(sort: \PlantMemory.updatedAt, order: .reverse) private var memories: [PlantMemory]
    @Query(sort: \CareTask.dueDate, order: .forward) private var allTasks: [CareTask]

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
                            .frame(maxWidth: 340)
                        }

                        if let options = optionsForCurrentStep {
                            OptionCard(options: options) { selected in
                                inputText = selected
                                handleSend()
                            }
                            .frame(maxWidth: 340)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider()

                if pendingAdjustmentDraft != nil {
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
                ReviewPlanView(plantName: plan.plantName, draftPlan: plan)
            }
            .navigationDestination(item: $adjustmentPreview) { plan in
                AdjustPlanPreviewView(draft: plan)
            }
            .onChange(of: profiles.count) { oldCount, newCount in
                // reset local chat state when all data gets cleared
                if oldCount > 0 && newCount == 0 {
                    resetToInitialState()
                }
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
        case .adjustAskPlantName:
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: "PlantPal")
            let plantName = normalizedPlantName(from: trimmed) ?? trimmed
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
            addAssistantMessage("How hands-on do you want the plan to be? (Conservative / Balanced / Hands-off)", plantName: plantName)
            setupStep = .adjustAskPlanStyle(plantName: plantName)
            isSending = false
        case .adjustAskPlanStyle(let plantName):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: plantName)
            let lower = trimmed.lowercased()
            if lower.contains("conservative") {
                updateAdjustmentIntake { $0.style = .conservative }
            } else if lower.contains("balanced") {
                updateAdjustmentIntake { $0.style = .balanced }
            } else if lower.contains("hands") {
                updateAdjustmentIntake { $0.style = .handsOff }
            } else {
                addAssistantMessage("Please choose conservative, balanced, or hands-off.", plantName: plantName)
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
            finalizeAdjustment(for: plantName)
            isSending = false
        case .adjustAskLongTermGoal(let plantName):
            chatMessages.append(SetupMessage(role: .user, text: trimmed))
            persistMessage(role: "user", content: trimmed, plantName: plantName)
            updateAdjustmentIntake {
                $0.longTermGoal = trimmed
                $0.style = .balanced
                $0.preferEarly = false
            }
            finalizeAdjustment(for: plantName)
            isSending = false
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
        if lower.contains("question") {
            pendingAdjustmentDraft = nil
            adjustmentPreview = nil
            addAssistantMessage("Sure. Which plant is this about?", plantName: "PlantPal")
            setupStep = .collectPlantName
            return
        }
        if lower.contains("modify") {
            pendingAdjustmentDraft = nil
            adjustmentPreview = nil
            if let plantName = suggestedPlantForAdjustment() {
                adjustmentIntake = AdjustmentIntake(plantName: plantName)
                addAssistantMessage("Great. I can modify \(plantName)'s current care plan.", plantName: plantName)
                if let context = adjustmentContext(for: plantName) {
                    addAssistantMessage(context, plantName: plantName)
                }
                addAssistantMessage("What would you like to change today? Short-term or long-term?", plantName: plantName)
                setupStep = .adjustAskChangeType(plantName: plantName)
            } else {
                addAssistantMessage("Okay. Which plant's plan should I modify?", plantName: "PlantPal")
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
        pendingPlan = PendingCarePlan(
            plantName: name,
            tasks: pendingTasks,
            explanation: scheduleResult.explanation
        )

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
        case .adjustAskChangeType:
            return [
                "Short-term change (for a specific period)",
                "Long-term change (a permanent update)"
            ]
        case .adjustAskHelperAvailability:
            return ["Yes", "No"]
        case .adjustAskPlanStyle:
            return [
                "Conservative (avoid underwater)",
                "Balanced",
                "Hands-off (minimal actions)"
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
        if profiles.count == 1 {
            return profiles.first?.name
        }
        if let fromMemory = memories.first?.plantName {
            return fromMemory
        }
        if let fromSummary = summaries.first?.plantName {
            return fromSummary
        }
        return nil
    }

    private func normalizedPlantName(from raw: String) -> String? {
        profiles.first(where: { $0.name.caseInsensitiveCompare(raw) == .orderedSame })?.name
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

    private func finalizeAdjustment(for plantName: String) {
        guard var intake = adjustmentIntake else {
            addAssistantMessage("I couldn't collect enough information. Please try again.", plantName: plantName)
            return
        }
        intake.plantName = plantName
        adjustmentIntake = intake

        guard let draft = buildAdjustmentDraft(from: intake) else {
            addAssistantMessage("I could not find a current schedule yet. Please set up a plan first, then try modify plan again.", plantName: plantName)
            return
        }

        pendingAdjustmentDraft = draft
        addAssistantMessage("I prepared a proposed schedule update for \(plantName). Tap Preview Changes to review it before applying.", plantName: plantName)
        setupStep = .adjustReadyForPreview
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
        if preferEarly {
            movedEarlyIndex = indicesInAway.first(where: { proposed[$0].title.lowercased().contains("water") })
            if let idx = movedEarlyIndex {
                let original = proposed[idx]
                let reason = "Moved watering earlier so the plant gets moisture before your trip."
                proposed[idx] = adjustedTask(from: original, newDate: dayBeforeAway, reason: reason)
                changes.append(PendingTaskChange(originalTask: original, proposedTask: proposed[idx], reason: reason))
            }
        }

        let spacing = spacingDays(for: intake.style ?? .balanced)
        for idx in indicesInAway {
            if preferEarly, idx == movedEarlyIndex { continue }
            let original = proposed[idx]
            let reason = "Paused while you are away and resumed after return."
            proposed[idx] = adjustedTask(from: original, newDate: resumeDay, reason: reason)
            changes.append(PendingTaskChange(originalTask: original, proposedTask: proposed[idx], reason: reason))
            resumeDay = calendar.date(byAdding: .day, value: spacing, to: resumeDay) ?? resumeDay
        }

        proposed.sort { $0.dueDate < $1.dueDate }

        let helperText = intake.helperAvailable == true
            ? "Optional: ask your helper for one quick soil check during the trip."
            : "Optional: if possible, add one mid-trip soil check reminder."

        let summary = [
            "Water once before your trip.",
            "Pause reminders while you're away (\(dateText(awayStartDay)) - \(dateText(awayEndDay))).",
            "Resume the regular schedule after you return."
        ]

        return PendingPlanAdjustment(
            plantName: intake.plantName,
            currentTasks: currentTasks,
            proposedTasks: proposed,
            strategySummary: summary,
            optionalTip: helperText,
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

        for idx in proposed.indices {
            guard proposed[idx].title.lowercased().contains("water") else { continue }
            let original = proposed[idx]
            let reason = "Updated to your new long-term watering preference (every \(desiredInterval) days)."
            proposed[idx] = adjustedTask(from: original, newDate: nextWaterDate, reason: reason)
            changes.append(PendingTaskChange(originalTask: original, proposedTask: proposed[idx], reason: reason))
            nextWaterDate = calendar.date(byAdding: .day, value: desiredInterval, to: nextWaterDate) ?? nextWaterDate
        }

        proposed.sort { $0.dueDate < $1.dueDate }

        return PendingPlanAdjustment(
            plantName: intake.plantName,
            currentTasks: currentTasks,
            proposedTasks: proposed,
            strategySummary: [
                "Adopt a permanent watering cadence of every \(desiredInterval) days.",
                "Keep non-watering tasks as close to the existing routine as possible."
            ],
            optionalTip: "You can fine-tune this later after one or two check-ins.",
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

    private func spacingDays(for style: AdjustmentStyle) -> Int {
        switch style {
        case .conservative:
            return 1
        case .balanced:
            return 1
        case .handsOff:
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
    case questionNewPlant = "Question about a new plant"
    case modifyCurrentPlan = "Modify current care plan"
}

private enum AdjustmentChangeType {
    case shortTerm
    case longTerm
}

private enum AdjustmentStyle {
    case conservative
    case balanced
    case handsOff
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
    Scenario1FlowView()
        .modelContainer(for: [
            PlantProfile.self,
            ChatMessage.self,
            ConversationSummary.self,
            PlantMemory.self,
            CareTask.self
        ], inMemory: true)
}
