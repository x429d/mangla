import SwiftUI

struct MangaGridCard: View {
    let manga: MangaItem
    let status: ReadingStatus
    let fraction: Double
    let isActive: Bool

    let onOpen: () -> Void
    let onRestart: () -> Void
    let onToggleRead: () -> Void
    let onReveal: () -> Void
    let onOpenChapter: (ChapterItem) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cover

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(manga.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if status == .reading {
                        Text(Format.percent(fraction))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accentSoft)
                    }
                }

                Text("\(Format.chaptersCompact(manga.chapterCount))  ·  \(Format.pagesCompact(manga.pageCount))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .scaleEffect(hovering ? 1.022 : 1)
        .animation(Theme.spring, value: hovering)
        .contextMenu {
            Button("Читать") { onOpen() }
            Button("Начать сначала") { onRestart() }
            if !manga.chapters.isEmpty {
                Menu("Главы") {
                    ForEach(manga.chapters.prefix(40)) { chapter in
                        Button(chapter.title) { onOpenChapter(chapter) }
                    }
                }
            }
            Divider()
            Button(status == .completed ? "Отметить непрочитанным" : "Отметить прочитанным") {
                onToggleRead()
            }
            Button("Показать в Finder") { onReveal() }
        }
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(0.68, contentMode: .fit)
            .overlay {
                Group {
                    if let url = manga.coverURL {
                        ThumbnailImage(url: url, maxPixel: 720)
                    } else {
                        TitlePlaceholder(title: manga.title)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 74)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                StatusBadge(status: status)
                    .padding(9)
                    .opacity(status == .unread ? 0.85 : 1)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 8, weight: .semibold))
                    Text("\(manga.pageCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(.white.opacity(0.72))
                .padding(.leading, 10)
                .padding(.bottom, 9)
            }
            .overlay(alignment: .bottom) {
                ProgressTrack(fraction: fraction, height: 2.5)
                    .opacity(fraction > 0 ? 1 : 0)
            }
            .overlay {
                if hovering {
                    ZStack {
                        Rectangle().fill(.black.opacity(0.22))
                        HStack(spacing: 6) {
                            Image(systemName: "book.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(status == .reading ? "Продолжить" : "Читать")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isActive
                            ? Theme.accent.opacity(0.55)
                            : (hovering ? Color.white.opacity(0.2) : Theme.stroke),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: .black.opacity(hovering ? 0.42 : 0.22),
                radius: hovering ? 20 : 9,
                y: hovering ? 11 : 5
            )
            .animation(Theme.spring, value: hovering)
    }
}

// MARK: - Continue banner

struct ContinueBanner: View {
    let manga: MangaItem
    let chapter: ChapterItem
    let pageIndex: Int
    let fraction: Double
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 18) {
                Group {
                    if let url = manga.coverURL {
                        ThumbnailImage(url: url, maxPixel: 360)
                    } else {
                        TitlePlaceholder(title: manga.title)
                    }
                }
                .frame(width: 66, height: 94)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("ПРОДОЛЖИТЬ ЧТЕНИЕ")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.4)
                    }
                    .foregroundStyle(Theme.accentSoft)

                    Text(manga.title)
                        .font(.system(size: 23, weight: .regular, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("\(chapter.title)  ·  стр. \(pageIndex + 1) из \(chapter.pageCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 9) {
                        ProgressTrack(fraction: fraction, height: 3)
                            .frame(width: 190)
                        Text(Format.percent(fraction))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 12)

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accentSoft, Theme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 5)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(hovering ? 1.06 : 1)
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent.opacity(0.10), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        hovering ? Theme.accent.opacity(0.35) : Theme.stroke,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.spring, value: hovering)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
