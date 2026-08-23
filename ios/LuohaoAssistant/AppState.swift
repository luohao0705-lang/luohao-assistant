import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var dashboard: DashboardSummary?
    @Published var cashflow: [CashflowPoint] = []
    @Published var dailyFocus: DailyFocus?
    @Published var projects: [ProjectSummary] = []
    @Published var tasks: [FocusTask] = []
    @Published var weeklyPlan: WeeklyPlan?
    @Published var pendingActions: [AssistantAction] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    let api = APIClient.shared

    func restoreSession() async {
        guard api.token != nil else { return }
        guard await BiometricGate.authenticate() else { return }
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
        projects = []
        tasks = []
        weeklyPlan = nil
        pendingActions = []
        isAuthenticated = false
    }

    func refreshDashboard() async {
        errorMessage = nil
        do {
            async let summary = api.dashboard()
            async let cashflowPoints = api.cashflow()
            async let focus = api.dailyFocus()
            async let projectList = api.projects()
            async let taskList = api.tasks()
            async let plan = api.currentWeeklyPlan()
            async let actions = api.pendingActions()
            dashboard = try await summary
            cashflow = try await cashflowPoints
            dailyFocus = try await focus
            projects = try await projectList
            tasks = try await taskList
            weeklyPlan = try await plan.item
            pendingActions = try await actions
        } catch let error as APIError {
            if case .unauthorized = error {
                logout()
            }
            errorMessage = error.localizedDescription
        } catch { errorMessage = error.localizedDescription }
    }

    func resolveAction(_ action: AssistantAction, confirm: Bool) async {
        do {
            if confirm { try await api.confirmAction(action.id) } else { try await api.cancelAction(action.id) }
            pendingActions.removeAll { $0.id == action.id }
            await refreshDashboard()
        } catch { errorMessage = error.localizedDescription }
    }
}
