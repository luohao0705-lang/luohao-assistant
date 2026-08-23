import Foundation

struct LoginResponse: Decodable {
    let accessToken: String
    let tokenType: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case tokenType = "token_type" }
}

struct DashboardSummary: Decodable {
    let cashCents: Int
    let outstandingDebtCents: Int
    let plannedIncomeCents: Int
    let plannedExpenseCents: Int
    let debtDue30dCents: Int
    let overdueIncomeCents: Int
    let forecastLowestBalanceCents: Int
    let forecastLowestDate: String
    let activeProjects: Int
    let openTasks: Int
    let riskFlags: [String]
    enum CodingKeys: String, CodingKey {
        case cashCents = "cash_cents"; case outstandingDebtCents = "outstanding_debt_cents"; case plannedIncomeCents = "planned_income_cents"; case plannedExpenseCents = "planned_expense_cents"; case debtDue30dCents = "debt_due_30d_cents"; case overdueIncomeCents = "overdue_income_cents"; case forecastLowestBalanceCents = "forecast_lowest_balance_cents"; case forecastLowestDate = "forecast_lowest_date"; case activeProjects = "active_projects"; case openTasks = "open_tasks"; case riskFlags = "risk_flags"
    }
}

struct CashflowPoint: Decodable, Identifiable {
    let date: String
    let balanceCents: Int
    var id: String { date }
    enum CodingKeys: String, CodingKey { case date; case balanceCents = "balance_cents" }
}

struct AccountSummary: Decodable, Identifiable {
    let id: Int
    let name: String
    let kind: String
    let balanceCents: Int
    let currency: String
    enum CodingKeys: String, CodingKey { case id, name, kind; case balanceCents = "balance_cents"; case currency }
}

struct TransactionSummary: Decodable, Identifiable {
    let id: Int
    let kind: String
    let amountCents: Int
    let occurredOn: String
    let expectedOn: String?
    let status: String
    let counterparty: String?
    let note: String?
    enum CodingKeys: String, CodingKey { case id, kind; case amountCents = "amount_cents"; case occurredOn = "occurred_on"; case expectedOn = "expected_on"; case status, counterparty, note }
}

struct DebtSummary: Decodable, Identifiable {
    let id: Int
    let creditor: String
    let principalCents: Int
    let outstandingCents: Int
    let dueOn: String?
    let interestRate: Double?
    let status: String
    let note: String?
    enum CodingKeys: String, CodingKey { case id, creditor; case principalCents = "principal_cents"; case outstandingCents = "outstanding_cents"; case dueOn = "due_on"; case interestRate = "interest_rate"; case status, note }
}

struct TransactionCreateRequest: Encodable {
    let kind: String
    let amountCents: Int
    let occurredOn: String
    let status: String
    let counterparty: String?
    let note: String?
    enum CodingKeys: String, CodingKey { case kind; case amountCents = "amount_cents"; case occurredOn = "occurred_on"; case status, counterparty, note }
}

struct DebtCreateRequest: Encodable {
    let creditor: String
    let principalCents: Int
    let outstandingCents: Int
    let dueOn: String?
    let interestRate: Double?
    let note: String?
    enum CodingKeys: String, CodingKey { case creditor; case principalCents = "principal_cents"; case outstandingCents = "outstanding_cents"; case dueOn = "due_on"; case interestRate = "interest_rate"; case note }
}

struct MemorySummary: Decodable, Identifiable {
    let id: Int
    let memoryType: String
    let content: String
    let projectId: Int?
    let source: String?
    enum CodingKeys: String, CodingKey { case id; case memoryType = "memory_type"; case content; case projectId = "project_id"; case source }
}

struct DecisionSummary: Decodable, Identifiable {
    let id: Int
    let projectId: Int?
    let title: String
    let context: String?
    let decision: String
    let rationale: String?
    let reviewOn: String?
    enum CodingKeys: String, CodingKey { case id; case projectId = "project_id"; case title, context, decision, rationale; case reviewOn = "review_on" }
}

struct AssistantCommandResponse: Decodable {
    let reply: String
    let snapshot: DashboardSummary
    let toolResults: [[String: JSONValue]]
    enum CodingKeys: String, CodingKey { case reply, snapshot; case toolResults = "tool_results" }
}

struct DailyFocus: Decodable {
    let date: String
    let focus: [FocusTask]
    let blocked: [BlockedTask]
    let overdueCount: Int
    let openCount: Int
    enum CodingKeys: String, CodingKey { case date, focus, blocked; case overdueCount = "overdue_count"; case openCount = "open_count" }
}

struct FocusTask: Decodable, Identifiable {
    let id: Int
    let title: String
    let projectId: Int?
    let status: String
    let priority: Int
    let impact: Int
    let urgency: Int
    let dueOn: String?
    let estimatedMinutes: Int?
    let score: Int
    enum CodingKeys: String, CodingKey { case id, title; case projectId = "project_id"; case status, priority, impact, urgency; case dueOn = "due_on"; case estimatedMinutes = "estimated_minutes"; case score }
}

struct BlockedTask: Decodable, Identifiable {
    let id: Int
    let title: String
    let reason: String
    let projectId: Int?
    enum CodingKeys: String, CodingKey { case id, title, reason; case projectId = "project_id" }
}

struct ProjectSummary: Decodable, Identifiable {
    let id: Int
    let name: String
    let objective: String?
    let status: String
    let stage: String
    let priority: Int
    let dueOn: String?
    let successCriteria: String?
    let keyHypothesis: String?
    let riskSummary: String?
    let blockerSummary: String?
    let nextAction: String?
    let tasks: [FocusTask]
    let openTaskCount: Int
    enum CodingKeys: String, CodingKey { case id, name, objective, status, stage, priority; case dueOn = "due_on"; case successCriteria = "success_criteria"; case keyHypothesis = "key_hypothesis"; case riskSummary = "risk_summary"; case blockerSummary = "blocker_summary"; case nextAction = "next_action"; case tasks; case openTaskCount = "open_task_count" }
}

struct WeeklyPlan: Decodable {
    let id: Int
    let weekStart: String
    let theme: String?
    let outcomes: [String]
    let priorities: [String]
    let risks: [String]
    let reviewNotes: String?
    let status: String
    enum CodingKeys: String, CodingKey { case id; case weekStart = "week_start"; case theme, outcomes, priorities, risks; case reviewNotes = "review_notes"; case status }
}

struct WeeklyPlanResponse: Decodable { let item: WeeklyPlan?; let weekStart: String; enum CodingKeys: String, CodingKey { case item; case weekStart = "week_start" } }

struct AssistantAction: Decodable, Identifiable {
    let id: Int
    let actionType: String
    let status: String
    let payload: JSONValue
    let result: JSONValue?
    enum CodingKeys: String, CodingKey { case id; case actionType = "action_type"; case status, payload, result }
}

struct TaskUpdateRequest: Encodable {
    let status: String?
    let priority: Int?
    let impact: Int?
    let urgency: Int?

    enum CodingKeys: String, CodingKey { case status, priority, impact, urgency }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(impact, forKey: .impact)
        try container.encodeIfPresent(urgency, forKey: .urgency)
    }
}

enum JSONValue: Decodable {
    case string(String); case number(Double); case bool(Bool); case object([String: JSONValue]); case array([JSONValue]); case null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null } else if let v = try? c.decode(String.self) { self = .string(v) } else if let v = try? c.decode(Double.self) { self = .number(v) } else if let v = try? c.decode(Bool.self) { self = .bool(v) } else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) } else { self = .array(try c.decode([JSONValue].self)) }
    }
}

enum APIError: LocalizedError {
    case invalidResponse; case unauthorized; case network(Error)
    var errorDescription: String? {
        switch self { case .invalidResponse: return "Invalid server response"; case .unauthorized: return "Session expired. Please sign in again."; case .network(let error): return "Network error: \(error.localizedDescription)" }
    }
}

final class APIClient {
    static let shared = APIClient()
    var baseURL = URL(string: "https://luo.hsh6.com")!
    private(set) var token: String?
    private init() { token = KeychainStore.read("luohao.session") }
    func login(password: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/login")); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(["password": password])
        let (data, response) = try await perform(request); guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response) }
        token = try JSONDecoder().decode(LoginResponse.self, from: data).accessToken; if let token { KeychainStore.save(token, key: "luohao.session") }
    }
    func logout() { token = nil; KeychainStore.delete("luohao.session") }
    func dashboard() async throws -> DashboardSummary { try await authorized(path: "dashboard/summary") }
    func cashflow(days: Int = 45) async throws -> [CashflowPoint] {
        let response: CashflowResponse = try await authorized(path: "dashboard/cashflow?days=\(days)")
        return response.points
    }
    func accounts() async throws -> [AccountSummary] { let response: AccountListResponse = try await authorized(path: "finance/accounts"); return response.items }
    func transactions() async throws -> [TransactionSummary] { let response: TransactionListResponse = try await authorized(path: "finance/transactions"); return response.items }
    func debts() async throws -> [DebtSummary] { let response: DebtListResponse = try await authorized(path: "finance/debts"); return response.items }
    func createTransaction(_ payload: TransactionCreateRequest) async throws { try await post(path: "finance/transactions", payload: payload) }
    func createDebt(_ payload: DebtCreateRequest) async throws { try await post(path: "finance/debts", payload: payload) }
    func memories() async throws -> [MemorySummary] { let response: MemoryListResponse = try await authorized(path: "memories"); return response.items }
    func decisions() async throws -> [DecisionSummary] { let response: DecisionListResponse = try await authorized(path: "decisions"); return response.items }
    func dailyFocus() async throws -> DailyFocus { try await authorized(path: "daily-focus") }
    func projects() async throws -> [ProjectSummary] { let response: ProjectListResponse = try await authorized(path: "projects"); return response.items }
    func tasks() async throws -> [FocusTask] { let response: TaskListResponse = try await authorized(path: "tasks"); return response.items }
    func currentWeeklyPlan() async throws -> WeeklyPlanResponse { try await authorized(path: "weekly-plans/current") }
    func pendingActions() async throws -> [AssistantAction] { let response: ActionListResponse = try await authorized(path: "assistant/actions"); return response.items.filter { $0.status == "pending" } }
    func confirmAction(_ id: Int) async throws { _ = try await authorizedAction(path: "assistant/actions/\(id)/confirm", method: "POST") }
    func cancelAction(_ id: Int) async throws { _ = try await authorizedAction(path: "assistant/actions/\(id)/cancel", method: "POST") }
    func updateTask(_ id: Int, status: String? = nil, priority: Int? = nil, impact: Int? = nil, urgency: Int? = nil) async throws {
        var request = try authorizedRequest(path: "tasks/\(id)")
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TaskUpdateRequest(status: status, priority: priority, impact: impact, urgency: urgency))
        let (_, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response) }
    }
    func command(_ text: String, mode: String = "chat") async throws -> AssistantCommandResponse {
        var request = try authorizedRequest(path: "assistant/command"); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "mode": mode])
        let (data, response) = try await perform(request); guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response) }; return try JSONDecoder().decode(AssistantCommandResponse.self, from: data)
    }
    private func authorized<T: Decodable>(path: String) async throws -> T { let (data, response) = try await perform(authorizedRequest(path: path)); guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response) }; return try JSONDecoder().decode(T.self, from: data) }
    private func post<T: Encodable>(path: String, payload: T) async throws {
        var request = try authorizedRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (_, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response) }
    }
    private func authorizedAction(path: String, method: String) async throws -> ActionResponse { var request = try authorizedRequest(path: path); request.httpMethod = method; let (data, response) = try await perform(request); guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response) }; return try JSONDecoder().decode(ActionResponse.self, from: data) }
    private func authorizedRequest(path: String) throws -> URLRequest {
        let url: URL
        if let components = URLComponents(string: path), components.query != nil {
            url = baseURL.appendingPathComponent(components.path).appending(queryItems: components.queryItems ?? [])
        } else {
            url = baseURL.appendingPathComponent(path)
        }
        var request = URLRequest(url: url)
        guard let token else { throw APIError.invalidResponse }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) { do { return try await URLSession.shared.data(for: request) } catch { throw APIError.network(error) } }
    private func error(for response: URLResponse) -> APIError { (response as? HTTPURLResponse)?.statusCode == 401 ? .unauthorized : .invalidResponse }
}

private struct ProjectListResponse: Decodable { let items: [ProjectSummary] }
private struct TaskListResponse: Decodable { let items: [FocusTask] }
private struct AccountListResponse: Decodable { let items: [AccountSummary] }
private struct TransactionListResponse: Decodable { let items: [TransactionSummary] }
private struct DebtListResponse: Decodable { let items: [DebtSummary] }
private struct MemoryListResponse: Decodable { let items: [MemorySummary] }
private struct DecisionListResponse: Decodable { let items: [DecisionSummary] }
private struct CashflowResponse: Decodable { let days: Int; let points: [CashflowPoint] }
private struct ActionListResponse: Decodable { let items: [AssistantAction] }
private struct ActionResponse: Decodable { let id: Int; let actionType: String; let status: String; enum CodingKeys: String, CodingKey { case id; case actionType = "action_type"; case status } }
