# Security Policy

## Supported scope

UsageBeacon stores provider secrets locally in the macOS Keychain and may open signed-in vendor sessions in local web views for personal connectors. Security reports related to credential handling, local storage, or unintended data exposure are in scope.

## Reporting

If you find a security issue, do not open a public issue with exploit details.

Report it privately to the repository owner with:

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
- Do not introduce plaintext credential persistence
- Prefer least-privilege access paths where vendor products support them
- Keep third-party network calls explicit and reviewable
