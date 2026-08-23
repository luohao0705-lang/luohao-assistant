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
                    }.padding(.horizontal).padding(.vertical, 12)
                } else if let error = state.errorMessage { ContentUnavailableView("Unable to load operating state", systemImage: "wifi.exclamationmark", description: Text(error)) } else { ProgressView().padding(.top, 80) }
            }
            .refreshable { await state.refreshDashboard() }
            .navigationTitle("Operating desk")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { showingWeeklyPlan = true } label: { Image(systemName: "calendar") }.accessibilityLabel("Weekly plan") }
                ToolbarItem(placement: .topBarTrailing) { HStack { Button { showingAssistant = true } label: { Image(systemName: "waveform") }.accessibilityLabel("Open AI assistant"); Button { state.logout() } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }.accessibilityLabel("Log out") } }
            }
            .sheet(isPresented: $showingAssistant) { AssistantView(state: state) }
            .sheet(item: $selectedProject) { ProjectWarRoom(project: $0) }
            .sheet(isPresented: $showingWeeklyPlan) { WeeklyPlanView(state: state) }
        }
    }

    private var cashflowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("45-day cash outlook", detail: state.cashflow.last.map { $0.date })
            if state.cashflow.isEmpty {
                Text("Add planned income, expenses, and debt due dates to see the outlook.").font(.subheadline).foregroundStyle(.secondary)
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
                .accessibilityLabel("Cash balance forecast for the next 45 days")
            }
        }
    }

    @ViewBuilder private func hero(_ d: DashboardSummary) -> some View {
        let lowestForecast = currency.string(from: NSNumber(value: Double(d.forecastLowestBalanceCents) / 100)) ?? "-"
        VStack(alignment: .leading, spacing: 6) {
            Text("Cash first, then action").font(.subheadline).foregroundStyle(.secondary)
            Text(currency.string(from: NSNumber(value: Double(d.cashCents) / 100)) ?? "-").font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
            Text("Available cash | lowest forecast \(lowestForecast) | \(d.forecastLowestDate)").font(.caption).foregroundStyle(d.forecastLowestBalanceCents < 0 ? .red : .secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Today's three priorities", detail: state.dailyFocus.map { "Open \($0.openCount) | overdue \($0.overdueCount)" })
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
            } else { Text("No ranked tasks yet. Ask the assistant to break down a project and review the proposal.").font(.subheadline).foregroundStyle(.secondary) }
            if let blocked = state.dailyFocus?.blocked, !blocked.isEmpty { Divider(); Label("\(blocked.count) blocked: \(blocked[0].reason)", systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange) }
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
            sectionTitle("Project war rooms", detail: "\(state.projects.count) active")
            ForEach(state.projects.prefix(4)) { project in
                Button { selectedProject = project } label: { HStack { VStack(alignment: .leading, spacing: 4) { Text(project.name).font(.headline).foregroundStyle(.primary); Text(project.nextAction ?? project.objective ?? "Define the next action").font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); VStack(alignment: .trailing, spacing: 4) { Text("\(project.openTaskCount) open").font(.caption.weight(.semibold)); Text(project.stage).font(.caption2).foregroundStyle(.secondary) } } }.buttonStyle(.plain).padding(.vertical, 6)
            }
            if state.projects.isEmpty { Text("No projects yet. Use voice to describe an objective and the assistant will draft a project and tasks.").font(.subheadline).foregroundStyle(.secondary) }
        }
    }

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 8) { sectionTitle("This week's plan", detail: state.weeklyPlan?.weekStart ?? "Not planned"); if let plan = state.weeklyPlan { if let theme = plan.theme { Text(theme).font(.headline) }; ForEach(plan.outcomes.prefix(3), id: \.self) { Text("• \($0)").font(.subheadline) } } else { Text("Ask the assistant to plan the week around projects, cash risk, and blockers.").font(.subheadline).foregroundStyle(.secondary) } }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 10) { sectionTitle("Needs your confirmation", detail: "AI never writes without approval"); ForEach(state.pendingActions) { action in HStack { VStack(alignment: .leading) { Text(action.actionType).font(.headline); Text("Proposal ready. Confirm before writing.").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { Task { await state.resolveAction(action, confirm: false) } } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).accessibilityLabel("Cancel action"); Button { Task { await state.resolveAction(action, confirm: true) } } label: { Image(systemName: "checkmark") }.buttonStyle(.borderless).foregroundStyle(.orange).accessibilityLabel("Confirm action") } .padding(.vertical, 6) } }
    }

    private func riskSection(_ flags: [String]) -> some View { VStack(alignment: .leading, spacing: 8) { sectionTitle("Risks needing attention", detail: nil); ForEach(flags, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.orange) } }.padding(14).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }
    private func sectionTitle(_ title: String, detail: String?) -> some View { HStack { Text(title).font(.title3.weight(.semibold)); Spacer(); if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) } } }
}

struct ProjectWarRoom: View {
    let project: ProjectSummary
    var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) { Text(project.name).font(.largeTitle.weight(.bold)); Text(project.objective ?? "Objective not defined").font(.body).foregroundStyle(.secondary); detail("Stage", project.stage); detail("Success criteria", project.successCriteria); detail("Key hypothesis", project.keyHypothesis); detail("Main risk", project.riskSummary); detail("Next action", project.nextAction); Divider(); Text("Task progress").font(.title2.weight(.semibold)); ForEach(project.tasks) { task in HStack { Circle().fill(task.status == "done" ? .green : .orange).frame(width: 7, height: 7); Text(task.title); Spacer(); Text("P\(task.priority)").font(.caption).foregroundStyle(.secondary) } } }.padding() }.navigationTitle("War room").navigationBarTitleDisplayMode(.inline) } }
    @ViewBuilder private func detail(_ title: String, _ value: String?) -> some View { if let value, !value.isEmpty { VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.body) } } }
}

struct WeeklyPlanView: View {
    @ObservedObject var state: AppState
    var body: some View {
        NavigationStack {
            List {
                if let plan = state.weeklyPlan {
                    Section("Theme") {
                        Text(plan.theme ?? "Not set")
                    }
                    Section("Outcomes") {
                        ForEach(plan.outcomes, id: \.self) { outcome in
                            Text(outcome)
                        }
                    }
                    Section("Priorities") {
                        ForEach(plan.priorities, id: \.self) { priority in
                            Text(priority)
                        }
                    }
                    Section("Risks") {
                        ForEach(plan.risks, id: \.self) { risk in
                            Text(risk)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No plan this week",
                        systemImage: "calendar.badge.plus",
                        description: Text("Ask the AI assistant to plan the week, then confirm the draft.")
                    )
                }
            }
            .navigationTitle("Weekly plan")
        }
    }
}
