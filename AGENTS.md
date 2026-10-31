# AGENTS.md

Instructions for AI coding agents working on Mangla.

## Project

Mangla is a native macOS manga reader written in Swift 6 with SwiftUI and AppKit. It targets macOS 15+, has no third-party dependencies, makes no network requests, and must never write into a user's manga folders.

Read `README.md` for the product surface and `CONTRIBUTING.md` for the human contribution workflow. This file adds the constraints that are easy for an agent to miss.

## Repository map

- `Sources/Mangla/App/` — application lifecycle, collections, scanning, progress, and one open reading session.
- `Sources/Mangla/Core/` — scanner, persistence, image decoding, prefetching, localization, layout, and watchers.
- `Sources/Mangla/Models/` — `Sendable` value types shared across layers.
- `Sources/Mangla/UI/` — SwiftUI library and reader chrome, plus the AppKit page canvases.
- `Tests/ManglaTests/` — XCTest coverage, including regression tests for every fixed blocker.
- `Scripts/` — app assembly, packaging, release notes, publishing, Xcode selection, and icon generation.
- `.github/workflows/ci.yml` — CI and automatic releases.

## Required checks

Run these before committing or opening a PR:

```bash
swift build -c release -Xswiftc -warnings-as-errors
swift test
swift format lint --recursive Sources Tests
```

The release build must have zero warnings and the full test suite must be green. Behavior changes and bug fixes need a regression test. Do not add a runtime dependency without an explicit product decision.

To build the app bundle or release assets:

```bash
./Scripts/build-app.sh release
./Scripts/package-app.sh
```

The version comes only from `VERSION`; do not hard-code a version in source or scripts. `MANGLA_BUILD_NUMBER` overrides `CFBundleVersion` for CI.

## Code rules

- Keep `@MainActor` on UI-bound types. Do not add `@unchecked Sendable` or `@preconcurrency` without a one-line justification.
- No force unwraps, `try!`, `as!`, or silent `try?` where a failure affects state, bookmarks, or user data. Log failures with `os.Logger` or surface them in the UI.
- No new network APIs, telemetry, analytics, or writes to library folders.
- Keep comments focused on why: invariants, ordering, platform quirks, workarounds. Do not add change history or commented-out code.
- Follow the committed `.swift-format` configuration. Apply formatting with:

```bash
swift format format --in-place --recursive Sources Tests
```

- Keep access control as tight as possible. Do not split `AppModel` or `ReadingSession` opportunistically; both are scheduled for post-1.0 refactoring.

## Concurrency

- Scans run in detached tasks. Cancellation cannot interrupt a filesystem walk, so `ScanGeneration` is the source of truth: only the newest generation may apply a snapshot or clear scan state. Do not replace it with a late `Task.isCancelled` check.
- `ImagePrefetcher` is an actor. Visible loads take precedence over speculative loads, and `releaseMemory()` bumps an epoch so old awaits cannot repopulate the cache after the reader closes.
- Canvas coordinators own their load and prefetch tasks. Cancel them in `teardown()`.
- Mutation of shared UI state belongs on the main actor. Reader close cancels metadata, canvas tasks, and the page cache.

## Persistence

- All state writes go through `StateStore`; keep atomic writes and the `state.json.bak` fallback.
- A corrupt or unreadable `state.json` is quarantined, never overwritten silently.
- Progress is keyed by collection UUID, then relative manga/chapter paths. Do not change that schema without a migration and a round-trip test.
- Security-scoped bookmarks must be refreshed when stale, and start/stop calls must stay balanced.

## Localization

- Every user-visible string belongs in `Sources/Mangla/Core/LocalizationCatalog.swift` with both English and Russian entries.
- Brand text, numeric labels, format names, and key glyphs such as `Esc` are exempt.
- Russian plurals follow one/few/many, including the 11–14 exception. Update `LocalizationTests` for any new counted noun.
- The only allowed Cyrillic outside the catalog is justified test fixtures.

## Scanner and watcher

- Supported layouts are collection → manga → pages and collection → manga → chapter → pages. A collection root may also be a manga. Image folders, `.cbz`/`.cbr` files, and `.pdf` files can be mixed at either level.
- Inside a manga folder, image folders and archive/PDF files each become a chapter; a loose archive or PDF at the collection root becomes its own manga.
- Traversal stops at 8 folder levels; truncation and unreadable folders and archives must be logged.
- Folder watching covers the collection root, manga folders, and chapter folders, capped at 200 directories per collection. Archive chapter files are never watched directly (reads would fire vnode events); only directories get a watcher. Document any change to that cap.
- Ignore hidden files, `__MACOSX`, and symlinks, both on disk and inside archives.

## Archives and PDFs

- ZIP (`.cbz`) is read in-process with `Compression`; ZIP64, stored, and deflate entries are supported. RAR (`.cbr`) goes through the system `/usr/bin/bsdtar` (libarchive) and never through a shell: pass arguments as an array.
- Archive format is detected from magic bytes, not from the extension.
- Scanning must never extract an archive. Archive listings are cached by path, size, and modification date; batch RAR extraction happens only when a chapter opens.
- RAR extraction goes to `~/Library/Caches/Mangla/Archives/`, keyed by a hash of the archive identity, with a `.mangla-ready` marker, a 2 GB cap, and a 14-day age cap. Never write extracted pages into a collection folder.
- Archive entry paths are untrusted: reject absolute paths, `..` components, hidden components, and `__MACOSX`. Remove extracted symlinks before publishing the cache.
- PDF pages are rasterized with CoreGraphics at about 2x page size, plus a sharper re-render on strong zoom. Page counts and aspect ratios come from the page box, not from rendering.

## Git and release

- `master` is PR-only: no direct pushes, no force-push, no deletion. Open a pull request; the `Build and test` check must pass before merge.
- Use Conventional Commits and one concern per commit.
- Merging to `master` runs CI. If `v<VERSION>` does not exist, CI creates a stable release; otherwise it replaces the rolling `nightly` prerelease.
- Do not tag, publish, or change repository visibility without explicit maintainer approval.
- Do not commit `.build/`, `Mangla.app`, `dist/`, `.review/`, personal paths, secrets, or private library screenshots.
- Keep release notes in `CHANGELOG.md` under the matching version heading; CI extracts them with `Scripts/release-notes.sh`.

## Non-goals for 1.x

App Sandbox, notarization, and a third language are post-1.0. Archive support relies on the system `bsdtar`, so sandboxing needs a different RAR strategy. Adaptive full-resolution decoding, stable progress identity across renames, avoid re-extracting unchanged CBRs, and splitting the large app/session types are tracked follow-ups, not drive-by changes.
