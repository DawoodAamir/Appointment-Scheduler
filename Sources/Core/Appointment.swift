import Foundation

public enum BookingStatus: String, Codable, CaseIterable, Identifiable {
    case confirmed, tentative, cancelled
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}
public struct Service: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let minutes: Int
    public static let catalog = [
        Service(id: "consultation", name: "Consultation", minutes: 30),
        Service(id: "planning", name: "Planning session", minutes: 60),
        Service(id: "review", name: "Project review", minutes: 45),
    ]
}
public struct Appointment: Codable, Identifiable, Equatable {
    public var id: UUID
    public var client: String
    public var contact: String
    public var serviceID: String
    public var start: Date
    public var durationMinutes: Int
    public var status: BookingStatus
    public var notes: String
    public var reminder: Bool
    public var modifiedAt: Date
    public var end: Date { start.addingTimeInterval(Double(durationMinutes) * 60) }
    public var serviceName: String {
        Service.catalog.first { $0.id == serviceID }?.name ?? "Appointment"
    }
    public init(
        id: UUID = UUID(), client: String = "", contact: String = "",
        serviceID: String = "consultation", start: Date = Date(), durationMinutes: Int = 30,
        status: BookingStatus = .confirmed, notes: String = "", reminder: Bool = false,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.client = client
        self.contact = contact
        self.serviceID = serviceID
        self.start = start
        self.durationMinutes = durationMinutes
        self.status = status
        self.notes = notes
        self.reminder = reminder
        self.modifiedAt = modifiedAt
    }
}
public enum BookingError: LocalizedError, Equatable {
    case missingClient, invalidDuration, outsideHours
    case conflict(String)
    public var errorDescription: String? {
        switch self {
        case .missingClient: return "Enter a client name."
        case .invalidDuration: return "Choose a duration from 15 to 180 minutes."
        case .outsideHours:
            return
                "Choose a weekday appointment between 9:00 AM and 5:00 PM, including the full duration."
        case .conflict(let client):
            return
                "This time overlaps an appointment for \(client). Choose another time or cancel the conflicting booking."
        }
    }
}
public enum BookingRules {
    public static func validate(
        _ appointment: Appointment, among appointments: [Appointment], calendar: Calendar = .current
    ) throws {
        guard !appointment.client.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BookingError.missingClient
        }
        guard (15...180).contains(appointment.durationMinutes) else {
            throw BookingError.invalidDuration
        }
        guard appointment.status != .cancelled else { return }
        guard let hours = businessHours(on: appointment.start, calendar: calendar),
            appointment.start >= hours.start, appointment.end <= hours.end
        else { throw BookingError.outsideHours }
        if let other = appointments.first(where: {
            $0.id != appointment.id && $0.status != .cancelled && appointment.start < $0.end
                && $0.start < appointment.end
        }) {
            throw BookingError.conflict(other.client)
        }
    }
    public static func businessHours(on day: Date, calendar: Calendar = .current) -> DateInterval? {
        guard (2...6).contains(calendar.component(.weekday, from: day)),
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
            let end = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day)
        else { return nil }
        return DateInterval(start: start, end: end)
    }
    public static func availableSlots(
        on day: Date, minutes: Int, appointments: [Appointment], excluding id: UUID? = nil,
        now: Date = Date(), calendar: Calendar = .current
    ) -> [Date] {
        guard (15...180).contains(minutes), let hours = businessHours(on: day, calendar: calendar)
        else { return [] }
        var result: [Date] = []
        var cursor = hours.start
        while cursor.addingTimeInterval(Double(minutes) * 60) <= hours.end {
            let end = cursor.addingTimeInterval(Double(minutes) * 60)
            if cursor >= now
                && !appointments.contains(where: {
                    $0.id != id && $0.status != .cancelled && cursor < $0.end && $0.start < end
                })
            {
                result.append(cursor)
            }
            cursor = cursor.addingTimeInterval(15 * 60)
        }
        return result
    }
}
public enum CalendarFile {
    public static func encode(_ appointment: Appointment) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let fields = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//DD//Appointment Scheduler//EN",
            "CALSCALE:GREGORIAN", "BEGIN:VEVENT",
            "UID:\(appointment.id.uuidString)@com.dd.appointmentscheduler",
            "DTSTAMP:\(formatter.string(from: appointment.modifiedAt))",
            "DTSTART:\(formatter.string(from: appointment.start))",
            "DTEND:\(formatter.string(from: appointment.end))",
            "SUMMARY:\(escape(appointment.serviceName + " — " + appointment.client))",
            "DESCRIPTION:\(escape(appointment.notes))",
            "STATUS:\(appointment.status == .cancelled ? "CANCELLED" : appointment.status == .tentative ? "TENTATIVE" : "CONFIRMED")",
            "END:VEVENT", "END:VCALENDAR",
        ]
        return fields.map(fold).joined(separator: "\r\n") + "\r\n"
    }
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
            of: "\r\n", with: "\n"
        ).replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: ",", with: "\\,")
    }
    // RFC 5545 lines fold at 75 octets without splitting a UTF-8 scalar.
    private static func fold(_ line: String) -> String {
        var output = ""
        var length = 0
        for scalar in line.unicodeScalars {
            let text = String(scalar)
            let bytes = text.utf8.count
            if length + bytes > 75 {
                output += "\r\n "
                length = 1
            }
            output += text
            length += bytes
        }
        return output
    }
}
