# UsageBeacon

UsageBeacon is a native macOS menu bar app for tracking AI vendor usage budgets without living inside vendor dashboards all day.

It keeps a live view of:

- Remaining monthly budget
- Remaining spend per working day
- Today's spend when the provider exposes it
- Last prompt cost when the provider exposes it

The app runs as a menu bar extra, includes macOS Notification Center and desktop widgets, supports an optional always-on-top floating HUD, and can adjust daily runway using your selected macOS calendars for vacations and holidays.

## Status

UsageBeacon is ready for local use and contributor-friendly development. Tagged releases are built, Developer ID signed, notarized, and published automatically with a Sparkle 2 update feed.
It is distributed under the MIT License.

## Features

- Native SwiftUI macOS interface with menu bar, WidgetKit, and floating HUD modes
- Small, medium, and large widgets for Notification Center or the desktop
- System-wide ⇧⌘U shortcut to show or hide the floating HUD
- Launch-at-login support plus automatic HUD recovery after sleep and display changes
- Calendar-aware per-working-day budget math
- Dark mode support
- Retry and backoff protection around provider refreshes
- Secure secret storage in the macOS Keychain
- Extensible provider model for adding new vendors or custom endpoints

## Connector Matrix

| Provider | Auth model | Admin required | Supported metrics |
| --- | --- | --- | --- |
| `Cursor Personal` | Signed-in web session | No | Monthly spend, remaining, per-workday runway, today spend, last prompt cost |
| `Cursor Admin` | Team admin API key | Yes | Monthly spend, remaining, today spend, last prompt cost |
| `Claude Personal` | Signed-in web session | No | 5-hour and 7-day utilization/reset times; personal monthly spend when Member analytics exposes it |
| `Anthropic Admin` | Admin API key | Yes | Monthly spend, remaining, today spend |
| `Manual Budget` | None | No | Monthly spend, remaining, today spend, last prompt cost |
| `Custom REST` | Configurable HTTP endpoint | Depends on your endpoint | Any mapped fields the endpoint exposes |

## Requirements

- macOS 14 or newer
- Swift 6.2.3 toolchain / Xcode 26.2 or newer

## Quick Start

### Install a release

Download the latest signed and notarized DMG from the [UsageBeacon website](https://david-cohen974.github.io/usage-beacon/) or [GitHub Releases](https://github.com/David-Cohen974/usage-beacon/releases). Installed releases can update themselves through Sparkle.

### Run from source

```bash
swift run UsageBeaconApp
```

### Build the app bundle

```bash
./Scripts/build-app.sh debug
ditto -x -k dist/UsageBeacon.zip /Applications
open /Applications/UsageBeacon.app
```

### Rebuild and relaunch during development

```bash
./Scripts/rebuild-and-open.sh
```

The built app runs as a menu bar app instead of appearing in the Dock.
The script creates only `dist/UsageBeacon.zip`. Keeping a second unpacked `.app` in the source folder can make macOS register the wrong widget extension, so install and run the single copy in `/Applications`.

### Add the widget

1. Open Notification Center and choose `Edit Widgets`, or Control-click the desktop and choose `Edit Widgets`.
2. Search for `UsageBeacon`.
3. Add the small, medium, or large widget. The app keeps its data current while it is running.

The floating HUD remains available separately in UsageBeacon's Display settings for people who prefer an always-on-top view. Keep `Launch at login` enabled there to restore the menu bar app and HUD after restarting your Mac.

## Setup Notes

### Cursor Personal

1. Add a `Cursor Personal` provider.
2. Click `Connect`.
3. Sign in to Cursor in the session window UsageBeacon opens.
4. Leave that window on Cursor's usage page.
5. Return to UsageBeacon and refresh.

If Cursor does not expose a reliable dollar cap, set `Budget Override USD` so UsageBeacon can still calculate remaining runway.

### Claude Personal

1. Add a `Claude Personal` provider.
2. Click `Connect`.
3. Sign in to Claude in the session window UsageBeacon opens.
4. Leave that window on `Settings → Usage`.
5. Return to UsageBeacon and refresh.

For Team and Enterprise accounts, an organization owner may need to enable `Organization settings → Usage → Member analytics`. UsageBeacon can only read the information Claude shows to the signed-in member. A budget override is optional and does not affect the rolling 5-hour or 7-day utilization values.

### Anthropic Admin

`Anthropic Admin` uses Anthropic's organization admin cost-report API. A normal Console API key is not enough for this adapter. Use `Claude Personal` when you are an organization member without an Admin API key.

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
- `site`: static GitHub Pages product website and release metadata placeholders
- `docs`: contributor documentation and architecture notes

## Security and Privacy

- Provider secrets are stored in the macOS Keychain.
- Calendar access is optional and only used for working-day calculations.
- UsageBeacon does not require a backend for provider data; usage and budgets are fetched directly from vendor endpoints or signed-in local sessions.
- Firebase crash reporting is on for new installations with a first-launch disclosure and an easy opt-out. Existing installations retain their saved choice. Anonymous usage analytics remain off by default and use a separate setting.
- Telemetry never includes API keys, cookies, account identifiers, provider responses, URLs, spending, budgets, limits, or token usage.
- Some personal connectors depend on vendor web UI structure and private session endpoints, so they may require maintenance when vendors change their dashboards.
- The personal connectors automate access to undocumented endpoints using your signed-in session. Before using or redistributing them, review the applicable vendor terms and policies. You are responsible for ensuring your use is permitted.

See [SECURITY.md](SECURITY.md) for disclosure guidance.

Release maintainers should follow [RELEASING.md](RELEASING.md). It documents the one-time GitHub/Apple/Sparkle setup, version tags, beta testing, and recovery procedures.

## Known Limitations

- `Cursor Personal` depends on Cursor's signed-in private usage-summary and usage-event endpoints, which may change without notice.
- `Claude Personal` depends on Claude's private signed-in usage endpoint, which may change without notice.
- Vendor terms or access policies may restrict automated use of private endpoints even when the user can access the same data in the web interface.
- Claude Personal does not expose daily spend or per-prompt cost; the app marks those metrics as not provided instead of treating them as connection failures.
- Organization owners can disable Member analytics, in which case Claude may expose rolling quota utilization without exposing personal spend.
- Claude subscription limits are rolling percentages rather than published token caps, so UsageBeacon shows the percentages Claude reports instead of inventing token totals.
- Anthropic's admin cost report is daily, so last-prompt cost is not available through the built-in adapter.

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

UsageBeacon is available under the [MIT License](LICENSE).

## Disclaimer

UsageBeacon is an independent open-source project and is not affiliated with Cursor or Anthropic.
