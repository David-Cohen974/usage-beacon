# Native interface redesign — September 8, 2026

The supplied menu screenshot showed truncated summary amounts, almost no visible provider content, and multiple nested rounded surfaces. Code inspection found an unbounded menu VStack containing a maximum-height-only ScrollView, a continuously animated backdrop, and spring animation attached to every snapshot change. The screenshot cannot establish animation timing; that finding comes from the implementation and the user's report.

## Layout decisions

- The menu is 400 points wide with a height bounded by the display's visible frame. Its toolbar and footer stay outside a single vertical scroll view. Summary and provider sections share that scroll view, so the summary cannot consume the entire provider viewport.
- Currency totals use a full-width headline or label/value rows. Provider sections use separators instead of cards within cards. The footer uses standard controls and retains Settings, Quit, and the floating panel toggle.
- System text and surface colours replace the tinted animated canvas. Data updates do not animate menu layout. Provider disclosure in Settings no longer springs open.
- Settings uses a native sidebar and one scroll view for its selected page: Providers, Workdays & Calendars, Appearance, Privacy & Diagnostics, or Updates. Existing settings bindings and actions are retained.
- The floating panel retains its compact structure; it inherits the quieter shared palette. Widget presentation is unchanged by this redesign.

Apple reference: https://developer.apple.com/design/human-interface-guidelines/scroll-views

## Verification

`USAGEBEACON_UI_CAPTURE_DIR=/tmp/beacon-ui swift test --filter menuLayoutCapture` creates an isolated four-provider configuration, suppresses widget publishing and telemetry, and performs native NSHostingView renders. It asserts that a real NSScrollView has a usable viewport, that its document exceeds the viewport, and that it can reach the document's end. Captures include menu top/bottom in light/dark appearances and each Settings page. CI runs this check separately from the normal suite.

The captures use example data, not the user's account. Offscreen rendering verifies layout and programmatic scrolling; it does not prove trackpad gesture routing or the system menu opening animation. Those remain live interaction acceptance checks. Rendered Settings pages cover the initial state, not every expanded provider editor or permission state.

Keep these boundaries for future changes: one menu scroll viewport, fixed accessible actions, no whole-layout animation on refresh, no nested metric cards, and no screenshot or test fixture writes to the user's live configuration or widget snapshot.

## Local result

All 65 tests passed with native captures enabled. The universal Release archive passed signing and packaging verification and was installed at `/Applications/UsageBeacon.app` with a rollback copy retained. At 14:18:57 local time, all three real providers had refreshed without errors; monetary daily budgets still used 15 workdays. The replacement widget extension logged successful small, medium, and large timeline requests. No public release was published.

### Settings alignment follow-up

A second UsageBeacon process was found running from Xcode DerivedData alongside the installed app. That extra process was closed to remove ambiguity about which menu and Settings window were being opened. Settings was further aligned with the menu using standard system typography, native bordered buttons and text fields, ordinary weekday checkboxes with full weekday accessibility labels, and consistent section edges. The provider disclosure action's explicit spring was removed as well as its animation modifier. Native screenshots for Providers, Workdays & Calendars, and Appearance were inspected after the changes; the 65-test suite passed with captures enabled.

### Widget-inspired colour refinement

The accepted layout remains unchanged. A stationary navy-to-teal canvas in dark appearance and pale blue-to-mint canvas in light appearance now connect the menu and Settings to the widget's palette. Translucent toolbars/sidebar and blue/teal symbols provide accents without introducing additional card containers. The remaining-budget headline uses an appearance-aware teal ink. Increased Contrast or Reduce Transparency substitutes the system window background. No continuous background animation or layout transforms were added. Native captures now cover all Settings pages in both light and dark appearances.
