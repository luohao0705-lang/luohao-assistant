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
            else { ForEach(state.accounts) { account in detailRow(account.name, account.kind, account.balanceCents, account.currency) } }
        case "流水":
            if state.transactions.isEmpty { empty("还没有流水", message: "收入和支出会在这里按日期记录。", icon: "list.bullet.rectangle") }
            else { ForEach(state.transactions.prefix(20)) { item in detailRow(item.counterparty ?? (item.kind == "income" ? "收入" : "支出"), "\(item.occurredOn) · \(item.status)", item.kind == "income" ? item.amountCents : -item.amountCents, "CNY") } }
        case "债务":
            if state.debts.isEmpty { empty("没有未偿债务", message: "新增贷款或应付款后，这里会显示还款压力。", icon: "creditcard") }
            else { ForEach(state.debts) { debt in detailRow(debt.creditor, debt.dueOn.map { "到期 \($0)" } ?? "未设到期日", debt.outstandingCents, "CNY") } }
        default:
            Text("金额明细已按账户、流水和债务分开整理。")
                .font(.subheadline).foregroundStyle(.secondary)
        }
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

struct TasksView: View {
    @ObservedObject var state: AppState
    var body: some View {
        NavigationStack {
            List {
                Section("今天") {
                    if state.tasks.isEmpty {
                        Text("还没有事项。用语音告诉助理今天要推进什么。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.tasks) { task in
                            TaskRow(task: task, state: state)
                        }
                    }
                }
            }
            .navigationTitle("事项")
            .refreshable { await state.refreshDashboard() }
        }
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
                                HStack { Text(project.name).font(.headline); Spacer(); Text(project.stage).font(.caption).foregroundStyle(.secondary) }
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

private struct TaskRow: View {
    let task: FocusTask
    @ObservedObject var state: AppState
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
            }
            Spacer()
            Text("\(task.score)").font(.caption.weight(.semibold)).monospacedDigit()
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
