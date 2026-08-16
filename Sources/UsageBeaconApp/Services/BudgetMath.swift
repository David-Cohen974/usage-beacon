import Foundation

enum BudgetMath {
    static func billingCycle(
        resetDay: Int,
        now: Date,
        calendar baseCalendar: Calendar = .current
    ) -> DateInterval {
        var calendar = baseCalendar
        calendar.timeZone = .current
        let day = max(1, min(resetDay, 28))
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now

        let currentAnchor = anchorDate(
            monthOffset: 0,
            day: day,
            from: monthStart,
            calendar: calendar
        )
        let start: Date
        let end: Date
        if now >= currentAnchor {
            start = currentAnchor
            end = anchorDate(
                monthOffset: 1,
                day: day,
                from: monthStart,
                calendar: calendar
            )
        } else {
            start = anchorDate(
                monthOffset: -1,
                day: day,
                from: monthStart,
                calendar: calendar
            )
            end = currentAnchor
        }

        return DateInterval(start: start, end: end)
    }

    static func calendarMonthCycle(
        now: Date,
        calendar baseCalendar: Calendar = .current
    ) -> DateInterval {
        var calendar = baseCalendar
        calendar.timeZone = .current
        let start = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func remainingPerWorkingDay(
        remainingUSD: Decimal?,
        workingDaysRemaining: Int?
    ) -> Decimal? {
        guard
            let remainingUSD,
            let workingDaysRemaining,
            workingDaysRemaining > 0
        else {
            return nil
        }
        return remainingUSD / Decimal(workingDaysRemaining)
    }

    static func progress(spent: Decimal?, budget: Decimal?) -> Double {
        guard
            let spent,
            let budget,
            budget > 0
        else {
            return 0
        }

        let value = (spent / budget).doubleValue
        return max(0, min(value, 1))
    }

    private static func anchorDate(
        monthOffset: Int,
        day: Int,
        from monthStart: Date,
        calendar: Calendar
    ) -> Date {
        let shifted = calendar.date(byAdding: .month, value: monthOffset, to: monthStart) ?? monthStart
        var components = calendar.dateComponents([.year, .month], from: shifted)
        components.day = day
        return calendar.date(from: components) ?? shifted
    }
}
