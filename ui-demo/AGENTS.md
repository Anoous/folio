# Folio UI Demo Working Agreement

- Develop and iterate the UI demo in `/Users/mac/github/folio/ui-demo` on the `codex/ui-demo` branch.
- Keep demo-specific code, assets, tests, and documentation inside this directory unless the user explicitly expands the scope.
- Before making demo changes, verify that the active Git branch is `codex/ui-demo`.
- Preserve unrelated user changes in the parent Folio repository.

## iOS Development Workflow

- For iOS app development, follow OpenAI's [Build for iOS](https://learn.chatgpt.com/use-cases/native-ios-apps) use case.
- Keep the build loop CLI-first with `xcodebuild`, and run the smallest trustworthy validation after each change before expanding to broader builds or UI tests.
- For deeper work in the existing Xcode project, use the recommended iOS build tooling or focused SwiftUI skills to inspect schemes, then use the browser-mirror workflow below for every visual or interactive verification.

## Mandatory `serve-sim` Browser-Mirror Testing

- Use the `ios-simulator-browser` skill and `serve-sim` for **all Folio UI demo visual, interaction, and manual acceptance testing**, even when the user does not explicitly ask to watch the run.
- Do not use the macOS Simulator app window as the testing surface, and do not accept a standalone `simctl`/Simulator screenshot as visual proof. Build, install, launch, and automated XCTest commands remain CLI-first; the running UI must be observed and exercised through the Codex in-app Browser mirror.
- “Do not use the real simulator” means “do not directly operate or visually approve the standalone Simulator window.” `serve-sim` still mirrors an underlying iOS Simulator device, and `xcodebuild`, `simctl`, and XCUITest still target that same explicit device.

### Required State

- Treat the iOS Simulator device, the long-running `serve-sim` process, and the in-app Browser tab as three independent states. All three must remain healthy and point to the same explicit UDID.
- Reuse the task's existing booted device and browser tab when available. Never silently switch to a different simulator after the browser URL has been pinned with `?device=<UDID>`.
- Keep the `serve-sim` terminal alive for the entire test and browser-review session. Keep one canonical mirror tab available to the user instead of repeatedly creating replacement tabs.

### Standard Workflow

1. Resolve and record the explicit booted Simulator UDID. If an existing mirror URL contains `?device=<UDID>`, use that device.
2. Build and run the smallest trustworthy CLI test against that same UDID. Keep the mirror running while `xcodebuild` or XCUITest executes.
3. Start or reuse a long-running `serve-sim` process pinned to that UDID. Clean up only that simulator's stale helper before starting:

    ```bash
    SIM_UDID="<simulator-udid>"
    cleanup_serve_sim() {
      npx --yes serve-sim@latest --kill "$SIM_UDID" >/dev/null 2>&1 || true
    }
    trap cleanup_serve_sim EXIT INT TERM HUP
    cleanup_serve_sim
    npx --yes serve-sim@latest "$SIM_UDID"
    ```

4. Open the exact local URL printed by `serve-sim` in the Codex in-app Browser and keep that tab available to the user.
5. After `xcodebuild test` or XCUITest finishes, install the latest built app if necessary and relaunch `com.folio.uidemo`, because the test runner may terminate the app or leave the device on SpringBoard:

    ```bash
    xcrun simctl install "$SIM_UDID" "<derived-data>/Build/Products/Debug-iphonesimulator/FolioUIDemo.app"
    xcrun simctl launch --terminate-running-process "$SIM_UDID" com.folio.uidemo <launch-arguments>
    ```

6. In the browser mirror, collapse the devices sidebar and Tools panel if they obscure the phone. Verify a real Folio frame is visible—not only a loaded page, a `live` badge, SpringBoard, or the `serve-sim` device picker.
7. Exercise the changed interaction through the browser-visible mirror and capture browser screenshots of the meaningful before/after states. CLI assertions alone are not sufficient for visual or interaction acceptance.
8. Report both layers of evidence: the CLI build/test result and what was visibly confirmed in the browser mirror. Leave the canonical mirror tab on the most useful final state for the user.

### Recovery and Isolation

- If the browser is blank, diagnose the three layers separately: confirm the selected UDID is booted, confirm `serve-sim` is still streaming that UDID, then relaunch `com.folio.uidemo`. Do not assume a loaded page or `live` badge means the App frame is present.
- If the browser shows SpringBoard after XCTest, relaunch the App; do not restart the entire mirror first.
- If the browser shows stale UI, install the latest build on the pinned UDID, relaunch the App, and verify the frame again before changing tabs or devices.
- Never run an unscoped `serve-sim --kill`; another task may own a different simulator mirror. Kill only the explicit pinned UDID.
- Do not close or finalize the canonical Browser tab until testing is complete. At delivery, preserve it as the user-visible result when the preview session is meant to remain available.
