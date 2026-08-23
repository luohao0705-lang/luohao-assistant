import SwiftUI

struct AssistantView: View {
    @ObservedObject var state: AppState
    @StateObject private var voice = VoiceInput()
    @State private var text = ""
    @State private var reply = ""
    @State private var toolResults: [[String: JSONValue]] = []
    @State private var mode = "chat"
    @State private var isSending = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(reply.isEmpty ? "Tell me what to plan or ask about cash and risk." : reply).frame(maxWidth: .infinity, alignment: .leading)
                        if !toolResults.isEmpty {
                            ForEach(Array(toolResults.enumerated()), id: \.offset) { _, item in
                                Label("Assistant action prepared", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.orange)
                                if let name = item["name"], case .string(let value) = name { Text(value).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        if !state.pendingActions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Waiting for your confirmation").font(.headline)
                                ForEach(state.pendingActions) { action in
                                    HStack { Text(action.actionType).font(.subheadline); Spacer(); Button("Cancel") { Task { await state.resolveAction(action, confirm: false) } }.buttonStyle(.borderless); Button("Confirm") { Task { await state.resolveAction(action, confirm: true) } }.buttonStyle(.borderedProminent).tint(.orange) }
                                }
                            }.padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    Button { Task { await voice.toggle() } } label: { Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill").font(.title2).foregroundStyle(voice.isRecording ? .red : .orange) }.accessibilityLabel(voice.isRecording ? "Stop recording" : "Start voice input")
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Mode", selection: $mode) { Text("Chat").tag("chat"); Text("Plan").tag("plan") }.pickerStyle(.segmented)
                        TextField("Describe your arrangement", text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
                    }.frame(maxWidth: .infinity)
                    Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending).accessibilityLabel("Send")
                }
            }.padding().navigationTitle("AI assistant").onChange(of: voice.transcript) { _, value in if !value.isEmpty { text = value } }
        }
    }
    private func send() {
        let prompt = text; text = ""; isSending = true
        Task { defer { isSending = false }; do { let response = try await state.api.command(prompt, mode: mode); reply = response.reply; toolResults = response.toolResults; await state.refreshDashboard() } catch { reply = error.localizedDescription } }
    }
}
