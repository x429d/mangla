# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
