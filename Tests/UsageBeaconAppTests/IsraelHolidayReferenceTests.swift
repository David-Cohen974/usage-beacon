import Foundation
import Testing
@testable import UsageBeaconApp

struct IsraelHolidayReferenceTests {
    // Independent fixture: Hebcal Israel Yom Tov API, retrieved 2026-09-08.
    // https://www.hebcal.com/hebcal?v=1&cfg=json&year=2024&ny=7&maj=on&yto=on&i=on
    // Covers ordinary/leap Hebrew years. Tests use no network or user calendar data.
    private let referenceDates = """
    2024-04-23
    2024-04-29
    2024-06-12
    2024-10-03
    2024-10-04
    2024-10-12
    2024-10-17
    2024-10-24
    2025-04-13
    2025-04-19
    2025-06-02
    2025-09-23
    2025-09-24
    2025-10-02
    2025-10-07
    2025-10-14
    2026-04-02
    2026-04-08
    2026-05-22
    2026-09-12
    2026-09-13
    2026-09-21
    2026-09-26
    2026-10-03
    2027-04-22
    2027-04-28
    2027-06-11
    2027-10-02
    2027-10-03
    2027-10-11
    2027-10-16
    2027-10-23
    2028-04-11
    2028-04-17
    2028-05-31
    2028-09-21
    2028-09-22
    2028-09-30
    2028-10-05
    2028-10-12
    2029-03-31
    2029-04-06
    2029-05-20
    2029-09-10
    2029-09-11
    2029-09-19
    2029-09-24
    2029-10-01
    2030-04-18
    2030-04-24
    2030-06-07
    2030-09-28
    2030-09-29
    2030-10-07
    2030-10-12
    2030-10-19
    """

    @Test(arguments: ["Asia/Jerusalem", "America/New_York", "Pacific/Auckland"])
    func fullHolidayDatesMatchIndependentReference(timeZone: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZone))
        let start = try #require(calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)))
        let end = try #require(calendar.date(from: DateComponents(year: 2031, month: 1, day: 1)))
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let actual = Set(WorkingDayService.israelYomTovDays(from: start, until: end, calendar: calendar)
            .keys.map { formatter.string(from: $0) })
        let expected = Set(referenceDates.split(whereSeparator: \.isWhitespace).map(String.init))
        #expect(actual == expected)
    }

    @Test
    func septemberKeepsFastsEvesAndIntermediateDaysWorking() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Jerusalem"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let holidays = WorkingDayService.israelYomTovDays(from: start, until: end, calendar: calendar)
        let holidayDays = Set(holidays.keys.map { calendar.component(.day, from: $0) })
        #expect(holidayDays == [12, 13, 21, 26])
        var settings = GlobalSettings()
        settings.workingWeekSchedule = .sundayStart
        #expect(WorkingDayService.remainingWorkingDays(from: start, until: end,
            blockedDays: Set(holidays.keys), settings: settings, calendar: calendar) == 15)
        for day in [9, 10, 14, 20, 27, 28, 29, 30] {
            #expect(!holidayDays.contains(day))
        }
        let vacationDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        #expect(WorkingDayService.remainingWorkingDays(from: start, until: end,
            blockedDays: Set(holidays.keys).union([vacationDay]), settings: settings, calendar: calendar) == 14)
    }

    @Test
    @MainActor
    func selectedFullHolidayScheduleWorksWithoutCalendarFeedAndDeduplicates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Jerusalem"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        var settings = GlobalSettings()
        settings.workingWeekSchedule = .sundayStart
        settings.calendarExclusionModes = ["missing-feed-a": .israelYomTov, "missing-feed-b": .israelYomTov]
        let service = WorkingDayService(calendar: calendar)
        #expect(service.remainingWorkingDays(from: start, until: end,
            selectedCalendarIDs: ["missing-feed-a", "missing-feed-b"], settings: settings) == 15)
        #expect(service.remainingWorkingDays(from: start, until: end, selectedCalendarIDs: [], settings: settings) == 17)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(GlobalSettings.self, from: data).calendarExclusionModes == settings.calendarExclusionModes)
    }

    @Test
    func holidayModeDoesNotTurnArbitraryEntriesIntoAbsences() {
        let event = WorkingDayEvent(start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86400), availability: .busy, mode: .israelYomTov)
        #expect(!event.excludesWorkingDay)
    }
}
