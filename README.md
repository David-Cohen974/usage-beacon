# UsageBeacon

UsageBeacon is a native macOS menu bar app for tracking AI vendor usage budgets without living inside vendor dashboards all day.

It keeps a live view of:

- Remaining monthly budget
- Remaining spend per working day
- Today's spend when the provider exposes it
- Last prompt cost when the provider exposes it

The app runs as a menu bar extra, supports an always-on-top floating HUD, and can adjust daily runway using your selected macOS calendars for vacations and holidays.

## Status

UsageBeacon is ready for local use and contributor-friendly development. The codebase is structured, tested, and documented for open-source publication.

Before publishing the repository publicly, choose the license you want to ship with and add a `LICENSE` file. That is an owner decision and is intentionally not assumed in this repository.

## Features

- Native SwiftUI macOS interface with menu bar and floating HUD modes
- Calendar-aware per-working-day budget math
- Dark mode support
- Retry and backoff protection around provider refreshes
- Secure secret storage in the macOS Keychain
- Extensible provider model for adding new vendors or custom endpoints

## Connector Matrix

| Provider | Auth model | Admin required | Supported metrics |
| --- | --- | --- | --- |
| `Cursor Personal` | Signed-in web session | No | Monthly spend, remaining, per-workday runway, best-effort today spend |
| `Cursor Admin` | Team admin API key | Yes | Monthly spend, remaining, today spend, last prompt cost |
| `Anthropic Admin` | Admin API key | Yes | Monthly spend, remaining, today spend |
| `Manual Budget` | None | No | Monthly spend, remaining, today spend, last prompt cost |
| `Custom REST` | Configurable HTTP endpoint | Depends on your endpoint | Any mapped fields the endpoint exposes |

## Requirements

- macOS 14 or newer
- Swift 6 toolchain / Xcode 16 or newer

## Quick Start

### Run from source

```bash
swift run UsageBeaconApp
```

### Build the app bundle

```bash
./Scripts/build-app.sh debug
open dist/UsageBeacon.app
```

### Rebuild and relaunch during development

```bash
./Scripts/rebuild-and-open.sh
```

The built app runs as a menu bar app instead of appearing in the Dock.

## Setup Notes

### Cursor Personal

1. Add a `Cursor Personal` provider.
2. Click `Connect`.
3. Sign in to Cursor in the session window UsageBeacon opens.
4. Leave that window on Cursor's usage page.
5. Return to UsageBeacon and refresh.

If Cursor does not expose a reliable dollar cap, set `Budget Override USD` so UsageBeacon can still calculate remaining runway.

### Anthropic

The current built-in Anthropic connector is `Anthropic Admin`, which uses Anthropic's organization admin cost-report API. A normal Console API key is not enough for this adapter.

## Development

### Test

```bash
swift test --jobs 1
```

### Project Layout

- `Sources/UsageBeaconApp/Models`: provider configuration and runtime snapshot models
- `Sources/UsageBeaconApp/Providers`: vendor-specific adapters and parsers
- `Sources/UsageBeaconApp/Services`: persistence, calendar math, session management, HTTP, HUD windowing
- `Sources/UsageBeaconApp/UI`: SwiftUI views and design system
- `Tests/UsageBeaconAppTests`: provider, parser, and configuration tests
- `Scripts`: local build and relaunch helpers
- `docs`: contributor documentation and architecture notes

## Security and Privacy

- Provider secrets are stored in the macOS Keychain.
- Calendar access is optional and only used for working-day calculations.
- UsageBeacon does not require a backend service; data is fetched directly from vendor endpoints or signed-in local sessions.
- Some personal connectors depend on vendor web UI structure and private session endpoints, so they may require maintenance when vendors change their dashboards.

See [SECURITY.md](SECURITY.md) for disclosure guidance.

## Known Limitations

- `Cursor Personal` depends on Cursor's signed-in web UI staying recognizable enough to parse.
- The current Anthropic adapter is admin-only; there is no non-admin Anthropic session connector yet.
- Anthropic's admin cost report is daily, so last-prompt cost is not available through the built-in adapter.

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

UsageBeacon is available under the [MIT License](LICENSE).

## Disclaimer

UsageBeacon is an independent open-source project and is not affiliated with Cursor or Anthropic.
