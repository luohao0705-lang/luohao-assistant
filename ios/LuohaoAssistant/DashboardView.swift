import SwiftUI
import Charts

struct DashboardView: View {
    @ObservedObject var state: AppState
    @State private var showingAssistant = false
    @State private var selectedProject: ProjectSummary?
    @State private var showingWeeklyPlan = false
    private var currency: NumberFormatter { let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "CNY"; return f }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let d = state.dashboard {
                    VStack(alignment: .leading, spacing: 20) {
                        hero(d)
                        cashflowSection
                        dailySection
                        projectSection
                        weeklySection
                        if !state.pendingActions.isEmpty { actionSection }
                        if !d.riskFlags.isEmpty { riskSection(d.riskFlags) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                } else if let error = state.errorMessage { ContentUnavailableView("经营数据暂时无法加载", systemImage: "wifi.exclamationmark", description: Text(error)) } else { ProgressView().padding(.top, 80) }
            }
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

    private var cashflowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("未来 45 天现金走势", detail: state.cashflow.last.map { $0.date })
            if state.cashflow.isEmpty {
                Text("录入预计收入、支出和还款日期后，这里会显示现金安全边界。你也可以直接对 AI 助理说：下个月有一笔支出。").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(state.cashflow) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Balance", Double(point.balanceCents) / 100))
                        .foregroundStyle(.orange)
                        .interpolationMethod(.monotone)
                    AreaMark(x: .value("Date", point.date), y: .value("Balance", Double(point.balanceCents) / 100))
                        .foregroundStyle(.orange.opacity(0.12))
                }
                .chartYAxis { AxisMarks(position: .leading) { value in AxisGridLine(); AxisValueLabel { if let amount = value.as(Double.self) { Text(currency.string(from: NSNumber(value: amount)) ?? "-").font(.caption2) } } } }
                .frame(height: 150)
                .accessibilityLabel("未来 45 天现金余额预测")
            }
        }
    }

    @ViewBuilder private func hero(_ d: DashboardSummary) -> some View {
        let lowestForecast = currency.string(from: NSNumber(value: Double(d.forecastLowestBalanceCents) / 100)) ?? "-"
        VStack(alignment: .leading, spacing: 6) {
            Text("先看现金，再决定行动").font(.subheadline).foregroundStyle(.secondary)
            Text(currency.string(from: NSNumber(value: Double(d.cashCents) / 100)) ?? "-").font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
            Text("当前可用现金 · 预测最低 \(lowestForecast) · \(d.forecastLowestDate)").font(.caption).foregroundStyle(d.forecastLowestBalanceCents < 0 ? .red : .secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("今天最重要的三件事", detail: state.dailyFocus.map { "待办 \($0.openCount) · 逾期 \($0.overdueCount)" })
            if let focus = state.dailyFocus?.focus, !focus.isEmpty {
                ForEach(focus) { task in
                    HStack(spacing: 12) {
                        Button { Task { await complete(task) } } label: { Image(systemName: task.status == "done" ? "checkmark.circle.fill" : "circle").foregroundStyle(task.status == "done" ? .green : .secondary) }.buttonStyle(.borderless).accessibilityLabel(task.status == "done" ? "Completed" : "Mark complete")
                        Text("\(task.score)").font(.caption.weight(.semibold)).monospacedDigit().frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) { Text(task.title).font(.headline); Text(task.status + (task.dueOn.map { " | \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(.orange)
                    }.padding(.vertical, 8)
                }
            } else { Text("还没有排好优先级的事项。告诉 AI 助理你的目标，它会拆解出可执行的下一步。").font(.subheadline).foregroundStyle(.secondary) }
            if let blocked = state.dailyFocus?.blocked, !blocked.isEmpty { Divider(); Label("\(blocked.count) 项被阻塞：\(blocked[0].reason)", systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange) }
        }
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
                Button { selectedProject = project } label: { HStack { VStack(alignment: .leading, spacing: 4) { Text(project.name).font(.headline).foregroundStyle(.primary); Text(project.nextAction ?? project.objective ?? "先定义这个项目的下一步").font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); VStack(alignment: .trailing, spacing: 4) { Text("\(project.openTaskCount) 项待办").font(.caption.weight(.semibold)); Text(project.stage).font(.caption2).foregroundStyle(.secondary) } } }.buttonStyle(.plain).padding(.vertical, 6)
            }
            if state.projects.isEmpty { Text("还没有项目。用语音说出一个目标，AI 助理会帮你建立项目、路径和任务。").font(.subheadline).foregroundStyle(.secondary) }
        }
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 8) { sectionTitle("本周计划", detail: state.weeklyPlan?.weekStart ?? "尚未安排"); if let plan = state.weeklyPlan { if let theme = plan.theme { Text(theme).font(.headline) }; ForEach(plan.outcomes.prefix(3), id: \.self) { Text("· \($0)").font(.subheadline) } } else { Text("让 AI 助理结合项目、现金风险和阻塞事项，帮你安排本周重点。").font(.subheadline).foregroundStyle(.secondary) } }
    }

    private var actionSection: some View {
                        VStack(alignment: .leading, spacing: 10) { sectionTitle("等待你的确认", detail: "AI 不会未经批准写入"); ForEach(state.pendingActions) { action in HStack { VStack(alignment: .leading) { Text(action.actionType).font(.headline); Text("方案已生成，请确认后写入").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { Task { await state.resolveAction(action, confirm: false) } } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).accessibilityLabel("取消操作"); Button { Task { await state.resolveAction(action, confirm: true) } } label: { Image(systemName: "checkmark") }.buttonStyle(.borderless).foregroundStyle(.orange).accessibilityLabel("确认操作") } .padding(.vertical, 6) } }
    }

    private func riskSection(_ flags: [String]) -> some View { VStack(alignment: .leading, spacing: 8) { sectionTitle("需要关注的风险", detail: nil); ForEach(flags, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.orange) } }.padding(14).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }
    private func sectionTitle(_ title: String, detail: String?) -> some View { HStack { Text(title).font(.title3.weight(.semibold)); Spacer(); if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) } } }
}

struct ProjectWarRoom: View {
    let project: ProjectSummary
    var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) { Text(project.name).font(.largeTitle.weight(.bold)); Text(project.objective ?? "尚未定义目标").font(.body).foregroundStyle(.secondary); detail("阶段", project.stage); detail("成功标准", project.successCriteria); detail("关键假设", project.keyHypothesis); detail("主要风险", project.riskSummary); detail("下一步", project.nextAction); Divider(); Text("任务进度").font(.title2.weight(.semibold)); ForEach(project.tasks) { task in HStack { Circle().fill(task.status == "done" ? .green : .orange).frame(width: 7, height: 7); Text(task.title); Spacer(); Text("优先级 \(task.priority)").font(.caption).foregroundStyle(.secondary) } } }.padding() }.navigationTitle("项目作战室").navigationBarTitleDisplayMode(.inline) } }
    @ViewBuilder private func detail(_ title: String, _ value: String?) -> some View { if let value, !value.isEmpty { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.body) } } }
}

struct WeeklyPlanView: View {
    @ObservedObject var state: AppState
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
        }
    }
}
