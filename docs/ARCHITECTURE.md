# Architecture

## Overview

UsageBeacon is a native macOS SwiftUI app with a local-first architecture:

- `AppModel` owns configuration, refresh orchestration, and UI-facing state
- `ProviderResolver` dispatches to one provider adapter per connector type
- Provider adapters return normalized `RawBudgetSnapshot` values
- `AppModel` enriches snapshots with working-day math and publishes `ProviderSnapshotState`
- `AppModel` publishes a privacy-safe snapshot to the shared app-group store
- `TelemetryController` owns explicit-consent Firebase initialization and sanitized diagnostics
- SwiftUI views render the menu, HUD, settings, and WidgetKit surfaces from those snapshot states

## Main layers

### Models

`Sources/UsageBeaconApp/Models`

- Provider configuration
- Global settings
- Snapshot structs shared across the app

### Providers

`Sources/UsageBeaconApp/Providers`

Each provider is responsible for:

- Validating its own configuration
- Calling its own endpoint or local session source
- Returning normalized budget data
- Explaining connector limitations in `notes`

Providers should not own calendar math or view logic.

### Services

`Sources/UsageBeaconApp/Services`

Service objects handle:

- Configuration persistence
- Keychain persistence
- Calendar access and working-day calculations
- Floating HUD window lifecycle
- Login-item registration and wake/display lifecycle recovery
- Cursor signed-in session management
- HTTP transport
- Disclosed-by-default crash reporting for new installations, plus opt-in anonymous product analytics

### Telemetry boundary

`TelemetryController` is the only production layer that imports Firebase. Crash reporting is enabled for genuinely new installations and shown in a first-launch disclosure with an immediate opt-out; decoded legacy configurations retain their saved or prior off state. Usage analytics remain off by default and use a separate preference. `AppModel` sends typed events containing only connector kinds, feature flags, coarse duration buckets, retry counts, and sanitized failure categories. Only unexpected or parsing failures become Crashlytics non-fatals, avoiding noise from ordinary authentication, network, and rate-limit conditions. Raw errors, URLs, credentials, account identifiers, provider payloads, budgets, spending, limits, and token usage must never cross this boundary. Firebase is linked only to the main app target, not the widget extension. A hidden, environment-gated developer command can generate a controlled Crashlytics verification crash for release validation.

### UI

`Sources/UsageBeaconApp/UI`

The UI layer is intentionally thin:

- `MenuBarRootView` renders the menu bar window
- `FloatingHUDView` renders the condensed always-on-top surface
- `SettingsView` renders provider configuration and app settings
- `BeaconDesignSystem` centralizes palette and reusable visual components

### Widget extension

`Sources/UsageBeaconWidget` renders small, medium, and large WidgetKit layouts for the desktop and Notification Center. `Sources/UsageBeaconShared` contains the narrow Codable snapshot contract shared by the app and widget. The app and extension use the macOS team-scoped `Y3XM9Q3AZT.com.rekindle.usagebeacon` group container. Snapshots are committed atomically to `widget-snapshot.json` before requesting a WidgetKit reload. The extension reads the file on every timeline request; legacy shared preferences are read only before the first file is created. Write failures are reported in the menu. Secrets and provider credentials never enter the shared snapshot.

Workday calculations run locally when schedules or calendars change and before periodic refreshes, even if a provider is offline. Refreshes run independently across providers. Results from a request whose provider configuration changed or was removed are discarded. Failed requests preserve the timestamp of the last successful data.

CI tests successive provider refreshes through the shared file, schedule changes, failure timestamps, provider removal, and persistence failures. `Scripts/verify-widget-store.sh` also checks ten writes against a separate, persistent reader process. These tests do not substitute for the signed WidgetKit checks in `docs/STABILITY.md`.

## Extension points

To add a new provider:

1. Add the new case to `ProviderKind`
2. Add its configuration model
3. Implement a provider adapter that returns `RawBudgetSnapshot`
4. Wire it into `ProviderResolver`
5. Add settings UI in `SettingsView`
6. Add tests for parsing and edge cases

## Design principles

- Native macOS first
- Local-first secret handling
- Readable provider failures
- Best-effort parsing only where no supported API exists
- Minimal hidden behavior

### Calendar exclusion rules

`WorkingDayEvent` separates event classification from EventKit access. Selected calendars use `busyAllDay` by default. Dedicated holiday/time-off calendars can explicitly use `allDay`; the latter includes Free/unsupported-availability entries. Cancelled, declined, birthday and timed events are never whole-day exclusions. The selected mode is stored per calendar in `GlobalSettings.calendarExclusionModes` and shown in Settings. Date expansion is half-open and preserves 23:59:59 provider end times rather than flooring them to midnight.

`israelYomTov` is a separate, explicit calendar mode for full Jewish holidays in Israel. It generates full civil-day exclusions from Foundation's Hebrew calendar and ignores arbitrary feed entries. It works without a network feed or EventKit read permission, while selected personal-calendar rules still require EventKit. Duplicate feeds do not multiply deductions. Eves, minor fasts, Chol HaMoed and national observances are not full-day exclusions in this mode. Independent multi-year Hebcal fixtures validate the date set.
