import AppKit
import EventKit
import Foundation

enum CalendarAccessState: Equatable {
    case notDetermined
    case fullAccess
    case writeOnly
    case denied
    case restricted
    case unknown

    var canReadEvents: Bool {
        self == .fullAccess
    }
}

// A value representation keeps event classification and date arithmetic testable
// without reading or changing a user's calendars.
struct WorkingDayEvent {
    var start: Date
    var end: Date
    var isAllDay: Bool = true
    var availability: EKEventAvailability = .busy
    var isCanceled: Bool = false
    var isDeclined: Bool = false
    var isBirthday: Bool = false
    var mode: CalendarExclusionMode = .busyAllDay

    var excludesWorkingDay: Bool {
        guard isAllDay, !isCanceled, !isDeclined, !isBirthday, start < end else { return false }
        switch mode {
        case .busyAllDay: return availability == .busy || availability == .unavailable
        case .allDay: return true
        case .israelYomTov: return false // Calculated from Hebrew dates, not event titles.
        }
    }
}

@MainActor
final class WorkingDayService {
    private let eventStore = EKEventStore()
    private let calendar: Calendar
    private var eventStoreChangedObserver: NSObjectProtocol?
    private var pendingCalendarChangeTask: Task<Void, Never>?

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    var isAuthorized: Bool {
        authorizationState.canReadEvents
    }

    var authorizationState: CalendarAccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .authorized:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    func requestAccess() async throws -> CalendarAccessState {
        switch authorizationState {
        case .fullAccess:
            eventStore.reset()
            return .fullAccess
        case .notDetermined:
            _ = try await Self.requestFullAccess()
            eventStore.reset()
            return authorizationState
        case .writeOnly, .denied, .restricted, .unknown:
            return authorizationState
        }
    }

    func availableCalendars(refreshStore: Bool = false) -> [CalendarSource] {
        guard isAuthorized else {
            return []
        }
        if refreshStore {
            eventStore.reset()
        }

        return eventStore.calendars(for: .event)
            .map {
                CalendarSource(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    colorHex: $0.cgColor.hexString
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func remainingWorkingDays(
        from now: Date,
        until cycleEnd: Date,
        selectedCalendarIDs: [String],
        settings: GlobalSettings
    ) -> Int {
        guard now < cycleEnd else { return 0 }
        let localCalendar = calendar

        let start = localCalendar.startOfDay(for: now)
        let end = cycleEnd
        guard start < end else {
            return 0
        }

        let blockedDays = blockedDaySet(
            from: start,
            until: end,
            selectedCalendarIDs: selectedCalendarIDs,
            settings: settings,
            calendar: localCalendar
        )

        return Self.remainingWorkingDays(
            from: start,
            until: end,
            blockedDays: blockedDays,
            settings: settings,
            calendar: localCalendar
        )
    }

    func startObservingCalendarChanges(onChange: @escaping @MainActor () -> Void) {
        stopObservingCalendarChanges()
        eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in
                guard let self else {
                    return
                }

                self.pendingCalendarChangeTask?.cancel()
                self.pendingCalendarChangeTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard Task.isCancelled == false else {
                        return
                    }
                    onChange()
                }
            }
        }
    }

    func stopObservingCalendarChanges() {
        pendingCalendarChangeTask?.cancel()
        pendingCalendarChangeTask = nil
        if let eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(eventStoreChangedObserver)
            self.eventStoreChangedObserver = nil
        }
    }

    nonisolated static func remainingWorkingDays(
        from start: Date,
        until end: Date,
        blockedDays: Set<Date>,
        settings: GlobalSettings,
        calendar: Calendar
    ) -> Int {
        guard start < end else {
            return 0
        }

        var count = 0
        var cursor = calendar.startOfDay(for: start)
        while cursor < end {
            if isConfiguredWorkingDay(
                cursor,
                settings: settings,
                calendar: calendar
            ) && !blockedDays.contains(cursor) {
                count += 1
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end
        }

        return count
    }

    nonisolated static func isConfiguredWorkingDay(
        _ date: Date,
        settings: GlobalSettings,
        calendar: Calendar
    ) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return workingWeekdayNumbers(
            settings: settings,
            referenceDate: date,
            calendar: calendar
        ).contains(weekday)
    }

    nonisolated static func workingWeekdayNumbers(
        settings: GlobalSettings,
        referenceDate: Date,
        calendar: Calendar
    ) -> Set<Int> {
        let clampedCount = settings.effectiveWorkingDaysPerWeek

        switch settings.workingWeekSchedule {
        case .mondayStart:
            return Set(orderedWeekdays(startingWith: 2).prefix(clampedCount))
        case .sundayStart:
            return Set(orderedWeekdays(startingWith: 1).prefix(clampedCount))
        case .custom:
            return Set(settings.normalizedCustomWorkingWeekdays)
        case .systemDefault:
            break
        }

        let weekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
            ?? calendar.startOfDay(for: referenceDate)

        var nonWeekendWeekdays: [Int] = []
        var weekendWeekdays: [Int] = []

        for offset in 0 ..< 7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                continue
            }
            let weekday = calendar.component(.weekday, from: date)
            if calendar.isDateInWeekend(date) {
                weekendWeekdays.append(weekday)
            } else {
                nonWeekendWeekdays.append(weekday)
            }
        }

        let orderedWeekdays = nonWeekendWeekdays + weekendWeekdays
        return Set(orderedWeekdays.prefix(clampedCount))
    }

    nonisolated static func orderedWeekdays(startingWith firstWeekday: Int) -> [Int] {
        guard (1 ... 7).contains(firstWeekday) else {
            return Array(1 ... 7)
        }

        return (0 ..< 7).map { offset in
            ((firstWeekday - 1 + offset) % 7) + 1
        }
    }

    private func blockedDaySet(
        from start: Date,
        until end: Date,
        selectedCalendarIDs: [String],
        settings: GlobalSettings,
        calendar: Calendar
    ) -> Set<Date> {
        let usesIsraelSchedule = selectedCalendarIDs.contains {
            settings.calendarExclusionModes[$0] == .israelYomTov
        }
        let scheduledHolidays = usesIsraelSchedule
            ? Set(Self.israelYomTovDays(from: start, until: end, calendar: calendar).keys)
            : Set<Date>()
        guard
            isAuthorized,
            !selectedCalendarIDs.isEmpty
        else {
            return scheduledHolidays
        }

        let selected = Set(selectedCalendarIDs)
        let calendars = eventStore.calendars(for: .event).filter {
            selected.contains($0.calendarIdentifier)
                && settings.calendarExclusionModes[$0.calendarIdentifier] != .israelYomTov
        }
        guard !calendars.isEmpty else {
            return scheduledHolidays
        }

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )
        let events = eventStore.events(matching: predicate).map { event in
            WorkingDayEvent(
                start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                availability: event.availability, isCanceled: event.status == .canceled,
                isDeclined: event.attendees?.contains {
                    $0.isCurrentUser && $0.participantStatus == .declined
                } ?? false,
                isBirthday: event.calendar.type == .birthday || event.birthdayContactIdentifier != nil,
                mode: settings.calendarExclusionModes[event.calendar.calendarIdentifier] ?? .busyAllDay
            )
        }
        return scheduledHolidays.union(Self.blockedDays(events: events, from: start, until: end, calendar: calendar))
    }

    // Full-day budget exclusions, using the Israel (not diaspora) Yom Tov schedule.
    // Hebrew dates avoid dependence on translated calendar titles or incomplete feeds.
    // Foundation reserves month 7 for Adar II, so Nisan is 8 and Sivan is 10 in both
    // ordinary and leap years. Reference fixtures are checked against Hebcal Yom Tov.
    nonisolated static func israelYomTovDays(
        from start: Date, until end: Date, calendar: Calendar
    ) -> [Date: String] {
        guard start < end else { return [:] }
        var hebrew = Calendar(identifier: .hebrew)
        hebrew.timeZone = calendar.timeZone
        var dates: [Date: String] = [:]
        var day = calendar.startOfDay(for: start)
        while day < end {
            let parts = hebrew.dateComponents([.month, .day], from: day)
            let name: String?
            switch (parts.month, parts.day) {
            case (1, 1): name = "Rosh Hashanah — day 1"
            case (1, 2): name = "Rosh Hashanah — day 2"
            case (1, 10): name = "Yom Kippur"
            case (1, 15): name = "Sukkot — first day"
            case (1, 22): name = "Shemini Atzeret / Simchat Torah"
            case (8, 15): name = "Passover — first day"
            case (8, 21): name = "Passover — seventh day"
            case (10, 6): name = "Shavuot"
            default: name = nil
            }
            if let name { dates[day] = name }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return dates
    }

    nonisolated static func blockedDays(
        events: [WorkingDayEvent], from start: Date, until end: Date, calendar: Calendar
    ) -> Set<Date> {
        guard start < end else { return [] }
        let firstDay = calendar.startOfDay(for: start)
        var blocked: Set<Date> = []
        for event in events where event.excludesWorkingDay {
            let clippedEnd = min(event.end, end)
            var day = calendar.startOfDay(for: max(event.start, firstDay))
            // Keep the actual exclusive end instant. Some providers use 23:59:59,
            // others use next-day midnight; both must include the final occupied day.
            while day < clippedEnd {
                blocked.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                day = next
            }
        }
        return blocked
    }

    nonisolated private static func requestFullAccess() async throws -> Bool {
        let permissionStore = EKEventStore()
        return try await withCheckedThrowingContinuation { continuation in
            let resumer = CalendarAccessRequestResumer(
                continuation: continuation,
                eventStore: permissionStore
            )
            permissionStore.requestFullAccessToEvents { granted, error in
                resumer.resume(granted: granted, error: error)
            }
        }
    }

}

private final class CalendarAccessRequestResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, any Error>?
    private var eventStore: EKEventStore?

    init(
        continuation: CheckedContinuation<Bool, any Error>,
        eventStore: EKEventStore
    ) {
        self.continuation = continuation
        self.eventStore = eventStore
    }

    func resume(granted: Bool, error: (any Error)?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        eventStore = nil
        lock.unlock()

        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: granted)
        }
    }
}

private extension CGColor {
    var hexString: String {
        guard
            let components = components,
            components.count >= 3
        else {
            return "#999999"
        }

        let red = Int((components[0] * 255).rounded())
        let green = Int((components[1] * 255).rounded())
        let blue = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
