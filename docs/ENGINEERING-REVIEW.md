# Engineering assessment — 2026-09-08

## Verdict

The product has useful architectural foundations, but the available evidence does not justify a full production-readiness sign-off. Passing tests establish the cases they execute; they do not establish that other features are unaffected. The workday report exposed a missing business-rule test, not just a missing edge case.

## Baseline test coverage

Measured locally using `swift test --jobs 4 --enable-code-coverage` before correcting the calendar classification. All 53 tests passed.

| Instrumented area | Lines exercised |
| --- | ---: |
| Own sources present in the report, including UI | 25.6% |
| Same sources excluding UI | 49.0% |
| AppModel | 50.7% |
| WorkingDayService | 47.1% |
| ConfigurationStore | 80.4% |
| HTTPClient | 8.6% |
| UpdaterController | 4.3% |
| Cursor dashboard session | 27.8% |
| Claude dashboard session | 33.2% |
| Shared widget store | 54.3% |

These are line-coverage measurements, not correctness probabilities. The WidgetKit extension itself is not exercised by this test target. The separate-process widget-store check runs outside this coverage measurement. SwiftUI and generated code also influence the totals.

Existing strengths: parser fixtures for each provider, configuration compatibility and corruption preservation, schedule math, successive app-to-file refreshes, late provider responses, and basic publishing failures.

Missing acceptance evidence: actual widget rendering assertions, automatic update installation and rollback, signed permission transitions, credential/session expiry and recovery, sleep/wake/midnight/time-zone changes, and a supported-macOS test matrix.

## Code assessment

Useful foundations:

- Typed provider configuration and normalized snapshots separate vendor parsing from budget math.
- UI-facing state is isolated to the main actor.
- Secrets use Keychain and are excluded from shared widget data.
- Configuration writes are atomic, and unreadable configuration is preserved.
- Provider failures have explicit categories and bounded retry counts.

Findings:

1. Calendar selection previously treated every all-day event as time off. Tests passed already-blocked dates to the counter, bypassing EventKit event classification. An all-day entry is not evidence that the user is unavailable.
2. Both dashboard page loaders await navigation completion before starting their 15-second content timeout. There is no application-owned deadline or cancellation handler around that first wait. A stalled navigation callback can retain a provider's in-flight refresh slot. This needs a tested deadline covering the whole load.
3. AppModel owns refreshes, calendars, persistence, lifecycle observers, telemetry, HUD, and widget publication. Its injectable services help, but the real calendar event adapter and several singleton session paths remain difficult to isolate in tests.
4. A successful WidgetKit timeline log and an atomic file-store test are useful evidence, but neither verifies what a user sees after an upgrade. Signed UI acceptance remains necessary.

## Priority before a public release

1. Completed: correct calendar event classification and verify it against real calendar data and synthetic event fixtures.
2. Add and test complete navigation deadlines and cancellation, plus provider independence during stalls.
3. Cover transport status/retry behavior and updater failure paths with injected transports.
4. Run and record signed upgrade, permission, widget rendering, and lifecycle acceptance on supported macOS versions.

Avoid raising a coverage percentage by testing trivial formatting while these scenarios remain untested. Prefer tests that fail for the actual historical regressions and the reported business behavior.

## Calendar policy

Ordinary calendars can exclude busy/unavailable all-day events; Free entries remain workdays. Dedicated time-off calendars can explicitly exclude every all-day entry. Cancelled, declined, timed, birthday, and invalid events are rejected. End times at 23:59:59 retain their final civil day.

The opt-in Israel full-holiday mode uses Hebrew calendar dates rather than event titles. It excludes Tishrei 1, 2, 10, 15, 22; Nisan 15, 21; and Sivan 6. Minor fasts, holiday eves, intermediate days, and national observances remain scheduled unless recorded separately as time off. The diaspora schedule differs. Overlapping holidays and vacation are deducted only once and only on configured working weekdays.

Tests compare 56 independently sourced Israel holiday dates for 2024–2030 across three time zones. Legacy calendar selections retain their previous policy until users explicitly select a different rule.
