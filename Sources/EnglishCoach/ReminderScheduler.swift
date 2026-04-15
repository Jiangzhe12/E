import Foundation
import UserNotifications

/// Schedules (and cancels) the "今天还没完成英语学习" daily local notification.
///
/// We use a single repeating calendar trigger; to "skip today when already
/// completed" we remove the pending request and reschedule only after the
/// user's reminder time has passed. On next day the normal repeat takes over.
@MainActor
final class ReminderScheduler {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "daily-reminder"

    /// Ask for authorization if we don't already have it. Returns true if the
    /// user ended up granting (either now or previously).
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                NSLog("[ReminderScheduler] authorization request failed: %@", error.localizedDescription)
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Schedule (or re-schedule) the repeating daily reminder.
    func schedule(hour: Int, minute: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let content = UNMutableNotificationContent()
        content.title = "English Coach"
        content.body = "今天还没完成英语学习 · 20 词和兴趣学习等你"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                NSLog("[ReminderScheduler] schedule failed: %@", error.localizedDescription)
            }
        }
    }

    /// Cancel the repeating reminder entirely.
    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Skip today's firing without losing future days. If the reminder time is
    /// still in the future today, we remove the pending request and schedule a
    /// single-shot request for tomorrow at the same time; a later call to
    /// `schedule(...)` (next app launch) will swap the one-shot back to the
    /// repeating trigger.
    func suppressForToday(hour: Int, minute: Int, now: Date = Date(), calendar: Calendar = .current) {
        var todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
        todayComponents.hour = hour
        todayComponents.minute = minute

        guard let todayFireDate = calendar.date(from: todayComponents) else { return }

        // If we're already past today's fire time, the next repeat is tomorrow
        // anyway — nothing to suppress.
        guard todayFireDate > now else { return }

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayFireDate) else { return }
        var tomorrowComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: tomorrow
        )
        tomorrowComponents.hour = hour
        tomorrowComponents.minute = minute

        let content = UNMutableNotificationContent()
        content.title = "English Coach"
        content.body = "今天还没完成英语学习 · 20 词和兴趣学习等你"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: tomorrowComponents, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                NSLog("[ReminderScheduler] suppress-reschedule failed: %@", error.localizedDescription)
            }
        }
    }
}
