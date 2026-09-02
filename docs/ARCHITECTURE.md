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
- Opt-in crash reporting and anonymous product analytics

### Telemetry boundary

`TelemetryController` is the only layer that imports Firebase. Crash reporting and usage analytics have separate, off-by-default preferences. `AppModel` sends typed events containing only connector kinds, feature flags, coarse duration buckets, retry counts, and sanitized failure categories. Only unexpected or parsing failures become Crashlytics non-fatals, avoiding noise from ordinary authentication, network, and rate-limit conditions. Raw errors, URLs, credentials, account identifiers, provider payloads, budgets, spending, limits, and token usage must never cross this boundary. Firebase is linked only to the main app target, not the widget extension.

### UI

`Sources/UsageBeaconApp/UI`

The UI layer is intentionally thin:

- `MenuBarRootView` renders the menu bar window
- `FloatingHUDView` renders the condensed always-on-top surface
- `SettingsView` renders provider configuration and app settings
- `BeaconDesignSystem` centralizes palette and reusable visual components

### Widget extension

`Sources/UsageBeaconWidget` renders small, medium, and large WidgetKit layouts for the desktop and Notification Center. `Sources/UsageBeaconShared` contains the narrow Codable snapshot contract shared by the app and widget. The app and extension use the macOS team-scoped `Y3XM9Q3AZT.com.rekindle.usagebeacon` group container. Secrets and provider credentials never enter the shared snapshot.

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
