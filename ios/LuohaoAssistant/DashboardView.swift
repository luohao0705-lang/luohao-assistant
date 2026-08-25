import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var state: AppState
    @State private var showingAssistant = false
    @State private var selectedProject: ProjectSummary?
    @State private var showingWeeklyPlan = false
    @State private var selectedPlanningWindow = 7
    private var currency: NumberFormatter { let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "CNY"; return f }

    var body: some View {
        NavigationStack {
            ScrollView {
                if state.dashboard != nil {
                    VStack(alignment: .leading, spacing: 20) {
                        morningBriefSection
                        dailySection
                        planningWindowSection
                        projectSection
                        weeklySection
                        if !state.pendingActions.isEmpty { actionSection }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                } else if let error = state.errorMessage { ContentUnavailableView("经营数据暂时无法加载", systemImage: "wifi.exclamationmark", description: Text(error)) } else { ProgressView().padding(.top, 80) }
            }
            .scrollIndicators(.hidden)
            .background(LuohaoDesign.canvas)
            .refreshable { await state.refreshDashboard() }
            .navigationTitle("经营驾驶舱")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { showingWeeklyPlan = true } label: { Image(systemName: "calendar") }.accessibilityLabel("本周计划") }
                ToolbarItem(placement: .topBarTrailing) { HStack { Button { showingAssistant = true } label: { Image(systemName: "waveform") }.accessibilityLabel("打开 AI 助理"); Button { state.logout() } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }.accessibilityLabel("退出登录") } }
            }
            .sheet(isPresented: $showingAssistant) { AssistantView(state: state) }
            .sheet(item: $selectedProject) { ProjectWarRoom(project: $0) }
            .sheet(isPresented: $showingWeeklyPlan) { WeeklyPlanView(state: state) }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var morningBriefSection: some View {
        if let brief = state.morningBrief {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("今日经营简报").font(.title3.weight(.semibold))
                    Spacer()
                    Text(brief.date).font(.caption).foregroundStyle(.secondary)
                }
                Text(brief.summary).font(.subheadline).foregroundStyle(.primary)
                adviceGroup(title: "人生建议", icon: "figure.mind.and.body", items: brief.lifeAdvice)
                adviceGroup(title: "财务建议", icon: "yensign.circle", items: brief.financeAdvice)
                adviceGroup(title: "工作建议", icon: "checklist", items: brief.workAdvice)
            }
            .surfaceCard(padding: 16)
        }
    }

    private func adviceGroup(title: String, icon: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            ForEach(items, id: \.self) { item in
                Text(item).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cashflowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("未来 45 天现金走势", detail: state.cashflow.last.map { $0.date })
            if state.cashflow.isEmpty {
                Text("录入预计收入、支出和还款日期后，这里会显示现金安全边界。你也可以直接对 AI 助理说：下个月有一笔支出。").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(state.cashflow) { point in
                    LineMark(x: .value("日期", point.date), y: .value("余额", Double(point.balanceCents) / 100))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("日期", point.date), y: .value("余额", Double(point.balanceCents) / 100))
                        .foregroundStyle(.orange.opacity(0.12))
                }
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisValueLabel { if let amount = value.as(Double.self) { Text(currency.string(from: NSNumber(value: amount)) ?? "-").font(.caption2) } } } }
                .frame(height: 150)
                .accessibilityLabel("未来 45 天现金余额预测")
            }
        }
        .surfaceCard(padding: 16)
    }

    @ViewBuilder private func hero(_ d: DashboardSummary) -> some View {
        let lowestForecast = currency.string(from: NSNumber(value: Double(d.forecastLowestBalanceCents) / 100)) ?? "-"
        VStack(alignment: .leading, spacing: 6) {
            Text("先看现金，再决定行动").font(.subheadline).foregroundStyle(.secondary)
            Text(d.cashRegistered ? (currency.string(from: NSNumber(value: Double(d.cashCents) / 100)) ?? "-") : "未登记").font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
            if d.cashRegistered && d.forecastLowestBalanceCents < 0 {
                let gap = currency.string(from: NSNumber(value: Double(-d.forecastLowestBalanceCents) / 100)) ?? "-"
                Text("未来预测窗口内最低现金余额为 \(lowestForecast)，发生在 \(d.forecastLowestDate)；预计现金缺口为 \(gap)。")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if d.cashRegistered {
                Text("未来预测窗口内最低现金余额为 \(lowestForecast)，发生在 \(d.forecastLowestDate)。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("尚未登记当前现金，现金缺口预测暂不计算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        }
    }

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("今天最重要的三件事", detail: state.dailyFocus.map { "待办 \($0.openCount) · 逾期 \($0.overdueCount)" })
            let focus = (state.dailyFocus?.focus ?? []).filter { !isFinancialTask($0) }
            if !focus.isEmpty {
                ForEach(focus) { task in
                    HStack(spacing: 12) {
                        Button { Task { await complete(task) } } label: { Image(systemName: task.status == "done" ? "checkmark.circle.fill" : "circle").foregroundStyle(task.status == "done" ? .green : .secondary) }.buttonStyle(.borderless).accessibilityLabel(task.status == "done" ? "已完成" : "标记完成")
                        Text("\(task.score)").font(.caption.weight(.semibold)).monospacedDigit().frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) { Text(task.title).font(.headline); Text(localizedTaskStatus(task.status) + (task.dueOn.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(.orange)
                    }.padding(.vertical, 8)
                }
            } else { Text("还没有排好优先级的事项。告诉 AI 助理你的目标，它会拆解出可执行的下一步。").font(.subheadline).foregroundStyle(.secondary) }
            if let blocked = state.dailyFocus?.blocked, !blocked.isEmpty { Divider(); Label("\(blocked.count) 项被阻塞：\(blocked[0].reason)", systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange) }
        }
        .surfaceCard(padding: 16)
    }

    private var planningWindowSection: some View {
        let windows = [3, 7, 30]
        let items = planningItems(for: selectedPlanningWindow)
        return VStack(alignment: .leading, spacing: 10) {
            sectionTitle("近期规划", detail: "按事项截止日期")
            HStack(spacing: 8) {
                ForEach(windows, id: \.self) { days in
                    let count = planningItems(for: days).count
                    Button { selectedPlanningWindow = days } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(days == 30 ? "近1个月" : "近\(days)天")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("\(count) 件")
                                .font(.headline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(count > 0 ? .orange : .primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(selectedPlanningWindow == days ? LuohaoDesign.accentTint : LuohaoDesign.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selectedPlanningWindow == days ? LuohaoDesign.accent.opacity(0.45) : LuohaoDesign.hairline, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            if items.isEmpty {
                Text("这段时间没有已安排截止日期的事项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(items.prefix(5)) { task in
                    HStack(spacing: 9) {
                        Circle().fill(task.status == "done" ? .green : .orange).frame(width: 7, height: 7)
                        Text(task.title).font(.subheadline).lineLimit(1)
                        Spacer()
                        Text(task.dueOn ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .surfaceCard(padding: 16)
    }

    private func planningItems(for days: Int) -> [FocusTask] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return state.tasks
            .filter { task in
                guard !isFinancialTask(task), task.status != "done", let dueOn = task.dueOn,
                      let dueDate = date(from: dueOn) else { return false }
                let distance = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: dueDate)).day ?? 999
                return distance >= 0 && distance <= days
            }
            .sorted { ($0.dueOn ?? "9999") < ($1.dueOn ?? "9999") }
    }

    private func date(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }

    private func complete(_ task: FocusTask) async {
        do {
            try await state.api.updateTask(task.id, status: task.status == "done" ? "todo" : "done")
            await state.refreshDashboard()
        } catch { state.errorMessage = error.localizedDescription }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("项目作战室", detail: "\(state.projects.count) 个项目")
            ForEach(state.projects.prefix(4)) { project in
                Button { selectedProject = project } label: { HStack { VStack(alignment: .leading, spacing: 4) { Text(project.name).font(.headline).foregroundStyle(.primary); Text(project.nextAction ?? project.objective ?? "先定义这个项目的下一步").font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); VStack(alignment: .trailing, spacing: 4) { Text("\(project.openTaskCount) 项待办").font(.caption.weight(.semibold)); Text(localizedProjectStage(project.stage)).font(.caption2).foregroundStyle(.secondary) } } }.buttonStyle(.plain).padding(.vertical, 6)
            }
            if state.projects.isEmpty { Text("还没有项目。用语音说出一个目标，AI 助理会帮你建立项目、路径和任务。").font(.subheadline).foregroundStyle(.secondary) }
        }
        .surfaceCard(padding: 16)
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 8) { sectionTitle("本周计划", detail: state.weeklyPlan?.weekStart ?? "尚未安排"); if let plan = state.weeklyPlan { if let theme = plan.theme { Text(theme).font(.headline) }; ForEach(plan.outcomes.prefix(3), id: \.self) { Text("· \($0)").font(.subheadline) } } else { Text("让 AI 助理结合项目和阻塞事项，帮你安排本周重点。").font(.subheadline).foregroundStyle(.secondary) } }
            .surfaceCard(padding: 16)
    }

    private var actionSection: some View {
                        VStack(alignment: .leading, spacing: 10) { sectionTitle("等待你的确认", detail: "AI 不会未经批准写入"); ForEach(state.pendingActions) { action in HStack { VStack(alignment: .leading) { Text(localizedActionType(action.actionType)).font(.headline); Text("方案已生成，请确认后写入").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { Task { await state.resolveAction(action, confirm: false) } } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).accessibilityLabel("取消操作"); Button { Task { await state.resolveAction(action, confirm: true) } } label: { Image(systemName: "checkmark") }.buttonStyle(.borderless).foregroundStyle(.orange).accessibilityLabel("确认操作") } .padding(.vertical, 6) } }
    }

    private func riskSection(_ flags: [String]) -> some View { VStack(alignment: .leading, spacing: 8) { sectionTitle("需要关注的风险", detail: nil); ForEach(flags, id: \.self) { Text(localizedRiskFlag($0)).font(.subheadline).foregroundStyle(.orange) } }.padding(14).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }

    private func localizedRiskFlag(_ value: String) -> String {
        if value.hasPrefix("Cash gap forecast on ") { return "预测现金缺口：\(value.replacingOccurrences(of: "Cash gap forecast on ", with: ""))" }
        if value == "Debt due within 30 days exceeds current cash" { return "未来 30 天到期债务超过当前现金" }
        if value.hasPrefix("Overdue expected income: ") { return "逾期预计收入：\(value.replacingOccurrences(of: "Overdue expected income: ", with: ""))" }
        if value.hasPrefix("Blocked work items requiring owner action: ") { return "有待你处理的阻塞事项：\(value.replacingOccurrences(of: "Blocked work items requiring owner action: ", with: ""))" }
        return value
    }
    private func sectionTitle(_ title: String, detail: String?) -> some View { HStack(alignment: .firstTextBaseline, spacing: 12) { Text(title).font(.headline.weight(.semibold)); Spacer(minLength: 8); if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) } } }
}

struct ProjectWarRoom: View {
    let project: ProjectSummary
    var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) { Text(project.name).font(.largeTitle.weight(.bold)); Text(project.objective ?? "尚未定义目标").font(.body).foregroundStyle(.secondary); detail("阶段", localizedProjectStage(project.stage)); detail("状态", localizedProjectStatus(project.status)); detail("成功标准", project.successCriteria); detail("关键假设", project.keyHypothesis); detail("主要风险", project.riskSummary); detail("下一步", project.nextAction); Divider(); Text("任务进度").font(.title2.weight(.semibold)); ForEach(project.tasks) { task in HStack { Circle().fill(task.status == "done" ? .green : .orange).frame(width: 7, height: 7); Text(task.title); Spacer(); Text("\(localizedTaskStatus(task.status)) · 优先级 \(task.priority)").font(.caption).foregroundStyle(.secondary) } } }.padding() }.navigationTitle("项目作战室").navigationBarTitleDisplayMode(.inline) } }
    @ViewBuilder private func detail(_ title: String, _ value: String?) -> some View { if let value, !value.isEmpty { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.body) } } }
}

struct WeeklyPlanView: View {
    @ObservedObject var state: AppState
    @State private var showingEditor = false
    var body: some View {
        NavigationStack {
            List {
                if let plan = state.weeklyPlan {
                    Section("本周主题") {
                        Text(plan.theme ?? "尚未设定")
                    }
                    Section("目标结果") {
                        ForEach(plan.outcomes, id: \.self) { outcome in
                            Text(outcome)
                        }
                    }
                    Section("优先事项") {
                        ForEach(plan.priorities, id: \.self) { priority in
                            Text(priority)
                        }
                    }
                    Section("风险提醒") {
                        ForEach(plan.risks, id: \.self) { risk in
                            Text(risk)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "本周还没有计划",
                        systemImage: "calendar.badge.plus",
                        description: Text("让 AI 助理结合项目、现金风险和阻塞事项，帮你安排本周重点。")
                    )
                }
            }
            .navigationTitle("本周计划")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingEditor = true } label: { Image(systemName: "pencil") }.accessibilityLabel("编辑本周计划") } }
            .sheet(isPresented: $showingEditor) { WeeklyPlanEditorView(state: state) }
        }
    }
}

private struct WeeklyPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: AppState
    @State private var theme: String
    @State private var outcomes: String
    @State private var priorities: String
    @State private var risks: String
    @State private var reviewNotes: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(state: AppState) {
        self.state = state
        _theme = State(initialValue: state.weeklyPlan?.theme ?? "")
        _outcomes = State(initialValue: state.weeklyPlan?.outcomes.joined(separator: "\n") ?? "")
        _priorities = State(initialValue: state.weeklyPlan?.priorities.joined(separator: "\n") ?? "")
        _risks = State(initialValue: state.weeklyPlan?.risks.joined(separator: "\n") ?? "")
        _reviewNotes = State(initialValue: state.weeklyPlan?.reviewNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("本周主题", text: $theme)
                TextField("目标结果（每行一项）", text: $outcomes, axis: .vertical).lineLimit(3...8)
                TextField("优先事项（每行一项）", text: $priorities, axis: .vertical).lineLimit(3...8)
                TextField("风险提醒（每行一项）", text: $risks, axis: .vertical).lineLimit(3...8)
                TextField("复盘备注", text: $reviewNotes, axis: .vertical).lineLimit(2...6)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button { save() } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text("保存计划").fontWeight(.semibold) }; Spacer() } }.disabled(isSaving)
            }
            .navigationTitle("编辑本周计划")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func save() {
        let outcomeItems = lines(outcomes)
        let priorityItems = lines(priorities)
        guard !outcomeItems.isEmpty, !priorityItems.isEmpty else { errorMessage = "至少填写一项目标结果和一项优先事项"; return }
        isSaving = true; errorMessage = nil
        Task {
            do {
                try await state.api.saveWeeklyPlan(WeeklyPlanCreateRequest(weekStart: weekStart(), theme: theme.isEmpty ? nil : theme, outcomes: Array(outcomeItems.prefix(5)), priorities: Array(priorityItems.prefix(8)), risks: Array(lines(risks).prefix(8)), reviewNotes: reviewNotes.isEmpty ? nil : reviewNotes))
                await state.refreshDashboard(); dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func weekStart() -> String {
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: Date())
        let daysFromMonday = (weekday + 5) % 7
        let date = calendar.date(byAdding: .day, value: -daysFromMonday, to: Date()) ?? Date()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: date)
    }
}
