import SwiftUI
import Charts

struct AppShellView: View {
    @ObservedObject var state: AppState
    @State private var selection = 0
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $selection) {
            AssistantView(state: state)
                .tabItem { Label("助理", systemImage: "waveform") }
                .tag(0)
            DashboardView(state: state)
                .tabItem { Label("总览", systemImage: "square.grid.2x2") }
                .tag(1)
            FinanceView(state: state)
                .tabItem { Label("财务", systemImage: "yensign.circle") }
                .tag(2)
            TasksView(state: state)
                .tabItem { Label("事项", systemImage: "checklist") }
                .tag(3)
            ProjectsView(state: state)
                .tabItem { Label("项目", systemImage: "rectangle.3.group") }
                .tag(4)
        }
        .tint(.orange)
        .background(LuohaoDesign.canvas.ignoresSafeArea())
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(LuohaoDesign.card, for: .tabBar)
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
    @State private var showingEntry = false
    @State private var entryType = "收支"
    @State private var selectedTransaction: TransactionSummary?
    @State private var selectedDebt: DebtSummary?
    @State private var selectedDueDate: Date?
    @State private var selectedPaymentWindow: Int? = 7
    @State private var expandedOwner: String?
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
                    pageHeader("财务中枢", subtitle: "先看现金安全，再安排每一笔还款")
                    if state.dashboard == nil, let error = state.errorMessage {
                        DataStatusBanner(message: error, retry: { await state.refreshDashboard() })
                    }
                    if state.financeDataUnavailable {
                        DataStatusBanner(message: "财务明细接口暂时不可用，请检查服务器版本或网络。", retry: { await state.refreshDashboard() })
                    }
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

                    PageSectionHeader(title: "近期要还", detail: "从今天起滚动计算，跨月也会显示")
                    paymentWindowSection

                    PageSectionHeader(title: "还款日历", detail: "点日期查看当天应还")
                    if state.debts.isEmpty {
                        empty("还没有债务记录", message: "通过语音告诉助理债权人、金额和还款日期。", icon: "calendar")
                    } else {
                        DebtCalendarSection(debts: state.debts, selectedDate: $selectedDueDate)
                    }

                    PageSectionHeader(title: "按人查看", detail: "每位归属人的未偿金额")
                    ownerSection

                    if state.debts.contains(where: { $0.outstandingCents > 0 && $0.dueOn == nil }) {
                        Label("有 \(state.debts.filter { $0.outstandingCents > 0 && $0.dueOn == nil }.count) 笔债务尚未设置还款日期", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                    }

                    PageSectionHeader(title: "现金预测", detail: "未来 45 天")
                    if state.cashflow.isEmpty {
                        empty("还没有现金预测", message: "通过语音告诉助理预计收入、支出或还款日期。", icon: "chart.xyaxis.line")
                    } else { cashflowMiniChart }

                    PageSectionHeader(title: "账户与流水", detail: nil)
                    accountAndTransactionSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(LuohaoDesign.canvas)
            .navigationTitle("财务")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { entryType = "收支"; showingEntry = true } label: { Label("新增记录", systemImage: "plus") }
                        Button { entryType = "账户"; showingEntry = true } label: { Label("新增账户", systemImage: "building.columns") }
                        Button { entryType = "债务"; showingEntry = true } label: { Label("新增债务", systemImage: "calendar.badge.plus") }
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
        let displayedCents = title.contains("债") ? displayedOutstandingDebtCents : cents
        let footnote = title.contains("债") && fixedAssetOutstandingCents > 0 ? "完整合计 \(formatCurrency(fullOutstandingDebtCents))，含房贷、车贷" : nil
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(currency.string(from: NSNumber(value: Double(displayedCents) / 100)) ?? "¥0")
                .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(color)
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LuohaoDesign.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(LuohaoDesign.hairline, lineWidth: 1)
        }
    }

    private var cashflowMiniChart: some View {
        ChartView(points: state.cashflow)
            .frame(height: 170)
            .padding(12)
            .background(LuohaoDesign.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LuohaoDesign.hairline, lineWidth: 1)
            }
    }

    private var upcomingDebtSection: some View {
        let items = state.debts
            .filter { $0.outstandingCents > 0 && $0.dueOn != nil }
            .sorted { ($0.dueOn ?? "9999") < ($1.dueOn ?? "9999") }
        return Group {
            if items.isEmpty {
                empty("暂无已安排日期的还款", message: "给债务补充到期日后，这里会自动提醒。", icon: "checkmark.circle")
            } else {
                VStack(spacing: 0) {
                    ForEach(items.prefix(8)) { debt in
                        if debt.id > 0 {
                            Button { selectedDebt = debt } label: { upcomingDebtRow(debt) }
                                .buttonStyle(.plain)
                        } else {
                            upcomingDebtRow(debt)
                        }
                        if debt.id != items.prefix(8).last?.id { Divider() }
                    }
                }
                .surfaceCard(padding: 12, radius: 14)
            }
        }
    }

    private var paymentWindowSection: some View {
        let windows = [3, 7, 15, 30]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(windows, id: \.self) { days in
                    Button { selectedPaymentWindow = days } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("近\(days)天")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(formatCurrency(paymentTotal(within: days)))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                                .foregroundStyle(paymentTotal(within: days) > 0 ? LuohaoDesign.accent : .primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .background(selectedPaymentWindow == days ? LuohaoDesign.accentTint : LuohaoDesign.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selectedPaymentWindow == days ? LuohaoDesign.accent.opacity(0.45) : LuohaoDesign.hairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("近\(days)天本期应还 \(formatCurrency(paymentTotal(within: days)))")
                }
            }
            if let selectedPaymentWindow {
                let items = monthlyPaymentItems.filter { daysBetweenTodayAnd($0.date) <= selectedPaymentWindow }
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("近\(selectedPaymentWindow)天明细")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(formatCurrency(items.reduce(0) { $0 + $1.paymentCents }))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.bottom, 8)
                    if items.isEmpty {
                        Text("这段时间没有已记录的月供")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(items) { item in
                            Button { if item.debt.id > 0 { selectedDebt = item.debt } } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.debt.creditor)
                                            .font(.subheadline.weight(.medium))
                                        Text("\(shortDate(item.date)) · 本期月供")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(formatCurrency(item.paymentCents))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                    if item.debt.id > 0 {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            if item.id != items.last?.id { Divider() }
                        }
                    }
                }
                .padding(12)
                .background(LuohaoDesign.accentTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            let missingCount = state.debts.filter { $0.outstandingCents > 0 && $0.monthlyPaymentCents == nil }.count
            if missingCount > 0 {
                Label("\(missingCount) 笔债务尚未记录月供，未计入上方应还金额", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct MonthlyPaymentItem: Identifiable {
        let debt: DebtSummary
        let date: Date
        let paymentCents: Int
        var id: String { "\(debt.id)-\(date.timeIntervalSince1970)" }
    }

    private var monthlyPaymentItems: [MonthlyPaymentItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let horizon = calendar.date(byAdding: .day, value: 30, to: today) ?? today
        let months = [
            calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: calendar.component(.month, from: today), day: 1))!,
            calendar.date(byAdding: .month, value: 1, to: today)!
        ]
        return state.debts.flatMap { debt -> [MonthlyPaymentItem] in
            guard debt.outstandingCents > 0, let paymentCents = debt.monthlyPaymentCents, paymentCents > 0 else { return [] }
            let day = debt.paymentDay ?? parseDate(debt.dueOn).map { calendar.component(.day, from: $0) }
            guard let day else { return [] }
            return months.compactMap { monthStart in
                let maxDay = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? day
                guard let date = calendar.date(from: DateComponents(year: calendar.component(.year, from: monthStart), month: calendar.component(.month, from: monthStart), day: min(day, maxDay))), date >= today, date <= horizon else { return nil }
                return MonthlyPaymentItem(debt: debt, date: date, paymentCents: paymentCents)
            }
        }
        .sorted { $0.date == $1.date ? $0.debt.creditor < $1.debt.creditor : $0.date < $1.date }
    }

    private func paymentTotal(within days: Int) -> Int {
        monthlyPaymentItems.filter { daysBetweenTodayAnd($0.date) <= days }.reduce(0) { $0 + $1.paymentCents }
    }

    private func daysBetweenTodayAnd(_ date: Date) -> Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? Int.max
    }

    private func upcomingDebtRow(_ debt: DebtSummary) -> some View {
        let due = parseDate(debt.dueOn)
        let isOverdue = due.map { Calendar.current.startOfDay(for: $0) < Calendar.current.startOfDay(for: Date()) } ?? false
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(debt.creditor).font(.headline)
                Text(due.map { dueLabel($0) } ?? "未设还款日")
                    .font(.caption).foregroundStyle(isOverdue ? .red : .secondary)
            }
            Spacer()
            Text(formatCurrency(debt.outstandingCents))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .foregroundStyle(isOverdue ? .red : .primary)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 9)
    }

    private var creditorSection: some View {
        let groups = creditorGroups
        return Group {
            if groups.isEmpty {
                empty("还没有债权人", message: "每笔债务保存后会自动按债权人归类。", icon: "person.2")
            } else {
                VStack(spacing: 0) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(group.creditor).font(.headline)
                                Spacer()
                                Text(formatCurrency(group.outstandingCents)).font(.headline.weight(.semibold)).monospacedDigit()
                            }
                            HStack(spacing: 14) {
                                Label("本金 \(formatCurrency(group.principalCents))", systemImage: "doc.text")
                                if let due = group.earliestDue { Label("最近 \(shortDate(due))", systemImage: "calendar") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let debt = group.debts.first(where: { $0.id > 0 }) { selectedDebt = debt }
                        }
                        .padding(.vertical, 11)
                        if group.id != groups.last?.id { Divider() }
                    }
                }
                .surfaceCard(padding: 12, radius: 14)
            }
        }
    }

    private var ownerSection: some View {
        let groups = ownerGroups
        return Group {
            if groups.isEmpty {
                empty("暂无债务归属人", message: "每笔债务保存后会按登记信息归类。", icon: "person.2")
            } else {
                VStack(spacing: 0) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 9) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedOwner = expandedOwner == group.owner ? nil : group.owner
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.owner).font(.headline)
                                        Text("\(group.debts.count) 笔债务 · 本金 \(formatCurrency(group.principalCents))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if group.fixedAssetCents > 0 {
                                            Text("完整合计 \(formatCurrency(group.fullOutstandingCents))，含房贷、车贷")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.8)
                                        }
                                    }
                                    Spacer()
                                    Text(formatCurrency(group.outstandingCents))
                                        .font(.headline.weight(.semibold))
                                        .monospacedDigit()
                                    Image(systemName: expandedOwner == group.owner ? "chevron.up" : "chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if expandedOwner == group.owner {
                                VStack(spacing: 0) {
                                    ForEach(group.debts) { debt in
                                        Button {
                                            if debt.id > 0 { selectedDebt = debt }
                                        } label: {
                                            HStack(spacing: 8) {
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(debt.creditor).font(.subheadline.weight(.medium))
                                                    Text(debt.monthlyPaymentCents.map { "月供 \(formatCurrency($0))" } ?? "月供未记录")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text(formatCurrency(debt.outstandingCents))
                                                    .font(.subheadline.weight(.semibold))
                                                    .monospacedDigit()
                                                if debt.id > 0 {
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.tertiary)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                            .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.plain)
                                        if debt.id != group.debts.last?.id { Divider() }
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 11)
                        if group.id != groups.last?.id { Divider() }
                    }
                }
                .surfaceCard(padding: 12, radius: 14)
            }
        }
    }

    @ViewBuilder private var accountAndTransactionSection: some View {
        if state.accounts.isEmpty && state.transactions.isEmpty {
            empty("还没有账户或流水", message: "账户、收入和支出会在这里按来源整理。", icon: "list.bullet.rectangle")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(state.accounts) { account in
                    HStack {
                        Label(account.name, systemImage: "building.columns")
                        Spacer()
                        Text(formatCurrency(account.balanceCents)).monospacedDigit()
                    }.padding(.vertical, 8)
                }
                if !state.accounts.isEmpty && !state.transactions.isEmpty { Divider().padding(.vertical, 4) }
                ForEach(state.transactions.prefix(8)) { item in
                    Button { selectedTransaction = item } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.counterparty ?? (item.kind == "income" ? "收入" : "支出")).font(.subheadline.weight(.medium))
                                Text("\(item.occurredOn) · \(item.status == "paid" ? "已支付" : "已确认")").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatCurrency(item.kind == "income" ? item.amountCents : -item.amountCents)).monospacedDigit()
                                .foregroundStyle(item.kind == "income" ? .green : .primary)
                        }
                    }.buttonStyle(.plain).padding(.vertical, 7)
                }
            }
            .surfaceCard(padding: 14, radius: 14)
        }
    }

    private struct OwnerGroup: Identifiable {
        let owner: String
        let debts: [DebtSummary]
        var id: String { owner }
        var creditor: String { owner }
        var principalCents: Int { debts.reduce(0) { $0 + $1.principalCents } }
        var fullOutstandingCents: Int { debts.reduce(0) { $0 + $1.outstandingCents } }
        var fixedAssetCents: Int {
            debts.filter { $0.creditor.contains("房贷") || $0.creditor.contains("车贷") }
                .reduce(0) { $0 + $1.outstandingCents }
        }
        var outstandingCents: Int { max(0, fullOutstandingCents - fixedAssetCents) }
        var earliestDue: Date? {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
            return debts.compactMap { $0.dueOn.flatMap { formatter.date(from: $0) } }.min()
        }
    }

    private var ownerGroups: [OwnerGroup] {
        Dictionary(grouping: state.debts.filter { $0.outstandingCents > 0 }, by: ownerName(for:))
            .map { OwnerGroup(owner: $0.key, debts: $0.value.sorted { ($0.dueOn ?? "9999") < ($1.dueOn ?? "9999") }) }
            .sorted { $0.outstandingCents > $1.outstandingCents }
    }

    private var creditorGroups: [OwnerGroup] { ownerGroups }

    private var fullOutstandingDebtCents: Int {
        state.debts.filter { $0.outstandingCents > 0 }.reduce(0) { $0 + $1.outstandingCents }
    }

    private var fixedAssetOutstandingCents: Int {
        state.debts.filter { debt in
            debt.outstandingCents > 0 && (debt.creditor.contains("房贷") || debt.creditor.contains("车贷"))
        }.reduce(0) { $0 + $1.outstandingCents }
    }

    private var displayedOutstandingDebtCents: Int {
        max(0, fullOutstandingDebtCents - fixedAssetOutstandingCents)
    }

    private func ownerName(for debt: DebtSummary) -> String {
        let text = debt.note ?? ""
        if text.contains("老婆") { return "老婆" }
        if text.contains("合伙人") { return "合伙人" }
        if text.contains("父亲") || text.contains("爸爸") { return "父亲" }
        return "未分类"
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }

    private func formatCurrency(_ cents: Int) -> String {
        currency.string(from: NSNumber(value: Double(cents) / 100)) ?? "¥0"
    }

    private func dueLabel(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days < 0 { return "已逾期 \(-days) 天 · \(shortDate(date))" }
        if days == 0 { return "今天还款" }
        if days == 1 { return "明天还款" }
        return "\(days) 天后 · \(shortDate(date))"
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "M月d日"; formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

private struct DebtCalendarSection: View {
    let debts: [DebtSummary]
    @Binding var selectedDate: Date?
    @State private var month = Date()
    private let calendar = Calendar(identifier: .gregorian)
    private let weekdays = ["一", "二", "三", "四", "五", "六", "日"]

    private var monthStart: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }
    private var monthDays: [Date] {
        let offset = (calendar.component(.weekday, from: monthStart) + 5) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: monthStart) }
    }
    private var grouped: [Date: [DebtSummary]] {
        Dictionary(grouping: debts.filter { $0.outstandingCents > 0 }) { debt in
            guard let date = paymentDate(for: debt) else { return Date.distantFuture }
            return calendar.startOfDay(for: date)
        }
    }
    private var selectedDebts: [DebtSummary] {
        guard let selectedDate else { return [] }
        return grouped[calendar.startOfDay(for: selectedDate)] ?? []
    }
    private var selectedTotal: Int { selectedDebts.reduce(0) { $0 + ($1.monthlyPaymentCents ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("上个月")
                Spacer()
                Text(monthTitle).font(.headline.weight(.semibold))
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("下个月")
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(weekdays, id: \.self) { Text($0).font(.caption2.weight(.medium)).foregroundStyle(.secondary) }
                ForEach(monthDays, id: \.self) { day in calendarDay(day) }
            }

            if let selectedDate, !selectedDebts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(selectedDate.formatted(.dateTime.month().day())) 应还").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(format(selectedTotal)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    ForEach(selectedDebts) { debt in
                        HStack {
                            Text(debt.creditor)
                            Spacer()
                            Text(debt.monthlyPaymentCents.map(format) ?? "月供未记录").monospacedDigit()
                        }
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(LuohaoDesign.accentTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Label(selectedDate == nil ? "选择有标记的日期查看应还明细" : "当天没有待还款项", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .surfaceCard(padding: 14, radius: 14)
        .onAppear {
            if selectedDate == nil { selectedDate = nextDateInMonth() }
        }
    }

    private func calendarDay(_ date: Date) -> some View {
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let key = calendar.startOfDay(for: date)
        let hasDebt = grouped[key]?.isEmpty == false
        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let isToday = calendar.isDateInToday(date)
        return Button {
            selectedDate = hasDebt ? date : nil
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: date))").font(.caption.weight(isToday ? .bold : .regular))
                Circle().fill(hasDebt ? LuohaoDesign.accent : .clear).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .foregroundStyle(inMonth ? (isSelected ? Color.white : Color.primary) : Color.secondary.opacity(0.45))
            .background(isSelected ? LuohaoDesign.accent : (isToday ? LuohaoDesign.accentTint : .clear), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!inMonth)
        .accessibilityLabel("\(date.formatted(.dateTime.month().day()))\(hasDebt ? " 有待还款" : "")")
    }

    private var monthTitle: String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy年M月"; formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: month)
    }

    private func moveMonth(_ value: Int) {
        if let next = calendar.date(byAdding: .month, value: value, to: month) { month = next; selectedDate = nextDateInMonth() }
    }

    private func nextDateInMonth() -> Date? {
        grouped.keys.filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }.min()
    }

    private func parse(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }

    private func paymentDate(for debt: DebtSummary) -> Date? {
        let base = monthStart
        let day = debt.paymentDay ?? debt.dueOn.flatMap { parse($0) }.map { calendar.component(.day, from: $0) }
        guard let day else { return nil }
        let maxDay = calendar.range(of: .day, in: .month, for: base)?.count ?? day
        return calendar.date(from: DateComponents(year: calendar.component(.year, from: base), month: calendar.component(.month, from: base), day: min(day, maxDay)))
    }

    private func format(_ cents: Int) -> String {
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = "CNY"
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "¥0"
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
    @State private var monthlyPayment = ""
    @State private var paymentDay = ""
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
                    TextField("每月还款金额（元，可选）", text: $monthlyPayment).keyboardType(.decimalPad)
                    TextField("每月还款日（1-31，可选）", text: $paymentDay).keyboardType(.numberPad)
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
                    let payment = Double(monthlyPayment).map { Int($0 * 100) }
                    let day = Int(paymentDay)
                    try await state.api.createDebt(DebtCreateRequest(creditor: creditor, principalCents: Int(value * 100), outstandingCents: Int(outstanding * 100), dueOn: dueOn.isEmpty ? nil : dueOn, monthlyPaymentCents: payment, paymentDay: day, interestRate: nil, note: note.isEmpty ? nil : note))
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
    @State private var monthlyPayment: String
    @State private var paymentDay: String
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
        _monthlyPayment = State(initialValue: item.monthlyPaymentCents.map { String(format: "%.2f", Double($0) / 100) } ?? "")
        _paymentDay = State(initialValue: item.paymentDay.map(String.init) ?? "")
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
                TextField("每月还款金额（元，可选）", text: $monthlyPayment).keyboardType(.decimalPad)
                TextField("每月还款日（1-31，可选）", text: $paymentDay).keyboardType(.numberPad)
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
                let payment = Double(monthlyPayment).map { Int($0 * 100) }
                let day = Int(paymentDay)
                try await state.api.updateDebt(item.id, DebtUpdateRequest(creditor: creditor, principalCents: Int(p * 100), outstandingCents: Int(o * 100), dueOn: dueOn.isEmpty ? nil : dueOn, monthlyPaymentCents: payment, paymentDay: day, status: status, note: note.isEmpty ? nil : note))
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
    @State private var showingCreate = false
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
            .scrollContentBackground(.hidden)
            .background(LuohaoDesign.canvas)
            .navigationTitle("事项")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("新建事项") } }
            .sheet(isPresented: $showingCreate) { TaskFormView(state: state) }
            .refreshable { await state.refreshDashboard() }
        }
    }

    private var filteredTasks: [FocusTask] {
        filter == "全部" ? state.tasks : state.tasks.filter { $0.status == filter }
    }
}

private struct TaskFormView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: AppState
    @State private var title = ""
    @State private var description = ""
    @State private var dueOn = ""
    @State private var priority = 3
    @State private var impact = 3
    @State private var urgency = 3
    @State private var estimatedMinutes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("事项标题", text: $title)
                TextField("说明（可选）", text: $description, axis: .vertical).lineLimit(2...6)
                TextField("截止日期 YYYY-MM-DD（可选）", text: $dueOn)
                Stepper("优先级：\(priority)", value: $priority, in: 1...5)
                Stepper("影响：\(impact)", value: $impact, in: 1...5)
                Stepper("紧急度：\(urgency)", value: $urgency, in: 1...5)
                TextField("预计用时（分钟，可选）", text: $estimatedMinutes).keyboardType(.numberPad)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button { save() } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text("创建事项").fontWeight(.semibold) }; Spacer() } }.disabled(isSaving)
            }
            .navigationTitle("新建事项")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func save() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入事项标题"; return }
        let minutes = estimatedMinutes.isEmpty ? nil : Int(estimatedMinutes)
        if let minutes, !(5...1440).contains(minutes) { errorMessage = "预计用时应在 5 到 1440 分钟之间"; return }
        isSaving = true; errorMessage = nil
        Task {
            do {
                try await state.api.createTask(TaskCreateRequest(title: title, description: description.isEmpty ? nil : description, projectId: nil, priority: priority, dueOn: dueOn.isEmpty ? nil : dueOn, impact: impact, urgency: urgency, estimatedMinutes: minutes))
                await state.refreshDashboard(); dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }
}

struct ProjectsView: View {
    @ObservedObject var state: AppState
    @State private var selected: ProjectSummary?
    @State private var editingProject: ProjectSummary?
    @State private var showingCreate = false
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button { editingProject = project } label: { Label("编辑", systemImage: "pencil") }.tint(.orange)
                            Button(role: .destructive) { archive(project) } label: { Label("归档", systemImage: "archivebox") }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LuohaoDesign.canvas)
            .navigationTitle("项目")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("新建项目")
                }
            }
            .sheet(item: $selected) { ProjectWarRoom(project: $0) }
            .sheet(item: $editingProject) { ProjectFormView(state: state, project: $0) }
            .sheet(isPresented: $showingCreate) { ProjectFormView(state: state, project: nil) }
        }
    }

    private func archive(_ project: ProjectSummary) {
        Task {
            do {
                try await state.api.updateProject(project.id, ProjectUpdateRequest(name: nil, objective: nil, status: "archived", priority: nil, dueOn: nil, stage: nil, successCriteria: nil, keyHypothesis: nil, riskSummary: nil, blockerSummary: nil, nextAction: nil))
                await state.refreshDashboard()
            } catch { state.errorMessage = error.localizedDescription }
        }
    }
}

private struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: AppState
    let project: ProjectSummary?
    @State private var name: String
    @State private var objective: String
    @State private var stage: String
    @State private var status: String
    @State private var priority: Int
    @State private var dueOn: String
    @State private var successCriteria: String
    @State private var keyHypothesis: String
    @State private var riskSummary: String
    @State private var blockerSummary: String
    @State private var nextAction: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(state: AppState, project: ProjectSummary?) {
        self.state = state
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _objective = State(initialValue: project?.objective ?? "")
        _stage = State(initialValue: project?.stage ?? "planning")
        _status = State(initialValue: project?.status ?? "planning")
        _priority = State(initialValue: project?.priority ?? 3)
        _dueOn = State(initialValue: project?.dueOn ?? "")
        _successCriteria = State(initialValue: project?.successCriteria ?? "")
        _keyHypothesis = State(initialValue: project?.keyHypothesis ?? "")
        _riskSummary = State(initialValue: project?.riskSummary ?? "")
        _blockerSummary = State(initialValue: project?.blockerSummary ?? "")
        _nextAction = State(initialValue: project?.nextAction ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("项目名称", text: $name)
                    TextField("目标", text: $objective, axis: .vertical).lineLimit(2...5)
                    Picker("阶段", selection: $stage) {
                        Text("规划").tag("planning"); Text("探索").tag("discovery"); Text("验证").tag("validation"); Text("交付").tag("delivery")
                    }
                    Stepper("优先级：\(priority)", value: $priority, in: 1...5)
                    TextField("截止日期 YYYY-MM-DD（可选）", text: $dueOn)
                }
                if project != nil {
                    Picker("项目状态", selection: $status) { Text("规划中").tag("planning"); Text("推进中").tag("active"); Text("已暂停").tag("paused"); Text("已完成").tag("completed") }
                }
                Section("作战信息") {
                    TextField("成功标准", text: $successCriteria, axis: .vertical).lineLimit(2...5)
                    TextField("关键假设", text: $keyHypothesis, axis: .vertical).lineLimit(2...5)
                    TextField("主要风险", text: $riskSummary, axis: .vertical).lineLimit(2...5)
                    TextField("阻塞情况", text: $blockerSummary, axis: .vertical).lineLimit(2...5)
                    TextField("下一步行动", text: $nextAction, axis: .vertical).lineLimit(2...5)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button { save() } label: { HStack { Spacer(); if isSaving { ProgressView() } else { Text(project == nil ? "创建项目" : "保存修改").fontWeight(.semibold) }; Spacer() } }.disabled(isSaving)
            }
            .navigationTitle(project == nil ? "新建项目" : "编辑项目")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入项目名称"; return }
        isSaving = true; errorMessage = nil
        Task {
            do {
                if let project {
                    try await state.api.updateProject(project.id, ProjectUpdateRequest(name: name, objective: optional(objective), status: status, priority: priority, dueOn: optional(dueOn), stage: stage, successCriteria: optional(successCriteria), keyHypothesis: optional(keyHypothesis), riskSummary: optional(riskSummary), blockerSummary: optional(blockerSummary), nextAction: optional(nextAction)))
                } else {
                    try await state.api.createProject(ProjectCreateRequest(name: name, objective: optional(objective), priority: priority, dueOn: optional(dueOn), stage: stage, successCriteria: optional(successCriteria), keyHypothesis: optional(keyHypothesis), riskSummary: optional(riskSummary), blockerSummary: optional(blockerSummary), nextAction: optional(nextAction)))
                }
                await state.refreshDashboard(); dismiss()
            } catch { errorMessage = error.localizedDescription; isSaving = false }
        }
    }

    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        NavigationStack {
            Form {
                Section("安全") {
                    Toggle(isOn: $state.biometricEnabled) {
                        Label("Face ID 解锁", systemImage: "faceid")
                    }
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
            .scrollContentBackground(.hidden)
            .background(LuohaoDesign.canvas)
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
            if state.knowledgeDataUnavailable {
                ContentUnavailableView("经营知识暂时无法加载", systemImage: "wifi.exclamationmark", description: Text("请检查网络后重试。"))
            } else if mode == .memories {
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

private struct DataStatusBanner: View {
    let message: String
    let retry: () async -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.orange)
            Button("重试") { Task { await retry() } }.buttonStyle(.bordered).tint(.orange)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
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
