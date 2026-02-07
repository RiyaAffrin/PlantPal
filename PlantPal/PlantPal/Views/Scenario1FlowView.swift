import SwiftUI

struct Scenario1FlowView: View {
    @State private var agentName = "PlantPal"
    @State private var chatMessages: [SetupMessage] = [
        SetupMessage(role: .assistant, text: "Welcome to PlantPal."),
        SetupMessage(role: .assistant, text: "What can I help you today?")
    ]
    @State private var inputText = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if chatMessages.count >= 2 {
                            OptionRow(options: [
                                "Setup a new plant",
                                "Question about my plant",
                                "Modify current care schedule"
                            ]) { option in
                                inputText = option
                                handleSend()
                            }
                        }

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

        chatMessages.append(SetupMessage(role: .user, text: trimmed))
        isSending = true

        Task {
            do {
                let history = chatMessages.map { msg in
                    ChatMessage(role: msg.role == .assistant ? "assistant" : "user", content: msg.text, plantName: "PlantPal")
                }
                let reply = try await GeminiService().generateReply(history: history, memory: nil, summary: nil)
                chatMessages.append(SetupMessage(role: .assistant, text: reply))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
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

private struct OptionRow: View {
    let options: [String]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    onSelect(option)
                }
                .buttonStyle(.bordered)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        }
        .padding(.bottom, 6)
    }
}

#Preview {
    Scenario1FlowView()
}
