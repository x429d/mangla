import SwiftUI

/// Searchable chapter list shown inside the reader. The library card menu is
/// fine for a handful of chapters, but a reader needs to jump from chapter 5
/// to chapter 45 without going back to the library first.
struct ChapterPickerOverlay: View {
    let session: ReadingSession

    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { session.hideChapterPicker() }

            panel
                .frame(width: 520, height: 560)
                .padding(24)
        }
        .transition(.opacity)
        .onAppear {
            searchFocused = true
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            searchField
            chapterList
            footer
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.44))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 34, y: 16)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "list.bullet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accentSoft)

            VStack(alignment: .leading, spacing: 3) {
                Text(t(.chapterPickerTitle))
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                Text(session.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Button {
                session.hideChapterPicker()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help(t(.helpClose))
            .accessibilityLabel(Text(t(.helpClose)))
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            TextField(
                t(.chapterPickerSearch),
                text: Binding(
                    get: { session.chapterQuery },
                    set: { session.chapterQuery = $0 }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.textPrimary)
            .focused($searchFocused)
            .onSubmit {
                if let first = session.chapterEntries.first {
                    session.openChapter(first.chapter)
                }
            }
            if !session.chapterQuery.isEmpty {
                Button {
                    session.chapterQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.24))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    searchFocused ? Theme.accent.opacity(0.45) : Theme.stroke,
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
        .animation(Theme.snappy, value: searchFocused)
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if session.chapterEntries.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(session.chapterEntries) { entry in
                            ChapterPickerRow(
                                entry: entry,
                                isCurrent: entry.chapter.id == session.chapter.id,
                                isCompleted: session.isChapterCompleted(entry.chapter),
                                onOpen: { session.openChapter(entry.chapter) }
                            )
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
            .scrollIndicators(.automatic)
            .onAppear {
                let current = session.chapterEntries.first { $0.chapter.id == session.chapter.id }
                guard let current else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(current.id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(t(.chapterPickerEmpty))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(t(.chapterPickerFooter))
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            Text("\(session.chapterEntries.count) / \(session.manga.chapters.count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)
        }
    }
}

private struct ChapterPickerRow: View {
    let entry: IndexedChapter
    let isCurrent: Bool
    let isCompleted: Bool
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Text("\(entry.index + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isCurrent ? Theme.accentSoft : Theme.textTertiary)
                    .frame(width: 34, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.chapter.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(Format.pages(entry.chapter.pageCount))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 8)

                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accentSoft.opacity(0.85))
                        .help(t(.statusCompleted))
                }

                if isCurrent {
                    Image(systemName: "book.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accentSoft)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
            .overlay(alignment: .leading) {
                if isCurrent {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isCurrent { return Theme.accent.opacity(0.14) }
        return hovering ? Color.white.opacity(0.055) : .clear
    }
}
