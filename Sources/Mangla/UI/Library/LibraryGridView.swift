import SwiftUI

struct LibraryGridView: View {
    @Bindable var model: AppModel

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 24, alignment: .top)
    ]

    private var sidebarCollapsed: Bool {
        model.columnVisibility == .detailOnly
    }

    var body: some View {
        ZStack {
            background

            if model.isLoadingProject {
                loadingView
            } else if model.mangas.isEmpty {
                EmptyProjectView(
                    onRefresh: { model.refresh() },
                    onChoose: { model.chooseProject() },
                    onReveal: { model.revealProject() }
                )
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if sidebarCollapsed {
                LinearGradient(
                    colors: [Theme.background, Theme.background.opacity(0.85), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
                .allowsHitTesting(false)
            }
        }
    }

    private var background: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(
                colors: [Theme.accent.opacity(0.085), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 760
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color(red: 0.24, green: 0.48, blue: 0.78).opacity(0.045), .clear],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 700
            )
            .ignoresSafeArea()
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.28)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.small)
            Text("Сканирую библиотеку…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                topBar
                header
                if let target = model.continueTarget, model.searchText.isEmpty, model.filter == .all {
                    ContinueBanner(
                        manga: target.manga,
                        chapter: target.chapter,
                        pageIndex: target.pageIndex,
                        fraction: model.progressFraction(for: target.manga),
                        onOpen: { model.continueReading() }
                    )
                }
                gridSection
                footer
            }
            .padding(.horizontal, 30)
            .padding(.top, 38)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.never)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            if sidebarCollapsed {
                SidebarToggleButton(isCollapsed: true) {
                    model.toggleSidebar()
                }
                .padding(.leading, 30)
                Rectangle()
                    .fill(Theme.stroke)
                    .frame(width: 1, height: 18)
            }

            HStack(spacing: 6) {
                Text("MANGLA")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(Theme.textTertiary)
                Text("/")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary.opacity(0.6))
                Text(model.projectName.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if model.isScanning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                    .frame(width: 18, height: 18)
            }

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Обновить проект (⌘R)")

            Menu {
                Button("Открыть проект…") { model.chooseProject() }
                Button("Обновить") { model.refresh() }
                Divider()
                Button("Показать в Finder") { model.revealProject() }
                Button("Забыть проект", role: .destructive) { model.forgetProject() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(height: 30)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Библиотека")
                    .font(.system(size: 42, weight: .regular, design: .serif))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 8) {
                    Text("\(model.mangas.count) \(Format.plural(model.mangas.count, "манга", "манги", "манг"))")
                    Text("·")
                    Text("\(model.mangas.reduce(0) { $0 + $1.chapterCount }) \(Format.plural(model.mangas.reduce(0) { $0 + $1.chapterCount }, "глава", "главы", "глав"))")
                    Text("·")
                    Text("\(model.mangas.reduce(0) { $0 + $1.pageCount }) \(Format.plural(model.mangas.reduce(0) { $0 + $1.pageCount }, "страница", "страницы", "страниц"))")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            if sidebarCollapsed {
                FilterBar(model: model)
                    .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private var gridSection: some View {
        if model.filteredMangas.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
                Text("Ничего не найдено")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.textSecondary)
                Text("Попробуйте изменить запрос или фильтр.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Button("Сбросить фильтры") {
                    withAnimation(Theme.snappy) { model.clearFilters() }
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 70)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                ForEach(model.filteredMangas) { manga in
                    MangaGridCard(
                        manga: manga,
                        status: model.status(for: manga),
                        fraction: model.progressFraction(for: manga),
                        isActive: model.lastMangaID == manga.id,
                        onOpen: { model.openReader(manga: manga) },
                        onRestart: { model.restartManga(manga) },
                        onToggleRead: {
                            model.setMangaRead(manga, read: model.status(for: manga) != .completed)
                        },
                        onReveal: { model.reveal(manga: manga) },
                        onOpenChapter: { chapter in
                            model.openChapter(chapter, manga: manga)
                        }
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Показано \(model.filteredMangas.count) из \(model.mangas.count)")
            Spacer()
            if !model.searchText.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                    Text("«\(model.searchText)»")
                }
                .foregroundStyle(Theme.accentSoft.opacity(0.8))
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(Theme.textTertiary)
        .padding(.top, 8)
    }
}
