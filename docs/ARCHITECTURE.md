# Architecture

## Overview

UsageBeacon is a native macOS SwiftUI app with a local-first architecture:

- `AppModel` owns configuration, refresh orchestration, and UI-facing state
- `ProviderResolver` dispatches to one provider adapter per connector type
- Provider adapters return normalized `RawBudgetSnapshot` values
- `AppModel` enriches snapshots with working-day math and publishes `ProviderSnapshotState`
- SwiftUI views render the menu, HUD, and settings surfaces from those snapshot states

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
- Cursor signed-in session management
- HTTP transport

### UI

`Sources/UsageBeaconApp/UI`

The UI layer is intentionally thin:

- `MenuBarRootView` renders the menu bar window
- `FloatingHUDView` renders the condensed always-on-top surface
- `SettingsView` renders provider configuration and app settings
- `BeaconDesignSystem` centralizes palette and reusable visual components

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
