# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Spread mode keeps the first page as a cover by default, so subsequent two-page spreads match the artwork. The offset can be switched from the reader sidebar or with `C` in spread mode.
- A searchable chapter picker in the reader opens any chapter without going back to the library (`L`).
- The library supports keyboard navigation: `Cmd+F` focuses search, arrow keys move the card selection, `Return` opens it, and `Esc` clears it.
- Plain `.zip` and `.rar` archives are scanned alongside `.cbz` and `.cbr`, and JPEG XL (`.jxl`) pages are supported.
- The library can be sorted by name, recently read, chapter count, or date added, and remembers the choice.
- Cached pages are dropped when the system reports memory pressure, without interrupting the page being read.

### Fixed

- The card context menu no longer stops at the first 40 chapters; long lists are grouped into ranges.
- The native sidebar toggle is removed on window update events instead of a fixed 0.8-second timer.

## [1.3.0] - 2026-11-02

### Fixed

- Webtoon scrolling no longer stalls in long chapters. The strip keeps its geometry cached, lays out only when pages or the viewport change, creates page views on demand, and stops decoding pages that scrolled out of the window instead of leaving them in a queue.
- Reading progress is written once scrolling pauses, so a hidden library is no longer redrawn for every page that passes through the viewport.

## [1.2.0] - 2026-11-01

### Added

- The library shows 32 manga per page instead of 30.

### Fixed

- Adding more than a few large collections no longer exhausts the app's file descriptors. Folder watching now uses one FSEvents stream per collection instead of one vnode source per directory, so covers, pages, and archives keep loading.

## [1.1.0] - 2026-10-31

### Added

- CBZ and CBR archives are read alongside image folders, with format detection by content and natural page ordering.
- PDF files open as manga or chapters; pages are rasterized on demand and re-rendered sharper when zoomed.
- Loose archives and PDFs at a collection root become individual mangas.
- CBR pages are cached outside the library in `~/Library/Caches/Mangla/Archives/`, bounded by size and age.

## [1.0.0] - 2026-10-30

### Added

- Native macOS library for folder-based manga and comic collections.
- Single-page, two-page spread, and continuous webtoon reading modes with RTL and LTR support.
- AppKit magnification, trackpad panning, smart zoom, click zones, and keyboard navigation.
- Multiple collections, per-collection progress, search, filters, and pagination.
- English and Russian interface selected from the system language.
- Folder watching for new collections, chapters, and pages.
- CI builds, tests, packaged app artifacts, and GitHub Releases.

### Fixed

- Corrupt state files are recovered from a backup instead of silently resetting progress.
- Cancelled scans can no longer publish stale library contents.
- Closing the reader releases decoded pages and bounds concurrent decodes.
- Deeply nested chapters are scanned consistently, and folder errors are logged.
