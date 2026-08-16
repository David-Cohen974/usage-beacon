import AppKit
import EventKit
import Foundation

@MainActor
final class WorkingDayService {
    private let eventStore = EKEventStore()
    private let calendar: Calendar
    private var eventStoreChangedObserver: NSObjectProtocol?
    private var pendingCalendarChangeTask: Task<Void, Never>?

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    var isAuthorized: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .fullAccess:
                return true
            case .notDetermined:
                return await Self.requestFullAccess()
            case .writeOnly, .denied, .restricted:
                return false
            @unknown default:
                return false
            }
        } else {
            let status = EKEventStore.authorizationStatus(for: .event)
            switch status {
            case .authorized, .fullAccess:
                return true
            case .notDetermined:
                return await Self.requestLegacyAccess()
            case .writeOnly, .denied, .restricted:
                return false
            @unknown default:
                return false
            }
        }
    }

    func availableCalendars() -> [CalendarSource] {
        guard isAuthorized else {
            return []
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
        var localCalendar = calendar
        localCalendar.timeZone = .current

        let start = localCalendar.startOfDay(for: now)
        let end = localCalendar.startOfDay(for: cycleEnd)
        guard start < end else {
            return 0
        }

        let blockedDays = blockedDaySet(
            from: start,
            until: end,
            selectedCalendarIDs: selectedCalendarIDs,
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
        calendar: Calendar
    ) -> Set<Date> {
        guard
            isAuthorized,
            !selectedCalendarIDs.isEmpty
        else {
            return []
        }

        let selected = Set(selectedCalendarIDs)
        let calendars = eventStore.calendars(for: .event).filter {
            selected.contains($0.calendarIdentifier)
        }
        guard !calendars.isEmpty else {
            return []
        }

        let predicate = eventStore.predicateForEvents(
            withStart: start,
            end: end,
            calendars: calendars
        )
        var blocked: Set<Date> = []
        for event in eventStore.events(matching: predicate) where event.isAllDay {
            var day = calendar.startOfDay(for: event.startDate)
            let eventEnd = calendar.startOfDay(for: event.endDate)
            while day < eventEnd {
                blocked.insert(day)
                day = calendar.date(byAdding: .day, value: 1, to: day) ?? eventEnd
            }
        }
        return blocked
    }

    nonisolated private static func requestFullAccess() async -> Bool {
        let eventStore = EKEventStore()
        return await withCheckedContinuation { continuation in
            let resumer = AccessRequestResumer(continuation)
            eventStore.requestFullAccessToEvents { granted, _ in
                resumer.resume(with: granted)
            }
        }
    }

    nonisolated private static func requestLegacyAccess() async -> Bool {
        let eventStore = EKEventStore()
        return await withCheckedContinuation { continuation in
            let resumer = AccessRequestResumer(continuation)
            eventStore.requestFullAccessToEvents { granted, _ in
                resumer.resume(with: granted)
            }
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

private final class AccessRequestResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(with granted: Bool) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: granted)
    }
}
