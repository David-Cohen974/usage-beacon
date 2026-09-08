# Stability and release acceptance

## September 2026 regression investigation

- `742122a` (1.2.2 hotfix) removed the app-group entitlement and widget build/embedding. Its checks explicitly required the widget to be absent.
- `4ef9c23` (1.2.5) restored the extension and shared entitlement, but checked packaging rather than live data propagation.
- At the start of this investigation, all 47 tests passed. Widget coverage only encoded and decoded a snapshot in memory.
- The installed 1.2.8 app had both a current group-container preference file and an older ordinary preference file for the same suite. The existing writer queued a preferences update and immediately requested a widget reload, with no committed-file handoff or visible write error. This was a plausible stale-data path, not proof of which preference domain the live extension read.
- Schedule/calendar changes required provider requests to succeed before recalculating per-workday values. The calculation also discarded the partial final day when a cycle reset after midnight. Sequential refreshes let one slow source delay later sources. Failed refreshes advanced the timestamp despite retaining old values.

## Automated checks

Run before every release:

```sh
swift test --jobs 4
Scripts/verify-widget-store.sh
Scripts/build-app.sh release
```

The suite covers provider parsing, configuration migration, work schedules, successive refreshes through the widget file, schedule updates without requests, failure timestamps, removal, write errors, and provider changes during suspended requests. The separate-process check keeps a reader alive across ten atomic writes. The bundle build verifies both architectures, extension embedding, matching versions, signatures, group entitlements, and archive integrity.

## Signed application acceptance

Record results against the actual release candidate, using a separate macOS test account for artificial budgets. Do not replace a real user's configuration with fixtures.

1. Upgrade from the previous public release. Confirm launch, provider configuration, login sessions, selected schedule, and calendar selection survive.
2. Add small, medium, and large desktop widgets. Confirm real configured sources replace gallery examples.
3. Refresh twice with a known data change. Confirm the menu, floating panel, and widget all converge to the new values. The shared file must be committed before the reload request; a file write alone is not proof of visible WidgetKit delivery.
4. Switch work schedules and selected vacation calendars. Confirm daily budget changes immediately, including offline; verify a midnight reset, a midday reset, a weekend, a vacation day, and a daylight-saving boundary.
5. Disable/remove a source during a request. Confirm its late response does not restore it. Fail one provider and confirm other sources still refresh.
6. Sleep/wake, change display configuration, restart the app, and cross midnight. Confirm the floating panel remains reachable and refresh resumes.
7. Run `Scripts/verify-distribution.sh` on the published candidate metadata to verify notarization, launch, packaging, and update metadata.

WidgetKit controls final display timing; its reload request is not an immediate-render guarantee. See [Apple's refresh documentation](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/).

Do not describe a release as end-to-end production verified until the signed application acceptance checks have evidence. Unit tests, a successful build, and a file-store check cannot establish that alone.

## Local verification on September 8, 2026

All 65 tests passed with native interface captures enabled. The persistent-reader widget-store check passed. Signed universal local builds passed archive verification and were installed with a rollback copy. Existing provider settings survived, successful refreshes advanced the shared snapshot, and WidgetKit logged successful small, medium, and large timeline requests.

Native renders cover the menu at its top and bottom and all Settings pages in light and dark appearances. The scroll check asserts a usable viewport and movement to the final provider. These checks do not establish a complete supported-OS, clean-install, gesture, sleep/wake, midnight, or automatic-upgrade acceptance matrix.
