# Releasing UsageBeacon

UsageBeacon releases are built from version tags. GitHub Actions builds the universal app, signs it with Developer ID, notarizes it with Apple, creates a DMG and Sparkle ZIP, generates Ed25519 signatures and deltas with Sparkle's official tools, creates the GitHub Release, then publishes the signed appcast and static website to `gh-pages`.

## One-time setup

### 1. Make distribution URLs public

The repository is currently private. Public users cannot download private GitHub Release assets, and GitHub Pages availability for private repositories depends on the account plan. Before public distribution, either make `David-Cohen974/usage-beacon` public or move the release assets and Pages site to a dedicated public distribution repository and update the URLs in:

- `Resources/UsageBeacon-Info.plist`
- `Scripts/generate-appcast.sh`
- `Scripts/generate-site-data.py`
- `site/`

The configured production URL is:

```text
https://david-cohen974.github.io/usage-beacon/
```

### 2. Configure GitHub Pages

After this release infrastructure is on `main`:

1. Open **Actions → Publish Website → Run workflow**. This creates the `gh-pages` branch.
2. Open **Settings → Pages**.
3. Under **Build and deployment**, choose **Deploy from a branch**.
4. Select `gh-pages`, folder `/ (root)`, and save.
5. Confirm the website URL and `appcast.xml` both return HTTPS responses.

The placeholder appcast contains no releases. The first version tag replaces it with a feed signed by Sparkle.

### 3. Add the GitHub Actions secrets

Open **Settings → Secrets and variables → Actions** and add:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 representation of the exported Developer ID Application certificate and its private key (`.p12`). |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12`. |
| `APPLE_API_KEY_ID` | App Store Connect API key ID used by `notarytool`. |
| `APPLE_API_ISSUER_ID` | App Store Connect API issuer ID. |
| `APPLE_API_PRIVATE_KEY` | Complete contents of the matching `AuthKey_<ID>.p8` file. |
| `SPARKLE_PRIVATE_KEY` | Sparkle Ed25519 private key exported from the login Keychain. |

`GITHUB_TOKEN` is supplied automatically. The workflow requests only `contents: write`, which it needs for Releases and the `gh-pages` branch.

Never add `.p12`, `.p8`, or exported Sparkle key files to the repository. The workflow writes credentials only into the ephemeral runner directory and deletes its temporary signing Keychain at the end.

### 4. Apple credentials

Export **Developer ID Application: David Cohen (Y3XM9Q3AZT)** and its private key from Keychain Access as a password-protected `.p12`, then encode it locally:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Create or use an App Store Connect API key with access sufficient for notarization. Copy the key ID, issuer ID, and the complete `.p8` contents into the three Apple API secrets. Apple lets the `.p8` file be downloaded only once, so keep the original in a secure credential vault.

The existing local `UsageBeaconNotary` Keychain profile still works for local release verification:

```bash
NOTARYTOOL_PROFILE=UsageBeaconNotary \
  ./Scripts/build-release.sh 1.0.0 7
```

### 5. Sparkle signing key

The dedicated key was generated with Sparkle 2.9.6 under Keychain account `com.rekindle.usagebeacon`. Its public key is already committed as `SUPublicEDKey`:

```text
TsvqpRp6P1+qRLzm/ei62YSGnZvsp//bdQITGnVdm8Y=
```

The private key remains in the macOS login Keychain. Export it only long enough to create the GitHub secret:

```bash
private_key_dir="$(mktemp -d "${TMPDIR:-/tmp}/usagebeacon-sparkle-key.XXXXXX")"
private_key_file="$private_key_dir/private-key"
sparkle_generate_keys="$(./Scripts/find-sparkle-tool.sh generate_keys)"
"$sparkle_generate_keys" --account com.rekindle.usagebeacon -x "$private_key_file"
gh secret set SPARKLE_PRIVATE_KEY < "$private_key_file"
rm -f "$private_key_file"
rmdir "$private_key_dir"
```

Keep a second encrypted copy in a password manager or offline credential vault. Do not generate another key for CI. CI receives the existing private key only through the masked `SPARKLE_PRIVATE_KEY` secret and passes it to `generate_appcast` over standard input, so it is never written into the checkout.

## Versioning

`Config/Version.xcconfig` is the release source of truth:

- `MARKETING_VERSION` becomes `CFBundleShortVersionString`, for example `1.2.0`.
- `CURRENT_PROJECT_VERSION` is the local `CFBundleVersion` fallback.
- CI replaces `CFBundleVersion` with `100000 + GITHUB_RUN_NUMBER`, which is monotonically increasing across release workflow runs.

The release workflow refuses a tag whose base semantic version does not exactly match `MARKETING_VERSION`. A tag `v1.4.2` therefore produces marketing version `1.4.2`; `v1.4.2-beta.1` also builds marketing version `1.4.2` but publishes a prerelease item on Sparkle's `beta` channel.

## Publish a stable release

1. Set `MARKETING_VERSION` in `Config/Version.xcconfig`.
2. Commit the release changes on `main`.
3. Create and push the matching annotated tag.

```bash
git add .
git commit -m "Release 1.2.0"
git tag -a v1.2.0 -m "UsageBeacon 1.2.0"
git push origin main --tags
```

After the **Release** workflow succeeds:

- GitHub Release `v1.2.0` contains the notarized DMG, Sparkle ZIP, and generated deltas.
- `appcast.xml` contains the build number, short version, size, publication date, minimum macOS version, notes, URL, Ed25519 archive signature, and signed-feed signature.
- `latest.json`, the Download buttons, and the changelog show `1.2.0` without a source edit.
- installed copies discover the update during their next scheduled check or through **Check for Updates…**.

## Test a release before stable publication

Publish a beta tag from a version already committed to `main`:

```bash
git tag -a v1.2.0-beta.1 -m "UsageBeacon 1.2.0 beta 1"
git push origin v1.2.0-beta.1
```

The workflow creates a GitHub prerelease and adds the appcast item to Sparkle's `beta` channel. It does not change the website's stable Download button. On a Mac with an older Sparkle-enabled UsageBeacon build:

1. Open UsageBeacon Settings → Updates.
2. Enable **Beta updates**.
3. Choose **Check for Updates…**.
4. Confirm the beta is found, its release notes appear, it downloads, installs, quits, and relaunches.
5. Confirm the new version/build in Settings.
6. Disable **Beta updates** unless this Mac should continue testing prereleases.

Run the non-mutating distribution check after any stable release:

```bash
./Scripts/verify-distribution.sh
```

It downloads `latest.json`, the appcast, and the DMG; validates XML and Ed25519 metadata; mounts the DMG read-only; then checks Developer ID signing, Gatekeeper assessment, notarization tickets, embedded Sparkle, version metadata, and the feed URL.

For a full clean-install test, use a separate macOS account or test Mac:

1. Download the DMG from the website.
2. Open it and drag UsageBeacon to Applications.
3. Launch normally and confirm Gatekeeper shows no bypass instructions.
4. Add the widget and verify the floating HUD/menu bar surfaces.
5. Keep this older version installed, publish a beta, and complete the update test above.

To force a scheduled check during testing, quit UsageBeacon and run:

```bash
defaults delete com.rekindle.usagebeacon SULastCheckTime
open /Applications/UsageBeacon.app
```

## Broken releases and rollback

Do not replace a public archive silently. Browsers, CDNs, and Sparkle may cache the old asset and signature independently.

- If a workflow fails before publishing the appcast, fix the cause and rerun it.
- If a beta is broken, leave it as a prerelease and publish a higher beta build/tag.
- If a stable release is broken, publish a higher patch version immediately. Sparkle updates move forward by `CFBundleVersion`; it does not downgrade users safely.
- If no users could have downloaded the release, deleting the GitHub Release and its tag is possible, but a new tag/version is still safer and auditable.
- To restore only the website after a bad site change, revert that source commit on `main` and run **Publish Website**. Do not hand-edit the signed appcast; any modification invalidates its signature.

## Sparkle troubleshooting

- **Feed is unavailable:** check the exact HTTPS `SUFeedURL`, Pages configuration, and `curl -I https://david-cohen974.github.io/usage-beacon/appcast.xml`.
- **No update is found:** compare the installed `CFBundleVersion` with `<sparkle:version>` in the appcast. The appcast build must be higher. Beta items also require **Beta updates**.
- **Improperly signed update:** confirm the app and appcast contain the committed `SUPublicEDKey`, the enclosure has `sparkle:edSignature`, and CI uses the matching private key.
- **Signed feed rejected:** never edit generated XML after `generate_appcast`; rerun the release workflow so Sparkle signs the complete feed again.
- **Gatekeeper rejection:** download the DMG again, then run `spctl`, `codesign`, and `xcrun stapler validate` as shown in `Scripts/verify-distribution.sh`.
- **Updater UI does not appear:** use Console.app and filter for `UsageBeacon` or `Sparkle`; Sparkle logs the feed, signature, extraction, permission, and relaunch failures in detail.
- **Key lost or compromised:** stop releasing and follow Sparkle's documented Ed25519 key-rotation procedure. Do not merely replace `SUPublicEDKey` in a normal release.
