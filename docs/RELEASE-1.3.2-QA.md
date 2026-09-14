# UsageBeacon 1.3.2 verification

Version 1.3.2, build 100015, installed at /Applications/UsageBeacon.app.

- 70 tests across 3 suites pass, including default meter selection, preserving a user's explicit off choice, and migration of saved selections.
- The universal app and DMG are Developer ID signed, notarized, stapled, and accepted by Gatekeeper.
- Clicked the empty middle/right area of a provider header to expand it, and the provider name to collapse it. Both work; Sync is inside the expanded settings.
- Verified switch on/off states through accessibility and screenshots. On uses blue with a checkmark and a right-positioned thumb; off uses gray with a minus and a left-positioned thumb. Checked Light and System/dark appearance, then restored System with the user's meter on.
- The saved Cursor connection still syncs successfully.
- Fixed an installer false rejection caused by grep exiting early while codesign was still writing under pipefail. The signature check now consumes all output; valid app and widget signatures remain mandatory.
