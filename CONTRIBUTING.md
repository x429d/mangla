# Contributing to Mangla

Thanks for helping improve Mangla. Keep changes focused, tested, and consistent with the existing Swift style.

## Build and test

```bash
swift build -c release -Xswiftc -warnings-as-errors
swift test
./Scripts/build-app.sh
```

The project has no external runtime dependencies. Do not add one without discussing it in an issue first.

## Style

- Swift 6 language mode; keep `@MainActor` on UI-bound types and `Sendable` honest.
- Follow the Swift API Design Guidelines. Prefer clear names to comments.
- Comments explain why, not what. No commented-out code, author banners, or unreferenced work items.
- Run `swift format lint --recursive Sources Tests` before opening a PR. Apply the committed `.swift-format` configuration with `swift format format --in-place --recursive Sources Tests`.
- User-visible strings belong in `Sources/Mangla/Core/LocalizationCatalog.swift`, with both English and Russian entries.

## Commits

Use Conventional Commits: `fix:`, `refactor:`, `style:`, `docs:`, `ci:`, `test:`, `chore:`. Keep one concern per commit. A behavior change needs a regression test.

## Pull requests

- Describe the problem and the fix.
- Add or update tests for behavior changes.
- Keep the release build warning-free and the full test suite green.
- Do not include generated build products, screenshots of private libraries, or personal paths.
- By submitting a pull request you agree to license your contribution under the MIT License.

## Reporting bugs

Use the bug report template and include the macOS version, steps to reproduce, and whether the problem happens with a folder-based library. Remove personal folder names and paths from screenshots and logs.
