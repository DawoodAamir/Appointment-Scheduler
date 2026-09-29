import SwiftUI
import UserNotifications

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var appointments: [Appointment] = []
    @Published var error: String?
    @Published var reminderMessage: String?
    private let file: URL
    private var loadFailed = false
    private var reminderRefresh: Task<Void, Never>?
    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppointmentScheduler/bookings.json")
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                appointments = try JSONDecoder().decode(
                    [Appointment].self, from: Data(contentsOf: file))
            }
        } catch {
            loadFailed = true
            self.error =
                "Saved appointments could not be opened. The file has been preserved. \(error.localizedDescription)"
        }
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--demo"), !loadFailed,
                appointments.isEmpty
            {
                var day = Calendar.current.startOfDay(for: Date())
                while Calendar.current.isDateInWeekend(day) {
                    day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
                }
                if let hours = BookingRules.businessHours(on: day) {
                    let examples = [
                        Appointment(
                            client: "Jordan Lee", start: hours.start.addingTimeInterval(3600)),
                        Appointment(
                            client: "Sam Rivera", serviceID: "planning",
                            start: hours.start.addingTimeInterval(3 * 3600), durationMinutes: 60,
                            status: .tentative),
                    ]
                    _ = persist(examples)
                }
            }
        #endif
    }
    @discardableResult
    func save(_ appointment: Appointment) -> Bool {
        do {
            var item = appointment
            item.start =
                Calendar.current.date(bySetting: .second, value: 0, of: item.start) ?? item.start
            try BookingRules.validate(item, among: appointments)
            item.client = item.client.trimmingCharacters(in: .whitespacesAndNewlines)
            item.modifiedAt = Date()
            var next = appointments.filter { $0.id != item.id }
            next.append(item)
            next.sort { $0.start < $1.start }
            return persist(next)
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    private func persist(_ items: [Appointment]) -> Bool {
        guard !loadFailed else {
            error =
                "Resolve the saved-file read error before making changes. Existing data has been preserved."
            return false
        }
        do {
            try JSONEncoder().encode(items).write(to: file, options: .atomic)
            appointments = items
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    func cancel(_ appointment: Appointment) {
        var next = appointment
        next.status = .cancelled
        next.reminder = false
        if save(next) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
                appointment.id.uuidString
            ])
            Task { await reconcileReminders() }
        }
    }
    func enableReminders() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound])
            reminderMessage =
                granted
                ? "Reminders enabled. Choose a reminder when editing a booking."
                : "Notifications are disabled. Enable them in Settings if you want appointment reminders."
            await reconcileReminders()
        } catch { self.error = error.localizedDescription }
    }
    func reconcileReminders() async {
        let previous = reminderRefresh
        let refresh = Task { [weak self] in
            await previous?.value
            await self?.scheduleCurrentReminders()
        }
        reminderRefresh = refresh
        await refresh.value
    }
    private func scheduleCurrentReminders() async {
        // Serialized on the main actor; each refresh replaces only this app's appointment IDs.
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        center.removePendingNotificationRequests(
            withIdentifiers: appointments.map { $0.id.uuidString })
        guard
            settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        else {
            if appointments.contains(where: {
                $0.reminder && $0.status != .cancelled && $0.start > Date()
            }) {
                reminderMessage =
                    "Bookings are saved, but reminders need notification permission. Use Enable reminders."
            }
            return
        }
        let upcoming = appointments.filter {
            $0.reminder && $0.status != .cancelled && $0.start.addingTimeInterval(-900) > Date()
        }.sorted { $0.start < $1.start }
        for item in upcoming.prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = "Upcoming appointment"
            content.body = "Your appointment starts in 15 minutes."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, item.start.timeIntervalSinceNow - 900), repeats: false)
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: item.id.uuidString, content: content, trigger: trigger))
            } catch {
                reminderMessage =
                    "Booking saved. A reminder could not be scheduled: \(error.localizedDescription)"
            }
        }
        if upcoming.count > 60 {
            reminderMessage =
                "The next 60 reminders are scheduled. Reopen the app to schedule later bookings as time passes."
        }
    }
    func export(_ item: Appointment) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "Appointment-\(item.id).ics")
        try CalendarFile.encode(item).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
