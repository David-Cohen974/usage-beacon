# Security Policy

## Supported scope

UsageBeacon stores provider secrets locally in the macOS Keychain and may open signed-in vendor sessions in local web views for personal connectors. Security reports related to credential handling, local storage, or unintended data exposure are in scope.

Optional crash reporting and anonymous usage analytics are disabled by default. When enabled independently in Settings, telemetry is sent to the dedicated UsageBeacon Firebase project. Events use coarse connector types, outcomes, error categories, and duration buckets; they must never contain credentials, account identifiers, URLs, provider response contents, budgets, spending, limits, or token usage.

## Reporting

If you find a security issue, do not open a public issue with exploit details.

Report it privately through [GitHub's private vulnerability reporting form](https://github.com/David-Cohen974/usage-beacon/security/advisories/new) with:

- A clear description of the issue
- Impact
- Reproduction steps
- Any proof-of-concept details needed to validate it

## Response expectations

- Reports will be triaged before public discussion
- Reasonable effort will be made to reproduce and fix confirmed issues
- Coordinated disclosure is preferred

## Hardening expectations for contributors

- Do not log secrets
- Do not add raw errors, provider payloads, identifiers, URLs, or usage values to telemetry
- Do not introduce plaintext credential persistence
- Prefer least-privilege access paths where vendor products support them
- Keep third-party network calls explicit and reviewable
