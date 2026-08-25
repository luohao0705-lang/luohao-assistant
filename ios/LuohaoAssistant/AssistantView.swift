import SwiftUI

private struct AssistantMessage: Identifiable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let toolResults: [[String: JSONValue]]
    let suggestions: [String]
    let isError: Bool

    init(role: Role, text: String, toolResults: [[String: JSONValue]] = [], suggestions: [String] = [], isError: Bool = false) {
        self.role = role
        if Self.containsInternalProtocol(text) {
            // A few DeepSeek gateways can return their internal DSML trace as
            // assistant content. It must never be exposed in the chat UI.
            self.text = "这次请求没有正常完成，未写入或修改任何数据。请重新发送，或先核对后再确认。"
            self.toolResults = []
            self.suggestions = ["重新发送", "查看当前债务"]
            self.isError = true
        } else {
            self.text = text
            self.toolResults = toolResults
            self.suggestions = suggestions
            self.isError = isError
        }
    }

    private static func containsInternalProtocol(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("dsml") || normalized.contains("tool_calls") || normalized.contains("<|")
    }
}

struct AssistantView: View {
    @ObservedObject var state: AppState
    @StateObject private var voice = VoiceInput()
    @State private var messages: [AssistantMessage] = [
        AssistantMessage(
            role: .assistant,
            text: "现在进入规划模式。告诉我你要推进的项目、事项或财务登记，我会先整理成待确认方案。",
            suggestions: ["安排今天最重要的三件事", "登记一笔收入", "拆解一个项目"]
        )
    ]
    @State private var text = ""
    @State private var mode = "plan"
    @State private var isSending = false
    @State private var lastPrompt = ""
    @State private var requestTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    assistantHeader
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(messages) { message in
                                    AssistantMessageBubble(
                                        message: message,
                                        onRetry: message.isError ? retry : nil,
                                        onSelectOption: message.role == .assistant && isLatestAssistant(message) && !isSending ? { option in
                                            handleQuickOption(option)
                                        } : nil
                                    )
                                    .id(message.id)
                                }

                                if isSending {
                                    thinkingRow.id("thinking")
                                }

                                pendingActionsPanel
                                Color.clear.frame(height: 8).id("bottom")
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 12)
                        }
                        .scrollIndicators(.hidden)
                        .onAppear { scrollToLatest(proxy, animated: false) }
                        .onChange(of: messages.count) { _, _ in scrollToLatest(proxy, animated: true) }
                        .onChange(of: isSending) { _, sending in
                            if sending { scrollToLatest(proxy, animated: true) }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle("经营助理")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: voice.transcript) { _, value in
                if !value.isEmpty { text = value }
            }
            .onChange(of: mode) { _, newMode in
                resetConversation(for: newMode)
            }
            .onDisappear {
                requestTask?.cancel()
                requestTask = nil
            }
        }
    }

    private var assistantHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.14))
                Image(systemName: "waveform.and.magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("今天先处理最重要的事")
                    .font(.headline.weight(.semibold))
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let dashboard = state.dashboard {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("可用现金")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(currency(dashboard.cashCents))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusText: String {
        if state.isLoading { return "正在检查连接" }
        if state.connectionHealthy == false { return "连接需要检查" }
        if state.dashboard == nil { return "等待同步" }
        if let dashboard = state.dashboard {
            let count = state.pendingActions.count
            return count > 0 ? "连接正常 · \(count) 项待确认" : "连接正常 · 今日 \(dashboard.openTasks) 项待办"
        }
        return "等待同步"
    }

    private var statusColor: Color {
        if state.isLoading { return .orange }
        if state.connectionHealthy == false { return .red }
        return .green
    }

    private var thinkingRow: some View {
        HStack(alignment: .bottom, spacing: 9) {
            assistantMark
            VStack(alignment: .leading, spacing: 7) {
                Text("洛浩助理").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.orange)
                    Text(mode == "plan" ? "正在整理执行路径…" : mode == "finance" ? "正在核对财务信息…" : "正在核对你的经营情况…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Spacer(minLength: 30)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("助理正在思考")
    }

    @ViewBuilder
    private var pendingActionsPanel: some View {
        if !state.pendingActions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(.orange)
                    Text("等待你的确认")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text("AI 不会自动写入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(state.pendingActions) { action in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(actionTitle(action.actionType))
                            .font(.subheadline.weight(.semibold))
                        Text(actionSummary(action.payload))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button("先不执行") {
                                Task { await state.resolveAction(action, confirm: false) }
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)

                            Button {
                                Task {
                                    let confirmed = await state.resolveAction(action, confirm: true)
                                    if confirmed {
                                        messages.append(AssistantMessage(role: .assistant, text: "已确认执行，数据已经写入并同步到总览。"))
                                    } else {
                                        messages.append(AssistantMessage(role: .assistant, text: "确认失败：\(state.errorMessage ?? "服务器没有完成写入，请稍后重试。")", isError: true))
                                    }
                                }
                            } label: {
                                Label("确认执行", systemImage: "checkmark")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }
                        Button("修改方案") {
                            Task {
                                _ = await state.resolveAction(action, confirm: false)
                                send(promptOverride: "我想修改刚才的方案，请基于原方案直接给我一版修订后的待确认方案。")
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.orange.opacity(0.18), lineWidth: 1)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 10) {
                Picker("模式", selection: $mode) {
                    Text("问答").tag("chat")
                    Text("财务").tag("finance")
                    Text("规划").tag("plan")
                }
                .pickerStyle(.segmented)
                .frame(width: 132)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清空输入内容")
                    .accessibilityHint("删除输入框中的全部文字")
                }

                Spacer()

                if voice.isRecording {
                    Label("正在听", systemImage: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else if isSending {
                    Text("可随时停止")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                        Text(mode == "plan" ? "生成方案前会先征求确认" : mode == "finance" ? "财务写入前会先征求确认" : "只读分析，不会写入数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let voiceError = voice.errorMessage {
                Label(voiceError, systemImage: "mic.slash")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    Task { await voice.toggle() }
                } label: {
                    Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(voice.isRecording ? .red : .orange)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .accessibilityLabel(voice.isRecording ? "停止录音" : "开始语音输入")

                TextField("说说你想安排或推进的事情", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.body)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing in
                        if pressing {
                            Task { await voice.startRecording() }
                        } else {
                            voice.stopRecording()
                        }
                    }, perform: {})

                Button {
                    if isSending { stopRequest() } else { send() }
                } label: {
                    Image(systemName: isSending ? "stop.fill" : "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(sendButtonColor, in: Circle())
                }
                .disabled(!isSending && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(isSending ? "停止请求" : "发送")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(LuohaoDesign.card)
        .overlay(alignment: .top) { Divider().opacity(0.7) }
    }

    private var sendButtonColor: Color { isSending ? .secondary : .orange }

    private func resetConversation(for newMode: String) {
        requestTask?.cancel()
        requestTask = nil
        isSending = false
        text = ""
        lastPrompt = ""
        messages = [AssistantMessage(
            role: .assistant,
            text: newMode == "plan"
                ? "现在进入规划模式。告诉我你要推进的项目或事项，我会先整理成待确认方案。"
                : newMode == "finance"
                    ? "现在进入财务模式。告诉我收入、支出、债务或账户变动，我会先整理成待确认登记。"
                    : "现在进入问答模式。你可以查询现金、债务、项目、任务和经营风险；此模式不会写入数据。",
            suggestions: newMode == "plan"
                ? ["安排今天最重要的三件事", "拆解一个项目", "生成本周计划"]
                : newMode == "finance"
                    ? ["登记一笔收入", "登记一笔支出", "登记一笔债务"]
                    : ["查看现金风险", "查看今天重点", "查看当前债务"]
        )]
    }

    private func send(promptOverride: String? = nil) {
        let prompt = (promptOverride ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSending else { return }
        let history = conversationHistory()
        text = ""
        lastPrompt = prompt
        messages.append(AssistantMessage(role: .user, text: prompt))
        isSending = true

        if isExplicitConfirmation(prompt) {
            requestTask = Task {
                await state.refreshPendingActions()
                guard !Task.isCancelled else { return }
                if let action = state.pendingActions.first, state.pendingActions.count == 1 {
                    let confirmed = await state.resolveAction(action, confirm: true)
                    guard !Task.isCancelled else { return }
                    messages.append(AssistantMessage(role: .assistant, text: confirmed
                        ? "已确认，方案已正式写入。后续结果已经同步到总览。"
                        : "确认没有完成，请检查网络或重试。"))
                    isSending = false
                    requestTask = nil
                } else {
                    messages.append(AssistantMessage(role: .assistant, text: state.pendingActions.isEmpty
                        ? "目前没有等待确认的方案。"
                        : "当前有多份待确认方案，请点击对应方案的确认按钮，避免误执行。"))
                }
                isSending = false
                requestTask = nil
            }
            return
        }

        requestTask = Task {
            do {
                let response = try await state.api.command(prompt, mode: mode, history: history)
                guard !Task.isCancelled else { return }
                let suggestions = response.suggestions.isEmpty && response.toolResults.isEmpty
                    ? fallbackSuggestions(for: response.reply)
                    : response.suggestions
                messages.append(AssistantMessage(role: .assistant, text: response.reply, toolResults: response.toolResults, suggestions: suggestions))
                // Load the confirmation queue immediately. A full dashboard
                // refresh can fail on an unrelated endpoint and must not hide
                // the action that the user needs to approve.
                await state.refreshPendingActions()
                await state.refreshDashboard()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                messages.append(AssistantMessage(role: .assistant, text: "这次没有完成请求：\(error.localizedDescription)", isError: true))
            }
            isSending = false
            requestTask = nil
        }
    }

    private func handleQuickOption(_ option: String) {
        if ["确认登记", "确认执行", "确认方案"].contains(option) {
            resolveLatestPendingAction()
        } else if option == "重新发送" {
            retry()
        } else if option == "修改方案" {
            reviseLatestPendingAction()
        } else {
            send(promptOverride: option)
        }
    }

    private func resolveLatestPendingAction() {
        guard !isSending else { return }
        messages.append(AssistantMessage(role: .user, text: "确认执行"))
        isSending = true
        requestTask = Task {
            await state.refreshPendingActions()
            guard !Task.isCancelled else { return }
            if let action = state.pendingActions.first, state.pendingActions.count == 1 {
                let confirmed = await state.resolveAction(action, confirm: true)
                if !Task.isCancelled {
                    messages.append(AssistantMessage(role: .assistant, text: confirmed
                        ? "已确认执行，数据已经写入并同步到总览。"
                        : "确认失败：\(state.errorMessage ?? "服务器没有完成写入，请稍后重试。")", isError: !confirmed))
                }
            } else {
                messages.append(AssistantMessage(role: .assistant, text: state.pendingActions.isEmpty
                    ? "目前没有等待确认的方案。"
                    : "当前有多份待确认方案，请点击对应方案的确认按钮。"))
            }
            isSending = false
            requestTask = nil
        }
    }

    private func reviseLatestPendingAction() {
        guard !isSending else { return }
        messages.append(AssistantMessage(role: .user, text: "修改方案"))
        isSending = true
        requestTask = Task {
            await state.refreshPendingActions()
            if let action = state.pendingActions.first, state.pendingActions.count == 1 {
                _ = await state.resolveAction(action, confirm: false)
            }
            guard !Task.isCancelled else { return }
            isSending = false
            requestTask = nil
            send(promptOverride: "我想修改刚才的方案，请基于原方案直接给我一版修订后的待确认方案。")
        }
    }

    private func retry() {
        guard !lastPrompt.isEmpty, !isSending else { return }
        send(promptOverride: lastPrompt)
    }

    private func isExplicitConfirmation(_ value: String) -> Bool {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "。", with: "")
            .replacingOccurrences(of: "！", with: "")
            .replacingOccurrences(of: "!", with: "")
        return [
            "ok", "okay", "确认", "确认登记", "确认方案", "确认执行", "可以执行", "同意", "没问题",
            "就这样", "按这个执行", "按方案执行", "好的", "可以"
        ].contains(normalized)
    }

    private func conversationHistory() -> [[String: String]] {
        messages
            .filter { !$0.isError && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(16)
            .map { message in
                [
                    "role": message.role == .user ? "user" : "assistant",
                    "content": message.text
                ]
            }
    }

    private func isLatestAssistant(_ message: AssistantMessage) -> Bool {
        messages.last(where: { $0.role == .assistant })?.id == message.id
    }

    private func fallbackSuggestions(for reply: String) -> [String] {
        let normalized = reply.replacingOccurrences(of: " ", with: "")
        guard normalized.contains("？") || normalized.contains("?") ||
                normalized.contains("是否") || normalized.contains("要不要") ||
                normalized.contains("请选择") || normalized.contains("请告诉我") ||
                normalized.contains("请提供") else { return [] }
        if normalized.contains("时间") || normalized.contains("日期") || normalized.contains("什么时候") {
            return ["今天", "本周", "下周"]
        }
        if normalized.contains("优先") || normalized.contains("先做") || normalized.contains("重点") {
            return ["先看现金风险", "先推进项目", "先清理阻塞"]
        }
        return ["继续说明", "先看现金风险", "安排今天三件事"]
    }

    private func stopRequest() {
        requestTask?.cancel()
        requestTask = nil
        isSending = false
        messages.append(AssistantMessage(role: .assistant, text: "已停止这次请求。你可以调整说法后重新发送。"))
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        Task { @MainActor in
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var assistantMark: some View {
        ZStack {
            Circle().fill(Color.orange.opacity(0.14))
            Image(systemName: "waveform")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
        }
        .frame(width: 28, height: 28)
    }

    private func currency(_ cents: Int) -> String {
        let value = Double(cents) / 100
        return String(format: "¥%.2f", value)
    }

    private func actionTitle(_ type: String) -> String {
        [
            "propose_tasks": "新增事项方案",
            "propose_finance_entry": "登记财务记录",
            "propose_debt_payment": "登记债务还款",
            "create_project_plan": "建立项目方案",
            "create_weekly_plan": "生成本周计划",
            "create_memory": "记录一条经营记忆",
            "create_decision": "记录一项经营决策"
        ][type] ?? localizedActionType(type)
    }

    private func actionSummary(_ value: JSONValue) -> String {
        switch value {
        case .object(let object):
            if let amount = object["amount_cents"], case .number(let cents) = amount {
                let kind = object["kind"].flatMap { value -> String? in
                    if case .string(let text) = value { return text }
                    return nil
                }
                let label = kind == "income" ? "收入" : "支出"
                return "\(label) \(String(format: "%.2f", cents / 100)) 元"
            }
            if let payment = object["payment_cents"], case .number(let cents) = payment {
                let creditor = object["creditor"].flatMap { value -> String? in
                    if case .string(let text) = value { return text }
                    return nil
                } ?? "债务"
                return "偿还 \(creditor) \(String(format: "%.2f", cents / 100)) 元"
            }
            for key in ["name", "title", "objective", "next_action", "decision", "content"] {
                if let item = object[key], case .string(let value) = item, !value.isEmpty { return value }
            }
            if let tasks = object["tasks"], case .array(let items) = tasks { return "将新增 \(items.count) 项待办" }
            return "AI 已整理出一份待确认方案"
        case .array(let items): return "包含 \(items.count) 项内容"
        case .string(let value): return value
        default: return "AI 已整理出一份待确认方案"
        }
    }
}

private struct AssistantMessageBubble: View {
    let message: AssistantMessage
    let onRetry: (() -> Void)?
    let onSelectOption: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if message.role == .assistant { assistantMark }
            if message.role == .user { Spacer(minLength: 34) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                Text(message.role == .user ? "你" : "洛浩助理")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                AssistantRichText(text: message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        if message.isError {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        }
                    }

                if !message.toolResults.isEmpty { toolTrace }

                if let onSelectOption {
                    // Confirmation is rendered by the real pending-action
                    // panel below the transcript. Do not present a chat chip
                    // that can say "confirm" when no action exists.
                    let options = requiresConfirmation ? [] : message.suggestions
                    if !options.isEmpty {
                        quickOptions(options, onSelectOption)
                    }
                }

                if let onRetry {
                    Button("重新发送", action: onRetry)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: 380, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 22) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var bubbleBackground: Color {
        if message.isError { return Color.red.opacity(0.08) }
        return message.role == .user ? .orange : Color(.secondarySystemBackground)
    }

    private var requiresConfirmation: Bool {
        let normalized = message.text.replacingOccurrences(of: " ", with: "")
        let hasPendingTool = message.toolResults.contains { item in
            guard let name = item["name"], case .string(let value) = name else { return false }
            return ["propose_finance_entry", "propose_debt_payment", "propose_tasks", "create_project_plan", "create_weekly_plan"].contains(value)
        }
        return hasPendingTool || normalized.contains("确认此方案") ||
            normalized.contains("请回复“确认") ||
            normalized.contains("请回复\"确认") ||
            normalized.contains("确认后，我会立即正式写入")
    }

    private var confirmationOptions: [String] {
        let normalized = message.text.replacingOccurrences(of: " ", with: "")
        let financeTerms = ["收入", "支出", "收款", "付款", "贷款", "债务", "账户", "金额", "元"]
        let isFinanceTool = message.toolResults.contains { item in
            if let name = item["name"], case .string(let value) = name { return value == "propose_finance_entry" || value == "propose_debt_payment" }
            return false
        }
        let confirmLabel = isFinanceTool || financeTerms.contains(where: normalized.contains) ? "确认登记" : "确认执行"
        return [confirmLabel, "修改方案"]
    }

    private var assistantMark: some View {
        ZStack {
            Circle().fill(Color.orange.opacity(0.14))
            Image(systemName: "waveform")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
        }
        .frame(width: 28, height: 28)
    }

    private var toolTrace: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(message.toolResults.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    if let name = item["name"], case .string(let value) = name {
                        Text("已完成 · \(localizedToolName(value))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("已完成一项数据核对")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func quickOptions(_ options: [String], _ onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("可以直接选择")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(options, id: \.self) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        Text(option)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择 \(option)")
                }
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
    }
}

private struct AssistantRichText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: normalizedText, options: .init(interpretedSyntax: .full)) {
            Text(attributed)
        } else {
            Text(plainFallback)
        }
    }

    private var normalizedText: String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var plainFallback: String {
        normalizedText
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let value = String(line)
                    .replacingOccurrences(of: #"^\s*#{1,6}\s*"#, with: "", options: .regularExpression)
                if value.trimmingCharacters(in: .whitespaces).hasPrefix("* ") {
                    return value.replacingOccurrences(of: "* ", with: "• ", options: [], range: value.range(of: "* "))
                }
                if value.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                    return value.replacingOccurrences(of: "- ", with: "• ", options: [], range: value.range(of: "- "))
                }
                return value
            }
            .joined(separator: "\n")
    }
}
