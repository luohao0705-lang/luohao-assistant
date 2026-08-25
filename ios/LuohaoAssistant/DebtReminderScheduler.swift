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
            // Keep lock-screen notifications private. The detail is available in the app.
            content.body = "你有一条消息待查看"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: "\(identifierPrefix)\(debt.id)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

}
