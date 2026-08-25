import Foundation

func localizedTaskStatus(_ value: String) -> String {
    ["todo": "待办", "in_progress": "进行中", "blocked": "阻塞", "done": "已完成", "cancelled": "已取消"][value] ?? value
}

func isFinancialTask(_ task: FocusTask) -> Bool {
    let title = task.title
    let keywords = ["欠款", "还款", "贷款", "房贷", "车贷", "债务", "月供", "收款", "付款"]
    if keywords.contains(where: title.contains) { return true }
    return title.contains("元") && title.range(of: "[0-9]", options: .regularExpression) != nil
}

func localizedProjectStage(_ value: String) -> String {
    ["planning": "规划", "discovery": "探索", "validation": "验证", "delivery": "交付", "paused": "暂停", "completed": "已完成", "active": "推进中"][value] ?? value
}

func localizedProjectStatus(_ value: String) -> String {
    ["planning": "规划中", "active": "推进中", "paused": "已暂停", "completed": "已完成", "archived": "已归档"][value] ?? value
}

func localizedAccountKind(_ value: String) -> String {
    ["bank": "银行账户", "cash": "现金", "wallet": "第三方支付"][value] ?? value
}

func localizedDebtStatus(_ value: String) -> String {
    ["open": "未偿还", "paid": "已还清", "overdue": "已逾期", "cancelled": "已取消"][value] ?? value
}

func localizedActionType(_ value: String) -> String {
    ["propose_finance_entry": "登记财务记录", "propose_debt_payment": "登记债务还款", "propose_tasks": "新增事项方案", "create_project_plan": "建立项目方案", "create_weekly_plan": "生成本周计划"][value] ?? "待确认操作"
}

func localizedToolName(_ value: String) -> String {
    ["propose_finance_entry": "财务登记", "propose_debt_payment": "债务还款", "propose_tasks": "事项拆解", "create_project_plan": "项目规划", "create_weekly_plan": "周计划", "get_daily_focus": "今日重点", "get_dashboard": "经营总览"][value] ?? value
}
