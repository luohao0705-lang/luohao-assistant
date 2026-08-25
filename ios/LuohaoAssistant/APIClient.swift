import Foundation

struct LoginResponse: Decodable {
    let accessToken: String
    let tokenType: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case tokenType = "token_type" }
}

struct DashboardSummary: Decodable {
    let cashCents: Int
    let cashRegistered: Bool
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
        case cashCents = "cash_cents"; case cashRegistered = "cash_registered"; case outstandingDebtCents = "outstanding_debt_cents"; case plannedIncomeCents = "planned_income_cents"; case plannedExpenseCents = "planned_expense_cents"; case debtDue30dCents = "debt_due_30d_cents"; case overdueIncomeCents = "overdue_income_cents"; case forecastLowestBalanceCents = "forecast_lowest_balance_cents"; case forecastLowestDate = "forecast_lowest_date"; case activeProjects = "active_projects"; case openTasks = "open_tasks"; case riskFlags = "risk_flags"
    }
}

struct MorningBrief: Decodable {
    let summary: String
    let lifeAdvice: [String]
    let financeAdvice: [String]
    let workAdvice: [String]
    let date: String
    enum CodingKeys: String, CodingKey {
        case summary, date
        case lifeAdvice = "life_advice"
        case financeAdvice = "finance_advice"
        case workAdvice = "work_advice"
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
    let monthlyPaymentCents: Int?
    let paymentDay: Int?
    let interestRate: Double?
    let status: String
    let note: String?
    enum CodingKeys: String, CodingKey { case id, creditor; case principalCents = "principal_cents"; case outstandingCents = "outstanding_cents"; case dueOn = "due_on"; case monthlyPaymentCents = "monthly_payment_cents"; case paymentDay = "payment_day"; case interestRate = "interest_rate"; case status, note }
}

struct TransactionCreateRequest: Encodable {
    let accountId: Int?
    let kind: String
    let amountCents: Int
    let occurredOn: String
    let status: String
    let counterparty: String?
    let note: String?
    enum CodingKeys: String, CodingKey { case accountId = "account_id"; case kind; case amountCents = "amount_cents"; case occurredOn = "occurred_on"; case status, counterparty, note }
}

struct AccountCreateRequest: Encodable {
    let name: String
    let kind: String
    let balanceCents: Int
    let currency: String
    enum CodingKeys: String, CodingKey { case name, kind; case balanceCents = "balance_cents"; case currency }
}

struct TransactionUpdateRequest: Encodable {
    let kind: String?
    let amountCents: Int?
    let occurredOn: String?
    let status: String?
    let counterparty: String?
    let note: String?
    enum CodingKeys: String, CodingKey { case kind; case amountCents = "amount_cents"; case occurredOn = "occurred_on"; case status, counterparty, note }
}

struct DebtCreateRequest: Encodable {
    let creditor: String
    let principalCents: Int
    let outstandingCents: Int
    let dueOn: String?
    let monthlyPaymentCents: Int?
    let paymentDay: Int?
    let interestRate: Double?
    let note: String?
    enum CodingKeys: String, CodingKey { case creditor; case principalCents = "principal_cents"; case outstandingCents = "outstanding_cents"; case dueOn = "due_on"; case monthlyPaymentCents = "monthly_payment_cents"; case paymentDay = "payment_day"; case interestRate = "interest_rate"; case note }
}

struct DebtUpdateRequest: Encodable {
    let creditor: String?
    let principalCents: Int?
    let outstandingCents: Int?
    let dueOn: String?
    let monthlyPaymentCents: Int?
    let paymentDay: Int?
    let status: String?
    let note: String?
    enum CodingKeys: String, CodingKey { case creditor; case principalCents = "principal_cents"; case outstandingCents = "outstanding_cents"; case dueOn = "due_on"; case monthlyPaymentCents = "monthly_payment_cents"; case paymentDay = "payment_day"; case status, note }
}

struct MemoryCreateRequest: Encodable {
    let content: String
    let memoryType: String
    let projectId: Int?
    let source: String
    enum CodingKeys: String, CodingKey { case content; case memoryType = "memory_type"; case projectId = "project_id"; case source }
}

struct DecisionCreateRequest: Encodable {
    let projectId: Int?
    let title: String
    let context: String?
    let decision: String
    let rationale: String?
    let reviewOn: String?
    enum CodingKeys: String, CodingKey { case projectId = "project_id"; case title, context, decision, rationale; case reviewOn = "review_on" }
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
    let suggestions: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decode(String.self, forKey: .reply)
        snapshot = try container.decode(DashboardSummary.self, forKey: .snapshot)
        toolResults = try container.decodeIfPresent([[String: JSONValue]].self, forKey: .toolResults) ?? []
        suggestions = try container.decodeIfPresent([String].self, forKey: .suggestions) ?? []
    }

    enum CodingKeys: String, CodingKey { case reply, snapshot, suggestions; case toolResults = "tool_results" }
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
    let blockedReason: String?
    let score: Int
    enum CodingKeys: String, CodingKey { case id, title; case projectId = "project_id"; case status, priority, impact, urgency; case dueOn = "due_on"; case estimatedMinutes = "estimated_minutes"; case blockedReason = "blocked_reason"; case score }
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

struct ProjectCreateRequest: Encodable {
    let name: String
    let objective: String?
    let priority: Int
    let dueOn: String?
    let stage: String
    let successCriteria: String?
    let keyHypothesis: String?
    let riskSummary: String?
    let blockerSummary: String?
    let nextAction: String?
    enum CodingKeys: String, CodingKey { case name, objective, priority; case dueOn = "due_on"; case stage; case successCriteria = "success_criteria"; case keyHypothesis = "key_hypothesis"; case riskSummary = "risk_summary"; case blockerSummary = "blocker_summary"; case nextAction = "next_action" }
}

struct ProjectUpdateRequest: Encodable {
    let name: String?
    let objective: String?
    let status: String?
    let priority: Int?
    let dueOn: String?
    let stage: String?
    let successCriteria: String?
    let keyHypothesis: String?
    let riskSummary: String?
    let blockerSummary: String?
    let nextAction: String?
    enum CodingKeys: String, CodingKey { case name, objective, status, priority; case dueOn = "due_on"; case stage; case successCriteria = "success_criteria"; case keyHypothesis = "key_hypothesis"; case riskSummary = "risk_summary"; case blockerSummary = "blocker_summary"; case nextAction = "next_action" }
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

struct WeeklyPlanCreateRequest: Encodable {
    let weekStart: String
    let theme: String?
    let outcomes: [String]
    let priorities: [String]
    let risks: [String]
    let reviewNotes: String?
    enum CodingKeys: String, CodingKey { case weekStart = "week_start"; case theme, outcomes, priorities, risks; case reviewNotes = "review_notes" }
}

struct AssistantAction: Decodable, Identifiable {
    let id: Int
    let actionType: String
    let status: String
    let payload: JSONValue
    let result: JSONValue?
    enum CodingKeys: String, CodingKey { case id; case actionType = "action_type"; case status, payload, result }
}

struct TaskUpdateRequest: Encodable {
    let title: String?
    let status: String?
    let priority: Int?
    let impact: Int?
    let urgency: Int?
    let blockedReason: String?

    enum CodingKeys: String, CodingKey { case title, status, priority, impact, urgency; case blockedReason = "blocked_reason" }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(impact, forKey: .impact)
        try container.encodeIfPresent(urgency, forKey: .urgency)
        try container.encodeIfPresent(blockedReason, forKey: .blockedReason)
    }
}

struct TaskCreateRequest: Encodable {
    let title: String
    let description: String?
    let projectId: Int?
    let priority: Int
    let dueOn: String?
    let impact: Int
    let urgency: Int
    let estimatedMinutes: Int?
    enum CodingKeys: String, CodingKey { case title, description; case projectId = "project_id"; case priority; case dueOn = "due_on"; case impact, urgency; case estimatedMinutes = "estimated_minutes" }
}

enum JSONValue: Decodable {
    case string(String); case number(Double); case bool(Bool); case object([String: JSONValue]); case array([JSONValue]); case null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null } else if let v = try? c.decode(String.self) { self = .string(v) } else if let v = try? c.decode(Double.self) { self = .number(v) } else if let v = try? c.decode(Bool.self) { self = .bool(v) } else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) } else { self = .array(try c.decode([JSONValue].self)) }
    }
}

enum APIError: LocalizedError {
    case invalidResponse; case unauthorized; case server(String); case network(Error)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务器返回了无法识别的数据"
        case .unauthorized: return "登录已过期，请重新登录"
        case .server(let message): return message
        case .network: return "网络连接失败，请检查网络后重试"
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    var baseURL = URL(string: "https://luo.hsh6.com")!
    private(set) var token: String?
    private init() { token = KeychainStore.read("luohao.session") }
    func login(password: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/login")); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(["password": password])
        let (data, response) = try await perform(request); guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response, data: data) }
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
    func createAccount(_ payload: AccountCreateRequest) async throws { try await post(path: "finance/accounts", payload: payload) }
    func createTransaction(_ payload: TransactionCreateRequest) async throws { try await post(path: "finance/transactions", payload: payload) }
    func updateTransaction(_ id: Int, _ payload: TransactionUpdateRequest) async throws { try await patch(path: "finance/transactions/\(id)", payload: payload) }
    func createDebt(_ payload: DebtCreateRequest) async throws { try await post(path: "finance/debts", payload: payload) }
    func updateDebt(_ id: Int, _ payload: DebtUpdateRequest) async throws { try await patch(path: "finance/debts/\(id)", payload: payload) }
    func memories() async throws -> [MemorySummary] { let response: MemoryListResponse = try await authorized(path: "memories"); return response.items }
    func decisions() async throws -> [DecisionSummary] { let response: DecisionListResponse = try await authorized(path: "decisions"); return response.items }
    func createMemory(_ payload: MemoryCreateRequest) async throws { try await post(path: "memories", payload: payload) }
    func archiveMemory(_ id: Int) async throws { _ = try await authorizedAction(path: "memories/\(id)/archive", method: "POST") }
    func createDecision(_ payload: DecisionCreateRequest) async throws { try await post(path: "decisions", payload: payload) }
    func dailyFocus() async throws -> DailyFocus { try await authorized(path: "daily-focus") }
    func morningBrief() async throws -> MorningBrief { try await authorized(path: "morning-brief") }
    func projects() async throws -> [ProjectSummary] { let response: ProjectListResponse = try await authorized(path: "projects"); return response.items }
    func createProject(_ payload: ProjectCreateRequest) async throws { try await post(path: "projects", payload: payload) }
    func updateProject(_ id: Int, _ payload: ProjectUpdateRequest) async throws { try await patch(path: "projects/\(id)", payload: payload) }
    func tasks() async throws -> [FocusTask] { let response: TaskListResponse = try await authorized(path: "tasks"); return response.items }
    func createTask(_ payload: TaskCreateRequest) async throws { try await post(path: "tasks", payload: payload) }
    func currentWeeklyPlan() async throws -> WeeklyPlanResponse { try await authorized(path: "weekly-plans/current") }
    func saveWeeklyPlan(_ payload: WeeklyPlanCreateRequest) async throws { try await post(path: "weekly-plans", payload: payload) }
    func pendingActions() async throws -> [AssistantAction] { let response: ActionListResponse = try await authorized(path: "assistant/actions"); return response.items.filter { $0.status == "pending" } }
    func confirmAction(_ id: Int) async throws { _ = try await authorizedAction(path: "assistant/actions/\(id)/confirm", method: "POST") }
    func cancelAction(_ id: Int) async throws { _ = try await authorizedAction(path: "assistant/actions/\(id)/cancel", method: "POST") }
    func updateTask(_ id: Int, title: String? = nil, status: String? = nil, priority: Int? = nil, impact: Int? = nil, urgency: Int? = nil, blockedReason: String? = nil) async throws {
        var request = try authorizedRequest(path: "tasks/\(id)")
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TaskUpdateRequest(title: title, status: status, priority: priority, impact: impact, urgency: urgency, blockedReason: blockedReason))
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response, data: data) }
    }
    func command(_ text: String, mode: String = "chat", history: [[String: String]] = []) async throws -> AssistantCommandResponse {
        var request = try authorizedRequest(path: "assistant/command"); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "mode": mode, "history": history])
        let (data, response) = try await perform(request); guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response, data: data) }; return try JSONDecoder().decode(AssistantCommandResponse.self, from: data)
    }
    private func authorized<T: Decodable>(path: String) async throws -> T { let (data, response) = try await perform(authorizedRequest(path: path)); guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response, data: data) }; return try JSONDecoder().decode(T.self, from: data) }
    private func post<T: Encodable>(path: String, payload: T) async throws {
        var request = try authorizedRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response, data: data) }
    }
    private func patch<T: Encodable>(path: String, payload: T) async throws {
        var request = try authorizedRequest(path: path)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response, data: data) }
    }
    private func authorizedAction(path: String, method: String) async throws -> ActionResponse { var request = try authorizedRequest(path: path); request.httpMethod = method; let (data, response) = try await perform(request); guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw error(for: response, data: data) }; return try JSONDecoder().decode(ActionResponse.self, from: data) }
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
    private func error(for response: URLResponse, data: Data = Data()) -> APIError {
        guard let status = (response as? HTTPURLResponse)?.statusCode else { return .invalidResponse }
        if status == 401 { return .unauthorized }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = object["detail"] {
            if let text = detail as? String { return .server(localizeServerDetail(text)) }
            if let items = detail as? [[String: Any]] {
                let messages = items.compactMap { $0["msg"] as? String }
                if !messages.isEmpty { return .server(messages.joined(separator: "；")) }
            }
        }
        return .server("服务器请求失败（\(status)）")
    }

    private func localizeServerDetail(_ value: String) -> String {
        if value.contains("date") || value.contains("日期") { return "日期格式不正确，请使用 YYYY-MM-DD" }
        if value.contains("amount") || value.contains("金额") { return "金额不正确，请检查后重试" }
        if value.contains("not found") { return "数据不存在或已被删除" }
        return value
    }
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
