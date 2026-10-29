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

            collectionsHeader
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 7)

            collectionList

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
        HStack(spacing: 9) {
            LogoMark(size: 25)
            Wordmark()
            Spacer()
            SidebarToggleButton(isCollapsed: false) {
                model.toggleSidebar()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            TextField(t(.searchPlaceholder), text: $model.searchText)
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

    private var collectionsHeader: some View {
        HStack(spacing: 8) {
            Text(t(.collectionsHeader))
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Theme.textTertiary)

            Spacer()

            Button {
                model.addCollections()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(t(.addCollectionHelp))
        }
    }

    private var collectionList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.collections) { collection in
                    CollectionRow(
                        collection: collection,
                        isSelected: model.selectedCollectionID == collection.id,
                        isScanning: model.scanningCollectionIDs.contains(collection.id),
                        onSelect: { model.selectCollection(collection.id) },
                        onRefresh: { model.scan(collectionID: collection.id) },
                        onReveal: { model.reveal(collection: collection) },
                        onRemove: { model.removeCollection(collection.id) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.never)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
            HStack(spacing: 6) {
                Text(Format.collections(model.collections.count))
                Spacer()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

// MARK: - Collection row

struct CollectionRow: View {
    let collection: MangaCollection
    let isSelected: Bool
    let isScanning: Bool
    let onSelect: () -> Void
    let onRefresh: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: collection.isAvailable ? "folder.fill" : "folder.badge.questionmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(collection.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(collection.isAvailable ? Theme.textPrimary : Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isScanning {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else if !collection.isAvailable {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
            .padding(.leading, 9)
            .padding(.trailing, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isSelected
                            ? Theme.accent.opacity(0.13)
                            : (hovering ? Color.white.opacity(0.045) : .clear)
                    )
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 7)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button(collection.isAvailable ? t(.refresh) : t(.checkAgain)) { onRefresh() }
            Button(t(.revealInFinder)) { onReveal() }
            Divider()
            Button(t(.removeFromApp), role: .destructive) { onRemove() }
        }
    }

    private var iconColor: Color {
        if !collection.isAvailable { return Theme.textTertiary }
        return isSelected ? Theme.accentSoft : Theme.textSecondary
    }

    private var subtitle: String {
        guard collection.isAvailable else { return t(.folderUnavailable) }
        return "\(Format.mangas(collection.mangaCount)) · \(Format.chapters(collection.chapterCount))"
    }
}
