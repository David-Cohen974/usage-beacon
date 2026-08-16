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

## Recommended first public release checklist

1. Confirm all provider names and feature descriptions are accurate.
2. Confirm CI is green.
3. Review any vendor-specific parsing notes for unsupported private endpoints.
4. Tag the initial release after a clean build and test pass.
