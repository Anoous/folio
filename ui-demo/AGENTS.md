# Folio UI Demo Working Agreement

- Develop and iterate the UI demo in `/Users/mac/github/folio/ui-demo` on the `codex/ui-demo` branch.
- Keep demo-specific code, assets, tests, and documentation inside this directory unless the user explicitly expands the scope.
- Before making demo changes, verify that the active Git branch is `codex/ui-demo`.
- Preserve unrelated user changes in the parent Folio repository.

## iOS Development Workflow

- For iOS app development, follow OpenAI's [Build for iOS](https://learn.chatgpt.com/use-cases/native-ios-apps) use case.
- Keep the build loop CLI-first with `xcodebuild`, and run the smallest trustworthy validation after each change before expanding to broader builds or UI tests.
- For deeper work in the existing Xcode project, use the recommended iOS build tooling or focused SwiftUI skills to inspect schemes, run the simulator, capture screenshots, and verify UI behavior.
