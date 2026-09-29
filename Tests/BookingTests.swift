import XCTest

@testable import SchedulerCore

final class BookingTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
    }
    func testAdjacentBookingsDoNotOverlap() throws {
        let first = Appointment(client: "A", start: monday)
        try BookingRules.validate(
            Appointment(client: "B", start: first.end), among: [first], calendar: calendar)
        XCTAssertThrowsError(
            try BookingRules.validate(
                Appointment(client: "B", start: monday.addingTimeInterval(15 * 60)), among: [first],
                calendar: calendar))
    }
    func testEditingIgnoresOwnBookingAndCancellationReleasesSlot() throws {
        var first = Appointment(client: "A", start: monday)
        try BookingRules.validate(first, among: [first], calendar: calendar)
        first.status = .cancelled
        try BookingRules.validate(
            Appointment(client: "B", start: monday), among: [first], calendar: calendar)
    }
    func testTentativeBookingsAlsoBlockTime() {
        let tentative = Appointment(client: "A", start: monday, status: .tentative)
        XCTAssertThrowsError(
            try BookingRules.validate(
                Appointment(client: "B", start: monday), among: [tentative], calendar: calendar))
    }
    func testWorkingHoursIncludeFullDurationAndRejectWeekends() {
        XCTAssertThrowsError(
            try BookingRules.validate(
                Appointment(client: "A", start: monday.addingTimeInterval(7.75 * 3600)), among: [],
                calendar: calendar))
        XCTAssertNil(
            BookingRules.businessHours(on: monday.addingTimeInterval(-86400), calendar: calendar))
    }
    func testSlotsExcludeOverlapsAndPastTimes() {
        let existing = Appointment(client: "A", start: monday)
        let slots = BookingRules.availableSlots(
            on: monday, minutes: 30, appointments: [existing], now: monday.addingTimeInterval(900),
            calendar: calendar)
        XCTAssertEqual(slots.first, existing.end)
        XCTAssertEqual(slots.last, monday.addingTimeInterval(7.5 * 3600))
    }
    func testCalendarExportUsesUTCAndEscapesInjectedFields() {
        let item = Appointment(client: "A, B", start: monday, notes: "Hello; world\nBEGIN:VEVENT")
        let text = CalendarFile.encode(item)
        XCTAssertTrue(text.contains("DTSTART:20261005T090000Z\r\n"))
        XCTAssertTrue(text.contains("Hello\\; world\\nBEGIN:VEVENT"))
        XCTAssertEqual(text.components(separatedBy: "\r\nBEGIN:VEVENT").count, 2)
    }
    func testCalendarFoldingPreservesUnicodeAndOctetLimit() {
        let item = Appointment(client: String(repeating: "旅", count: 80), start: monday)
        let text = CalendarFile.encode(item)
        XCTAssertTrue(text.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        XCTAssertTrue(text.replacingOccurrences(of: "\r\n ", with: "").contains(item.client))
    }
    func testPersistedAppointmentRetainsIdentityAndStatus() throws {
        let item = Appointment(client: "A", start: monday, status: .tentative, reminder: true)
        XCTAssertEqual(
            try JSONDecoder().decode(Appointment.self, from: JSONEncoder().encode(item)), item)
    }
}
