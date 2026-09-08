import Foundation
import EventKit
import Testing
@testable import UsageBeaconApp

struct WorkingDayServiceTests {
    @Test
    func freeMonthLongWorkEntryDoesNotEraseWorkingDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Jerusalem"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 8)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let entry = WorkingDayEvent(start: start.addingTimeInterval(-10 * 86_400), end: end,
                                    availability: .free)
        let blocked = WorkingDayService.blockedDays(events: [entry], from: start, until: end, calendar: calendar)
        var settings = GlobalSettings()
        settings.workingWeekSchedule = .sundayStart
        #expect(blocked.isEmpty)
        #expect(WorkingDayService.remainingWorkingDays(from: start, until: end,
            blockedDays: blocked, settings: settings, calendar: calendar) == 17)
    }

    @Test(arguments: [EKEventAvailability.free, .notSupported, .tentative])
    func informationalEventsRequireDedicatedTimeOffMode(availability: EKEventAvailability) {
        var event = WorkingDayEvent(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400),
                                    availability: availability)
        #expect(!event.excludesWorkingDay)
        event.mode = .allDay
        #expect(event.excludesWorkingDay)
    }

    @Test(arguments: [EKEventAvailability.busy, .unavailable])
    func busyAndUnavailableAllDayEventsAreExcluded(availability: EKEventAvailability) {
        let event = WorkingDayEvent(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400),
                                    availability: availability)
        #expect(event.excludesWorkingDay)
    }

    @Test
    func canceledDeclinedBirthdayAndTimedEventsNeverExcludeWholeDays() {
        let base = WorkingDayEvent(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400), mode: .allDay)
        var canceled = base; canceled.isCanceled = true
        var declined = base; declined.isDeclined = true
        var birthday = base; birthday.isBirthday = true
        var timed = base; timed.isAllDay = false
        var invalid = base; invalid.end = invalid.start
        #expect([canceled, declined, birthday, timed, invalid].allSatisfy { !$0.excludesWorkingDay })
    }

    @Test(arguments: [0.0, -1.0])
    func holidayIncludesItsDayForMidnightAndLastSecondEnd(endOffset: Double) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Jerusalem"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21)))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let holiday = WorkingDayEvent(start: start, end: tomorrow.addingTimeInterval(endOffset), availability: .free, mode: .allDay)
        let blocked = WorkingDayService.blockedDays(events: [holiday, holiday], from: start,
                                                     until: tomorrow, calendar: calendar)
        #expect(blocked == [start])
    }

    @Test(arguments: [3, 11])
    func absencesUseCalendarDaysAcrossDaylightSaving(month: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let day = month == 3 ? 7 : 1
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
        let end = try #require(calendar.date(byAdding: .day, value: 3, to: start))
        let absence = WorkingDayEvent(start: start, end: end)
        #expect(WorkingDayService.blockedDays(events: [absence], from: start, until: end, calendar: calendar).count == 3)
        let clippedStart = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        #expect(WorkingDayService.blockedDays(events: [absence], from: clippedStart, until: end, calendar: calendar).count == 2)
    }

    @Test
    func calendarModesPersistAndLegacySelectionsKeepTheirRule() throws {
        var settings = GlobalSettings()
        settings.calendarExclusionModes = ["holidays": .allDay, "work": .busyAllDay]
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(GlobalSettings.self, from: data).calendarExclusionModes == settings.calendarExclusionModes)
        let legacy = try JSONDecoder().decode(GlobalSettings.self, from: Data("{}".utf8))
        #expect(legacy.calendarExclusionModes.isEmpty)
        let selectedLegacy = try JSONDecoder().decode(GlobalSettings.self,
            from: Data(#"{"selectedCalendarIDs":["holidays","holidays"]}"#.utf8))
        #expect(selectedLegacy.calendarExclusionModes == ["holidays": .allDay])
    }

}
