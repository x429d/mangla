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
            content
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

    @ViewBuilder
    private var content: some View {
        if let collection = model.selectedCollection, !collection.isAvailable {
            UnavailableCollectionView(
                name: collection.name,
                path: collection.directoryURL.path,
                isChecking: model.scanningCollectionIDs.contains(collection.id),
                onRetry: { model.scan(collectionID: collection.id) },
                onRemove: { model.removeCollection(collection.id) },
                onReveal: { model.reveal(collection: collection) }
            )
        } else if model.isLoadingSelectedCollection {
            loadingView
        } else if model.selectedCollection == nil {
            selectCollectionView
        } else if model.mangas.isEmpty {
            EmptyCollectionView(
                onRefresh: { model.refresh() },
                onAddCollection: { model.addCollections() },
                onReveal: { model.revealProject() }
            )
        } else {
            libraryScroll
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
            Text("Сканирую коллекцию…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var selectCollectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Выберите коллекцию")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textSecondary)
            Button("Добавить коллекцию") { model.addCollections() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    // MARK: - Main scroll content

    private var libraryScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Color.clear
                        .frame(height: 0)
                        .id("libraryTop")

                    topBar
                    header

                    if model.currentPage == 0,
                       let target = model.continueTarget,
                       model.searchText.isEmpty,
                       model.filter == .all {
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
            .onChange(of: model.libraryPage) { _, _ in
                withAnimation(Theme.snappy) {
                    proxy.scrollTo("libraryTop", anchor: .top)
                }
            }
            .onChange(of: model.searchText) { _, _ in
                model.resetPage()
                withAnimation(Theme.snappy) {
                    proxy.scrollTo("libraryTop", anchor: .top)
                }
            }
            .onChange(of: model.filter) { _, _ in
                model.resetPage()
                withAnimation(Theme.snappy) {
                    proxy.scrollTo("libraryTop", anchor: .top)
                }
            }
            .onChange(of: model.selectedCollectionID) { _, _ in
                model.resetPage()
                proxy.scrollTo("libraryTop", anchor: .top)
            }
            .onChange(of: model.filteredMangas.count) { _, _ in
                model.clampPage()
            }
        }
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
                Text("КОЛЛЕКЦИИ")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
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
            .help("Обновить коллекцию (⌘R)")

            Menu {
                Button("Добавить коллекцию…") { model.addCollections() }
                Button("Обновить коллекцию") { model.refresh() }
                Divider()
                Button("Показать в Finder") { model.revealProject() }
                Button("Убрать из приложения", role: .destructive) {
                    model.removeSelectedCollection()
                }
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
            VStack(alignment: .leading, spacing: 5) {
                Text("КОЛЛЕКЦИЯ")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(Theme.accentSoft)

                Text(model.projectName)
                    .font(.system(size: 42, weight: .regular, design: .serif))
                    .tracking(-0.8)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.7)

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

            VStack(alignment: .trailing, spacing: 10) {
                if model.pageCount > 1 {
                    PaginationBar(
                        page: model.currentPage,
                        pageCount: model.pageCount,
                        onPrevious: { model.previousPage() },
                        onNext: { model.nextPage() }
                    )
                }

                if sidebarCollapsed {
                    FilterBar(model: model)
                }
            }
            .padding(.bottom, 4)
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
                ForEach(model.pageMangas) { manga in
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
        HStack(spacing: 12) {
            Text("Показано \(model.pageRangeText)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            Spacer()

            if !model.searchText.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                    Text("«\(model.searchText)»")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.accentSoft.opacity(0.8))
            }

            if model.pageCount > 1 {
                PaginationBar(
                    page: model.currentPage,
                    pageCount: model.pageCount,
                    onPrevious: { model.previousPage() },
                    onNext: { model.nextPage() }
                )
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - Pagination

struct PaginationBar: View {
    let page: Int
    let pageCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(page > 0 ? Theme.textSecondary : Theme.textTertiary.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(page <= 0)
            .help("Предыдущая страница")

            Text("\(page + 1) / \(pageCount)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 48)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(page < pageCount - 1 ? Theme.textSecondary : Theme.textTertiary.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(page >= pageCount - 1)
            .help("Следующая страница")
        }
        .padding(.horizontal, 7)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}
