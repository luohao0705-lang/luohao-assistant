import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var dashboard: DashboardSummary?
    @Published var cashflow: [CashflowPoint] = []
    @Published var dailyFocus: DailyFocus?
    @Published var morningBrief: MorningBrief?
    @Published var projects: [ProjectSummary] = []
    @Published var tasks: [FocusTask] = []
    @Published var accounts: [AccountSummary] = []
    @Published var transactions: [TransactionSummary] = []
    @Published var debts: [DebtSummary] = []
    @Published var memories: [MemorySummary] = []
    @Published var decisions: [DecisionSummary] = []
    @Published var financeDataUnavailable = false
    @Published var knowledgeDataUnavailable = false
    @Published var weeklyPlan: WeeklyPlan?
    @Published var pendingActions: [AssistantAction] = []
    @Published var errorMessage: String?
    @Published private(set) var connectionHealthy: Bool?
    @Published var isLoading = false
    @Published var biometricEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricEnabled, forKey: "luohao.biometricEnabled") }
    }
    let api = APIClient.shared

    init() {
        biometricEnabled = UserDefaults.standard.object(forKey: "luohao.biometricEnabled") as? Bool ?? true
    }

    func restoreSession() async {
        guard api.token != nil else { return }
        if biometricEnabled {
            guard await BiometricGate.authenticate() else { return }
        }
        isAuthenticated = true
        await refreshDashboard()
    }

    func login(password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await api.login(password: password)
            isAuthenticated = true
            await refreshDashboard()
        } catch { errorMessage = error.localizedDescription }
    }

    func logout() {
        api.logout()
        dashboard = nil
        cashflow = []
        dailyFocus = nil
        morningBrief = nil
        projects = []
        tasks = []
        accounts = []
        transactions = []
        debts = []
        memories = []
        decisions = []
        financeDataUnavailable = false
        knowledgeDataUnavailable = false
        weeklyPlan = nil
        pendingActions = []
        connectionHealthy = nil
        isAuthenticated = false
    }

    func refreshDashboard() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let summary = api.dashboard()
            async let cashflowPoints = api.cashflow()
            async let focus = api.dailyFocus()
            async let brief: MorningBrief? = try? await api.morningBrief()
            async let projectList = api.projects()
            async let taskList = api.tasks()
            async let accountList: [AccountSummary]? = try? await api.accounts()
            async let transactionList: [TransactionSummary]? = try? await api.transactions()
            async let debtList: [DebtSummary]? = try? await api.debts()
            async let memoryList: [MemorySummary]? = try? await api.memories()
            async let decisionList: [DecisionSummary]? = try? await api.decisions()
            async let plan = api.currentWeeklyPlan()
            async let actions = api.pendingActions()
            dashboard = try await summary
            cashflow = try await cashflowPoints
            dailyFocus = try await focus
            morningBrief = await brief
            projects = try await projectList
            tasks = try await taskList
            let accountsValue = await accountList
            let transactionsValue = await transactionList
            let debtsValue = await debtList
            let memoriesValue = await memoryList
            let decisionsValue = await decisionList
            financeDataUnavailable = accountsValue == nil || transactionsValue == nil || debtsValue == nil
            knowledgeDataUnavailable = memoriesValue == nil || decisionsValue == nil
            accounts = accountsValue ?? []
            transactions = transactionsValue ?? []
            debts = debtsValue ?? []
            await DebtReminderScheduler.sync(debts: debts, tasks: tasks)
            memories = memoriesValue ?? []
            decisions = decisionsValue ?? []
            weeklyPlan = try await plan.item
            pendingActions = try await actions
            connectionHealthy = true
        } catch let error as APIError {
            if case .unauthorized = error {
                logout()
            }
            errorMessage = error.localizedDescription
            connectionHealthy = false
        } catch {
            errorMessage = error.localizedDescription
            connectionHealthy = false
        }
    }

    /// Refresh only the confirmation queue. This stays usable even when an
    /// unrelated dashboard endpoint is temporarily unavailable.
    func refreshPendingActions() async {
        do {
            pendingActions = try await api.pendingActions()
            connectionHealthy = true
        } catch {
            errorMessage = error.localizedDescription
            connectionHealthy = false
        }
    }

    @discardableResult
    func resolveAction(_ action: AssistantAction, confirm: Bool) async -> Bool {
        do {
            if confirm { try await api.confirmAction(action.id) } else { try await api.cancelAction(action.id) }
            pendingActions.removeAll { $0.id == action.id }
            await refreshDashboard()
            return true
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }
}
