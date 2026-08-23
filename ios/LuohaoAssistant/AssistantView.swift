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
                        Text(reply.isEmpty ? "告诉我你要推进什么，或者想了解哪一项现金与风险。" : reply)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.body)
                        if !toolResults.isEmpty {
                            ForEach(Array(toolResults.enumerated()), id: \.offset) { _, item in
                                Label("已生成待确认方案", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.orange)
                                if let name = item["name"], case .string(let value) = name { Text(value).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                        if !state.pendingActions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("等待你的确认").font(.headline)
                                ForEach(state.pendingActions) { action in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(actionTitle(action.actionType)).font(.subheadline.weight(.semibold))
                                        Text(actionSummary(action.payload)).font(.caption).foregroundStyle(.secondary)
                                        HStack { Spacer(); Button("取消") { Task { await state.resolveAction(action, confirm: false) } }.buttonStyle(.borderless); Button("确认执行") { Task { await state.resolveAction(action, confirm: true) } }.buttonStyle(.borderedProminent).tint(.orange) }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }.padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        if let error = state.errorMessage, reply.isEmpty {
                            ContentUnavailableView("暂时无法连接助理", systemImage: "wifi.exclamationmark", description: Text(error))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    Button { Task { await voice.toggle() } } label: { Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic.fill").font(.title2).foregroundStyle(voice.isRecording ? .red : .orange) }.accessibilityLabel(voice.isRecording ? "停止录音" : "开始语音输入")
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("模式", selection: $mode) { Text("问答").tag("chat"); Text("规划").tag("plan") }.pickerStyle(.segmented)
                        TextField("说说你想安排或推进的事情", text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
                    }.frame(maxWidth: .infinity)
                    Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending).accessibilityLabel("发送")
                }
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8).navigationTitle("AI 经营助理").onChange(of: voice.transcript) { _, value in if !value.isEmpty { text = value } }
        }
    }
    private func send() {
        let prompt = text; text = ""; isSending = true
        Task { defer { isSending = false }; do { let response = try await state.api.command(prompt, mode: mode); reply = response.reply; toolResults = response.toolResults; await state.refreshDashboard() } catch { reply = error.localizedDescription } }
    }

    private func actionTitle(_ type: String) -> String {
        ["propose_tasks": "新增事项方案", "create_project_plan": "建立项目方案", "create_weekly_plan": "生成本周计划", "create_memory": "记录一条经营记忆", "create_decision": "记录一项经营决策"][type] ?? "待确认操作"
    }

    private func actionSummary(_ value: JSONValue) -> String {
        switch value {
        case .object(let object):
            let keys = ["name", "title", "objective", "next_action", "decision", "content"]
            for key in keys {
                if let item = object[key], case .string(let text) = item, !text.isEmpty { return text }
            }
            if let tasks = object["tasks"], case .array(let items) = tasks { return "将新增 \(items.count) 项待办" }
            return "AI 已整理出一份待确认方案"
        case .array(let items): return "包含 \(items.count) 项内容"
        case .string(let text): return text
        default: return "AI 已整理出一份待确认方案"
        }
    }
}
