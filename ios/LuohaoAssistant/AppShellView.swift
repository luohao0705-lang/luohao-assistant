import SwiftUI
import Charts

struct AppShellView: View {
    @ObservedObject var state: AppState
    @State private var selection = 0
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $selection) {
            DashboardView(state: state)
                .tabItem { Label("总览", systemImage: "square.grid.2x2") }
                .tag(0)
            FinanceView(state: state)
                .tabItem { Label("财务", systemImage: "yensign.circle") }
                .tag(1)
            TasksView(state: state)
                .tabItem { Label("事项", systemImage: "checklist") }
                .tag(2)
            ProjectsView(state: state)
                .tabItem { Label("项目", systemImage: "rectangle.3.group") }
                .tag(3)
            AssistantView(state: state)
                .tabItem { Label("助理", systemImage: "waveform") }
                .tag(4)
        }
        .tint(.orange)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView(state: state) }
    }
}

struct FinanceView: View {
    @ObservedObject var state: AppState
    @State private var section = "概览"
    @State private var showingEntry = false
    @State private var entryType = "收支"
    @State private var selectedTransaction: TransactionSummary?
    @State private var selectedDebt: DebtSummary?
    private let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeader("财务中枢", subtitle: "先看现金安全，再安排支出和还款")
                    if let dashboard = state.dashboard {
                        HStack(spacing: 12) {
                            metric("可用现金", dashboard.cashCents, .orange)
                            metric("未偿债务", dashboard.outstandingDebtCents, .red)
                        }
                        HStack(spacing: 12) {
                            metric("30 天到期", dashboard.debtDue30dCents, .secondary)
                            metric("计划支出", dashboard.plannedExpenseCents, .secondary)
                        }
                    }
                    sectionTitle("现金预测", detail: "未来 45 天")
                    if state.cashflow.isEmpty {
                        empty("还没有现金预测", message: "通过语音告诉助理预计收入、支出或还款日期。", icon: "chart.xyaxis.line")
                    } else {
                        cashflowMiniChart
                    }
                    sectionTitle("下一步", detail: nil)
                    Picker("财务视图", selection: $section) {
                        Text("概览").tag("概览")
                        Text("账户").tag("账户")
                        Text("流水").tag("流水")
                        Text("债务").tag("债务")
                    }
                    .pickerStyle(.segmented)
                    financeDetail
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle("财务")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { entryType = "收支"; showingEntry = true } label: { Label("新增记录", systemImage: "plus") }
                        Button { entryType = "账户"; showingEntry = true } label: { Label("新增账户", systemImage: "building.columns") }
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新增财务数据")
                }
            }
            .sheet(isPresented: $showingEntry) { FinanceEntryView(state: state, initialEntryType: entryType) }
            .sheet(item: $selectedTransaction) { TransactionEditView(state: state, item: $0) }
            .sheet(item: $selectedDebt) { DebtEditView(state: state, item: $0) }
        }
    }

    private func metric(_ title: String, _ cents: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(currency.string(from: NSNumber(value: Double(cents) / 100)) ?? "¥0")
                .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var cashflowMiniChart: some View {
        ChartView(points: state.cashflow)
            .frame(height: 170)
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var financeDetail: some View {
        switch section {
        case "账户":
            if state.accounts.isEmpty { empty("还没有账户", message: "使用 AI 助理或后续新增账户。", icon: "building.columns") }
            else { ForEach(state.accounts) { account in detailRow(account.name, localizedAccountKind(account.kind), account.balanceCents, account.currency) } }
        case "流水":
            if state.transactions.isEmpty { empty("还没有流水", message: "收入和支出会在这里按日期记录。", icon: "list.bullet.rectangle") }
            else { ForEach(state.transactions.prefix(20)) { item in
                Button { selectedTransaction = item } label: {
                    detailRow(item.counterparty ?? (item.kind == "income" ? "收入" : "支出"), "\(item.occurredOn) · \(statusLabel(item.status))", item.kind == "income" ? item.amountCents : -item.amountCents, "CNY")
                }.buttonStyle(.plain)
            } }
        case "债务":
            if state.debts.isEmpty { empty("没有未偿债务", message: "新增贷款或应付款后，这里会显示还款压力。", icon: "creditcard") }
            else { ForEach(state.debts) { debt in
                Button { selectedDebt = debt } label: { detailRow(debt.creditor, "\(localizedDebtStatus(debt.status)) · " + (debt.dueOn.map { "到期 \($0)" } ?? "未设到期日"), debt.outstandingCents, "CNY") }.buttonStyle(.plain)
            } }
        default:
            Text("金额明细已按账户、流水和债务分开整理。")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func statusLabel(_ value: String) -> String {
        ["planned": "计划", "confirmed": "已确认", "paid": "已支付", "overdue": "已逾期", "cancelled": "已取消"][value] ?? value
    }

    private func detailRow(_ title: String, _ subtitle: String, _ cents: Int, _ currencyCode: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Text(currency.string(from: NSNumber(value: Double(cents) / 100)) ?? "¥0")
                .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(cents < 0 ? .red : .primary)
        }
        .padding(.vertical, 8)
    }
}

struct FinanceEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: AppState
    @State private var kind = "expense"
    @State private var creditor = ""
    @State private var amount = ""
    @State private var counterparty = ""
    @State private var note = ""
    @State private var dueOn = ""
    @State private var entryType: String
    @State private var accountKind = "bank"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingConfirmation = false

    init(state: AppState, initialEntryType: String = "收支") {
        self.state = state
        _entryType = State(initialValue: initialEntryType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("记录类型", selection: $entryType) {
                    Text("收入/支出").tag("收支")
                    Text("债务").tag("债务")
                    Text("账户").tag("账户")
                }
                .pickerStyle(.segmented)
                if entryType == "收支" {
                    Picker("方向", selection: $kind) { Text("支出").tag("expense"); Text("收入").tag("income") }
                    TextField("金额（元）", text: $amount).keyboardType(.decimalPad)
                    TextField("对方或用途（可选）", text: $counterparty)
                    TextField("备注（可选）", text: $note, axis: .vertical)
                } else if entryType == "债务" {
                    TextField("债权人", text: $creditor)
                    TextField("本金（元）", text: $amount).keyboardType(.decimalPad)
                    TextField("未偿余额（元）", text: $counterparty).keyboardType(.decimalPad)
                    TextField("到期日 YYYY-MM-DD（可选）", text: $dueOn)
                    TextField("备注（可选）", text: $note, axis: .vertical)
                } else {
                    TextField("账户名称", text: $creditor)
                    Picker("账户类型", selection: $accountKind) {
                        Text("银行账户").tag("bank")
                        Text("现金").tag("cash")
                        Text("第三方支付").tag("wallet")
                    }
                    TextField("当前余额（元）", text: $amount).keyboardType(.decimalPad)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Section {
                    Button { requestSave() } label: {
                        HStack { Spacer(); if isSaving { ProgressView() } else { Text("保存记录").fontWeight(.semibold) }; Spacer() }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle("新增财务数据")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .confirmationDialog("确认写入这条财务记录？", isPresented: $showingConfirmation, titleVisibility: .visible) {
                Button("确认写入", role: .destructive) { save() }
                Button("返回修改", role: .cancel) { }
            } message: {
                Text("写入后会影响现金总览和风险预测，并留下审计记录。")
            }
        }
    }

    private func requestSave() {
        guard let value = Double(amount), value > 0 else { errorMessage = "请输入有效金额"; return }
        if entryType == "债务" && creditor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errorMessage = "请输入债权人"; return }
        if entryType == "账户" && creditor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errorMessage = "请输入账户名称"; return }
        _ = value
        errorMessage = nil
        showingConfirmation = true
    }

    private func save() {
        guard let value = Double(amount), value > 0 else { errorMessage = "请输入有效金额"; return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                if entryType == "收支" {
                    try await state.api.createTransaction(TransactionCreateRequest(accountId: nil, kind: kind, amountCents: Int(value * 100), occurredOn: today(), status: "confirmed", counterparty: counterparty.isEmpty ? nil : counterparty, note: note.isEmpty ? nil : note))
                } else if entryType == "债务" {
                    let outstanding = Double(counterparty) ?? value
                    try await state.api.createDebt(DebtCreateRequest(creditor: creditor, principalCents: Int(value * 100), outstandingCents: Int(outstanding * 100), dueOn: dueOn.isEmpty ? nil : dueOn, interestRate: nil, note: note.isEmpty ? nil : note))
                } else {
                    try await state.api.createAccount(AccountCreateRequest(name: creditor, kind: accountKind, balanceCents: Int(value * 100), currency: "CNY"))
                }
                await state.refreshDashboard()
                dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }

    private func today() -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: Date())
    }
}

struct TransactionEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: AppState
    let item: TransactionSummary
    @State private var kind: String
    @State private var amount: String
    @State private var occurredOn: String
    @State private var status: String
    @State private var counterparty: String
    @State private var note: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingConfirmation = false

    init(state: AppState, item: TransactionSummary) {
        self.state = state
        self.item = item
        _kind = State(initialValue: item.kind)
        _amount = State(initialValue: String(format: "%.2f", Double(item.amountCents) / 100))
        _occurredOn = State(initialValue: item.occurredOn)
        _status = State(initialValue: item.status)
        _counterparty = State(initialValue: item.counterparty ?? "")
        _note = State(initialValue: item.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("方向", selection: $kind) { Text("支出").tag("expense"); Text("收入").tag("income") }.pickerStyle(.segmented)
                TextField("金额（元）", text: $amount).keyboardType(.decimalPad)
                TextField("发生日期 YYYY-MM-DD", text: $occurredOn)
                Picker("状态", selection: $status) {
                    Text("计划").tag("planned"); Text("已确认").tag("confirmed"); Text("已支付").tag("paid"); Text("已逾期").tag("overdue"); Text("已取消").tag("cancelled")
                }
                TextField("对方或用途", text: $counterparty)
                TextField("备注", text: $note, axis: .vertical)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button { requestSave() } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text("保存修改").fontWeight(.semibold) }; Spacer() } }.disabled(isSaving)
            }
            .navigationTitle("编辑流水")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .confirmationDialog("确认修改这笔流水？", isPresented: $showingConfirmation, titleVisibility: .visible) {
                Button("确认写入", role: .destructive) { save() }
                Button("返回修改", role: .cancel) { }
            } message: {
                Text("修改会影响现金总览和风险预测，并留下审计记录。")
            }
        }
    }

    private func requestSave() {
        guard let value = Double(amount), value > 0 else { errorMessage = "请输入有效金额"; return }
        guard occurredOn.count == 10 else { errorMessage = "日期格式应为 YYYY-MM-DD"; return }
        _ = value
        errorMessage = nil
        showingConfirmation = true
    }

    private func save() {
        guard let value = Double(amount), value > 0 else { errorMessage = "请输入有效金额"; return }
        isSaving = true; errorMessage = nil
        Task {
            do {
                try await state.api.updateTransaction(item.id, TransactionUpdateRequest(kind: kind, amountCents: Int(value * 100), occurredOn: occurredOn, status: status, counterparty: counterparty.isEmpty ? nil : counterparty, note: note.isEmpty ? nil : note))
                await state.refreshDashboard(); dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }
}

struct DebtEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: AppState
    let item: DebtSummary
    @State private var creditor: String
    @State private var principal: String
    @State private var outstanding: String
    @State private var dueOn: String
    @State private var status: String
    @State private var note: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingConfirmation = false

    init(state: AppState, item: DebtSummary) {
        self.state = state; self.item = item
        _creditor = State(initialValue: item.creditor)
        _principal = State(initialValue: String(format: "%.2f", Double(item.principalCents) / 100))
        _outstanding = State(initialValue: String(format: "%.2f", Double(item.outstandingCents) / 100))
        _dueOn = State(initialValue: item.dueOn ?? "")
        _status = State(initialValue: item.status)
        _note = State(initialValue: item.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("债权人", text: $creditor)
                TextField("本金（元）", text: $principal).keyboardType(.decimalPad)
                TextField("未偿余额（元）", text: $outstanding).keyboardType(.decimalPad)
                TextField("到期日 YYYY-MM-DD", text: $dueOn)
                Picker("状态", selection: $status) { Text("未偿还").tag("open"); Text("已还清").tag("paid"); Text("已逾期").tag("overdue"); Text("已取消").tag("cancelled") }
                TextField("备注", text: $note, axis: .vertical)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button { requestSave() } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text("保存修改").fontWeight(.semibold) }; Spacer() } }.disabled(isSaving)
            }
            .navigationTitle("编辑债务")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .confirmationDialog("确认修改这笔债务？", isPresented: $showingConfirmation, titleVisibility: .visible) {
                Button("确认写入", role: .destructive) { save() }
                Button("返回修改", role: .cancel) { }
            } message: {
                Text("修改会影响还款压力和现金预测，并留下审计记录。")
            }
        }
    }

    private func requestSave() {
        guard let p = Double(principal), p > 0, let o = Double(outstanding), o >= 0 else { errorMessage = "请输入有效金额"; return }
        guard !creditor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入债权人"; return }
        _ = p; _ = o
        errorMessage = nil
        showingConfirmation = true
    }

    private func save() {
        guard let p = Double(principal), p > 0, let o = Double(outstanding), o >= 0 else { errorMessage = "请输入有效金额"; return }
        guard !creditor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入债权人"; return }
        isSaving = true; errorMessage = nil
        Task {
            do {
                try await state.api.updateDebt(item.id, DebtUpdateRequest(creditor: creditor, principalCents: Int(p * 100), outstandingCents: Int(o * 100), dueOn: dueOn.isEmpty ? nil : dueOn, status: status, note: note.isEmpty ? nil : note))
                await state.refreshDashboard(); dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }
}

private enum EntryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

struct TasksView: View {
    @ObservedObject var state: AppState
    @State private var filter = "全部"
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("事项筛选", selection: $filter) {
                    Text("全部").tag("全部")
                    Text("待办").tag("todo")
                    Text("进行中").tag("in_progress")
                    Text("阻塞").tag("blocked")
                    Text("已完成").tag("done")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                List {
                    Section("当前事项") {
                        if filteredTasks.isEmpty {
                        Text("还没有事项。用语音告诉助理今天要推进什么。")
                            .foregroundStyle(.secondary)
                        } else {
                        ForEach(filteredTasks) { task in
                            TaskRow(task: task, state: state)
                        }
                    }
                }
            }
            }
            .navigationTitle("事项")
            .refreshable { await state.refreshDashboard() }
        }
    }

    private var filteredTasks: [FocusTask] {
        filter == "全部" ? state.tasks : state.tasks.filter { $0.status == filter }
    }
}

struct ProjectsView: View {
    @ObservedObject var state: AppState
    @State private var selected: ProjectSummary?
    var body: some View {
        NavigationStack {
            List {
                if state.projects.isEmpty {
                    Text("还没有项目。打开助理，用语音说出一个目标即可开始。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.projects) { project in
                        Button { selected = project } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(project.name).font(.headline); Spacer(); Text(localizedProjectStage(project.stage)).font(.caption).foregroundStyle(.secondary) }
                                Text(project.nextAction ?? project.objective ?? "尚未定义下一步")
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                Text("待办 \(project.openTaskCount) 项")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("项目")
            .sheet(item: $selected) { ProjectWarRoom(project: $0) }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        NavigationStack {
            Form {
                Section("安全") {
                    Label("Face ID 解锁", systemImage: "faceid")
                    Button("退出登录", role: .destructive) { state.logout() }
                }
                Section("连接") {
                    LabeledContent("服务地址", value: "luo.hsh6.com")
                    LabeledContent("状态", value: state.errorMessage == nil ? "已连接" : "需要检查")
                }
                Section("经营知识") {
                    NavigationLink("记忆库") { KnowledgeView(state: state, mode: .memories) }
                    NavigationLink("决策记录") { KnowledgeView(state: state, mode: .decisions) }
                }
                Section("关于") {
                    Text("洛浩经营台")
                    Text("现金、风险和事项规划的个人经营系统")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}

struct KnowledgeView: View {
    enum Mode: Equatable { case memories, decisions }
    @ObservedObject var state: AppState
    let mode: Mode
    @State private var showingEntry = false
    var body: some View {
        List {
            if mode == .memories {
                Section("已记录的经营信息") {
                    if state.memories.isEmpty { Text("还没有记忆。你可以在 AI 助理中说：记住这件事……").foregroundStyle(.secondary) }
                    ForEach(state.memories) { memory in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(memory.content)
                            Text("来源：\(memory.source ?? "手动记录")").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { Task { try? await state.api.archiveMemory(memory.id); await state.refreshDashboard() } } label: { Label("归档", systemImage: "archivebox") }
                        }
                    }
                }
            } else {
                Section("需要复盘的决策") {
                    if state.decisions.isEmpty { Text("还没有决策记录。重要决定可以让 AI 助理帮你留下背景和理由。").foregroundStyle(.secondary) }
                    ForEach(state.decisions) { decision in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(decision.title).font(.headline)
                            Text(decision.decision)
                            if let reviewOn = decision.reviewOn { Text("复盘日期：\(reviewOn)").font(.caption).foregroundStyle(.orange) }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
        .navigationTitle(mode == .memories ? "记忆库" : "决策记录")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingEntry = true } label: { Image(systemName: "plus") }.accessibilityLabel(mode == .memories ? "新增记忆" : "新增决策") } }
        .sheet(isPresented: $showingEntry) { if mode == .memories { MemoryEntryView(state: state) } else { DecisionEntryView(state: state) } }
        .refreshable { await state.refreshDashboard() }
    }
}

private struct MemoryEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: AppState
    @State private var content = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack { Form {
            TextField("记住什么？", text: $content, axis: .vertical).lineLimit(4...8)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            Button { save() } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text("保存记忆").fontWeight(.semibold) }; Spacer() } }.disabled(isSaving)
        }.navigationTitle("新增记忆").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } } }
    }
    private func save() {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入记忆内容"; return }
        isSaving = true; errorMessage = nil
        Task { do { try await state.api.createMemory(MemoryCreateRequest(content: content, memoryType: "note", projectId: nil, source: "manual")); await state.refreshDashboard(); dismiss() } catch { errorMessage = error.localizedDescription; isSaving = false } }
    }
}

private struct DecisionEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: AppState
    @State private var title = ""
    @State private var decision = ""
    @State private var rationale = ""
    @State private var reviewOn = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack { Form {
            TextField("决策标题", text: $title)
            TextField("决定内容", text: $decision, axis: .vertical).lineLimit(3...8)
            TextField("为什么这样决定（可选）", text: $rationale, axis: .vertical).lineLimit(3...8)
            TextField("复盘日期 YYYY-MM-DD（可选）", text: $reviewOn)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            Button { save() } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text("保存决策").fontWeight(.semibold) }; Spacer() } }.disabled(isSaving)
        }.navigationTitle("新增决策").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } } }
    }
    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !decision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请填写标题和决定内容"; return }
        isSaving = true; errorMessage = nil
        Task { do { try await state.api.createDecision(DecisionCreateRequest(projectId: nil, title: title, context: nil, decision: decision, rationale: rationale.isEmpty ? nil : rationale, reviewOn: reviewOn.isEmpty ? nil : reviewOn)); await state.refreshDashboard(); dismiss() } catch { errorMessage = error.localizedDescription; isSaving = false } }
    }
}

private struct TaskRow: View {
    let task: FocusTask
    @ObservedObject var state: AppState
    @State private var showingEdit = false
    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { try? await state.api.updateTask(task.id, status: task.status == "done" ? "todo" : "done"); await state.refreshDashboard() }
            } label: {
                Image(systemName: task.status == "done" ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.status == "done" ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.headline)
                Text(task.dueOn.map { "截止 \($0)" } ?? "未设截止日期")
                    .font(.caption).foregroundStyle(.secondary)
                if task.status == "blocked", let reason = task.blockedReason, !reason.isEmpty { Text("阻塞：\(reason)").font(.caption).foregroundStyle(.orange).lineLimit(1) }
            }
            Spacer()
            Text("\(task.score)").font(.caption.weight(.semibold)).monospacedDigit()
        }
        .contentShape(Rectangle())
        .onTapGesture { showingEdit = true }
        .sheet(isPresented: $showingEdit) { TaskEditView(state: state, task: task) }
    }
}

private struct TaskEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: AppState
    let task: FocusTask
    @State private var title: String
    @State private var status: String
    @State private var blockedReason: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(state: AppState, task: FocusTask) {
        self.state = state; self.task = task
        _title = State(initialValue: task.title)
        _status = State(initialValue: task.status)
        _blockedReason = State(initialValue: task.blockedReason ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("事项标题", text: $title)
                Picker("状态", selection: $status) {
                    Text("待办").tag("todo"); Text("进行中").tag("in_progress"); Text("阻塞").tag("blocked"); Text("已完成").tag("done"); Text("已取消").tag("cancelled")
                }
                if status == "blocked" { TextField("阻塞原因", text: $blockedReason, axis: .vertical) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button { save() } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text("保存修改").fontWeight(.semibold) }; Spacer() } }.disabled(isSaving)
            }
            .navigationTitle("编辑事项")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入事项标题"; return }
        if status == "blocked" && blockedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errorMessage = "请填写阻塞原因"; return }
        isSaving = true; errorMessage = nil
        Task {
            do {
                try await state.api.updateTask(task.id, title: title, status: status, blockedReason: status == "blocked" ? blockedReason : nil)
                await state.refreshDashboard(); dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }
}

private struct ChartView: View {
    let points: [CashflowPoint]
    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value("日期", point.date), y: .value("余额", Double(point.balanceCents) / 100))
                .foregroundStyle(.orange.opacity(0.14))
            LineMark(x: .value("日期", point.date), y: .value("余额", Double(point.balanceCents) / 100))
                .foregroundStyle(.orange)
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
    }
}

private func pageHeader(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.largeTitle.weight(.bold))
        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
    }
}

private func sectionTitle(_ title: String, detail: String?) -> some View {
    HStack {
        Text(title).font(.title3.weight(.semibold))
        Spacer()
        if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
    }
}

private func empty(_ title: String, message: String, icon: String) -> some View {
    Label { VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(message).font(.subheadline).foregroundStyle(.secondary) } } icon: { Image(systemName: icon).foregroundStyle(.orange) }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
}
