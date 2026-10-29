import SwiftUI

struct FilterBar: View {
    @Bindable var model: AppModel
    var showsCounts = true

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LibraryFilter.allCases) { filter in
                Button {
                    withAnimation(Theme.snappy) { model.filter = filter }
                } label: {
                    HStack(spacing: 4) {
                        Text(filter.title)
                        if showsCounts {
                            Text("\(model.filterCount(filter))")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(
                                    model.filter == filter
                                        ? Theme.textPrimary.opacity(0.65)
                                        : Theme.textTertiary
                                )
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        model.filter == filter ? Theme.textPrimary : Theme.textSecondary
                    )
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(
                        Capsule().fill(
                            model.filter == filter ? Color.white.opacity(0.13) : .clear
                        )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.22)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        .fixedSize()
    }
}

struct SidebarView: View {
    @Bindable var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 42)
                .padding(.horizontal, 16)

            searchField
                .padding(.horizontal, 14)
                .padding(.top, 16)

            HStack {
                FilterBar(model: model)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)
                .padding(.top, 13)

            if model.filteredMangas.isEmpty {
                emptyList
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredMangas) { manga in
                            SidebarMangaRow(
                                manga: manga,
                                status: model.status(for: manga),
                                fraction: model.progressFraction(for: manga),
                                isExpanded: model.expandedMangaIDs.contains(manga.id),
                                isActive: model.lastMangaID == manga.id,
                                activeChapterID: model.reading?.chapter.id,
                                isReadingThisManga: model.reading?.manga.id == manga.id,
                                chapterCompleted: { chapter in
                                    model.progress[manga.id]?.chapters[chapter.id]?.isCompleted == true
                                },
                                onOpen: {
                                    model.openReader(manga: manga)
                                },
                                onToggle: {
                                    withAnimation(Theme.snappy) {
                                        model.toggleExpanded(mangaID: manga.id)
                                    }
                                },
                                onOpenChapter: { chapter in
                                    model.openChapter(chapter, manga: manga)
                                },
                                onRestart: { model.restartManga(manga) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 9)
                }
                .scrollIndicators(.never)
            }

            footer
        }
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Theme.background.opacity(0.68)
            }
            .ignoresSafeArea()
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                LogoMark(size: 25)
                Wordmark()
                Spacer()
                SidebarToggleButton(isCollapsed: false) {
                    model.toggleSidebar()
                }
            }

            HStack(spacing: 7) {
                Menu {
                    Button("Открыть проект…") { model.chooseProject() }
                    Button("Обновить") { model.refresh() }
                    Divider()
                    Button("Показать в Finder") { model.revealProject() }
                    Button("Забыть проект", role: .destructive) { model.forgetProject() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.accentSoft)
                        Text(model.projectName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Spacer(minLength: 0)

                Button {
                    model.refresh()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                        .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                        .rotationEffect(.degrees(model.isScanning ? 360 : 0))
                        .animation(
                            model.isScanning
                                ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                : .default,
                            value: model.isScanning
                        )
                }
                .buttonStyle(.plain)
                .help("Обновить проект")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            TextField("Поиск по библиотеке", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 29)
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
        .animation(Theme.snappy, value: searchFocused)
    }

    private var emptyList: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: model.searchText.isEmpty ? "books.vertical" : "magnifyingglass")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(model.searchText.isEmpty ? "Нет манг в этой подборке" : "Ничего не найдено")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
            HStack(spacing: 6) {
                Text("\(model.mangas.count) \(Format.plural(model.mangas.count, "манга", "манги", "манг"))")
                Text("·")
                Text("\(totalChapters) \(Format.plural(totalChapters, "глава", "главы", "глав"))")
                Spacer()
                Menu {
                    Button("Открыть проект…") { model.chooseProject() }
                    Button("Показать в Finder") { model.revealProject() }
                    Divider()
                    Button("Забыть проект", role: .destructive) { model.forgetProject() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private var totalChapters: Int {
        model.mangas.reduce(0) { $0 + $1.chapterCount }
    }
}

// MARK: - Sidebar row

struct SidebarMangaRow: View {
    let manga: MangaItem
    let status: ReadingStatus
    let fraction: Double
    let isExpanded: Bool
    let isActive: Bool
    let activeChapterID: String?
    let isReadingThisManga: Bool
    let chapterCompleted: (ChapterItem) -> Bool
    let onOpen: () -> Void
    let onToggle: () -> Void
    let onOpenChapter: (ChapterItem) -> Void
    let onRestart: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 15, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onOpen) {
                    HStack(spacing: 9) {
                        cover

                        VStack(alignment: .leading, spacing: 3) {
                            Text(manga.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            HStack(spacing: 4) {
                                Text(Format.chaptersCompact(manga.chapterCount))
                                Text("·")
                                Text(Format.pagesCompact(manga.pageCount))
                                Spacer(minLength: 2)
                                if status == .completed {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Theme.mint)
                                } else if status == .reading {
                                    Text(Format.percent(fraction))
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Theme.accentSoft)
                                }
                            }
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)

                            if status == .reading {
                                ProgressTrack(fraction: fraction, height: 2)
                                    .padding(.top, 1)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isReadingThisManga
                            ? Theme.accent.opacity(0.13)
                            : (hovering ? Color.white.opacity(0.045) : .clear)
                    )
            )
            .onHover { hovering = $0 }
            .contextMenu {
                Button("Читать") { onOpen() }
                Button("Начать сначала") { onRestart() }
            }

            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(manga.chapters) { chapter in
                        Button {
                            onOpenChapter(chapter)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: chapter.id == activeChapterID
                                      ? "book.fill"
                                      : (chapterCompleted(chapter) ? "checkmark.circle.fill" : "circle"))
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(
                                        chapter.id == activeChapterID
                                            ? Theme.accentSoft
                                            : (chapterCompleted(chapter) ? Theme.mint.opacity(0.8) : Theme.textTertiary.opacity(0.55))
                                    )
                                Text(chapter.title)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(
                                        chapter.id == activeChapterID
                                            ? Theme.textPrimary
                                            : Theme.textSecondary
                                    )
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                Text("\(chapter.pageCount)")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.leading, 32)
                            .padding(.trailing, 10)
                            .frame(height: 24)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var cover: some View {
        Group {
            if let url = manga.coverURL {
                ThumbnailImage(url: url, maxPixel: 160)
            } else {
                TitlePlaceholder(title: manga.title)
            }
        }
        .frame(width: 27, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
