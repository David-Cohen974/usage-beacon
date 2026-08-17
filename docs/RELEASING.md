# Releasing and Publishing

## Before making the repository public

1. Choose a license and add a `LICENSE` file.
2. Review the README for connector limitations you want to present publicly.
3. Make sure no local test data or personal screenshots are included in the repo.
4. Confirm the app builds cleanly:

```bash
swift test --jobs 1
./Scripts/build-app.sh debug
```

5. Verify the built app launches:

```bash
open dist/UsageBeacon.app
```

## Developer ID build

Set `USAGEBEACON_SIGNING_IDENTITY` to an installed Developer ID Application
identity to enable Hardened Runtime signing with a secure timestamp:

```bash
USAGEBEACON_SIGNING_IDENTITY="Developer ID Application: David Cohen (Y3XM9Q3AZT)" \
  ./Scripts/build-app.sh release
```

Developer ID signing does not replace notarization. Before sharing the app,
submit the signed distribution to Apple's notary service, staple the accepted
ticket to the app, and verify it with Gatekeeper.

## Recommended first public release checklist

1. Confirm all provider names and feature descriptions are accurate.
2. Confirm CI is green.
3. Review any vendor-specific parsing notes for unsupported private endpoints.
4. Tag the initial release after a clean build and test pass.
