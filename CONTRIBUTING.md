# Contributing

## Development workflow

1. Make focused changes.
2. Add or update tests when behavior changes.
3. Run the local validation commands before opening a pull request:

```bash
swift test --jobs 1
./Scripts/build-app.sh debug
```

If you are actively iterating on the app UI, `./Scripts/rebuild-and-open.sh` is the fastest local loop.

## Project conventions

- Keep the app native to macOS. Do not add a web or Electron layer.
- Prefer small provider-specific parsing helpers over large shared abstractions.
- Keep provider failures user-readable. The app should explain what is misconfigured instead of surfacing raw transport errors when possible.
- Preserve the current local-first model: fetch directly from vendor APIs or signed-in local sessions, not through a hosted relay.
- Treat secrets as Keychain-only data. Do not introduce plaintext secret storage.

## Tests

Add tests for:

- Provider parsing changes
- New JSON path or usage summary logic
- Configuration migrations or defaults
- Working-day math changes

## Pull requests

- Explain the user-facing behavior change.
- Mention any connector assumptions or vendor endpoint dependencies.
- Call out any remaining gaps if a provider relies on best-effort parsing.
