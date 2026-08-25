import Foundation
import UserNotifications

enum DebtReminderScheduler {
    private static let identifierPrefix = "luohao.debt."

    static func sync(debts: [DebtSummary]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }

        let pending = await center.pendingNotificationRequests()
        let oldIdentifiers = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        if !oldIdentifiers.isEmpty { center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers) }

        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for debt in debts where debt.outstandingCents > 0 {
            guard let dueOn = debt.dueOn, let dueDate = formatter.date(from: dueOn) else { continue }
            guard calendar.startOfDay(for: dueDate) >= calendar.startOfDay(for: Date()) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: dueDate)
            components.hour = 9
            components.minute = 0
            let content = UNMutableNotificationContent()
            content.title = "还款提醒"
            content.body = "\(debt.creditor)应还 \(currency(debt.outstandingCents))"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "\(identifierPrefix)\(debt.id)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    private static func currency(_ cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "¥0"
    }
}
