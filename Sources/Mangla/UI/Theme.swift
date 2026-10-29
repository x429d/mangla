import SwiftUI

enum Theme {
    static let background = Color(red: 0.043, green: 0.045, blue: 0.052)
    static let backgroundDeep = Color(red: 0.027, green: 0.028, blue: 0.033)
    static let panel = Color(red: 0.086, green: 0.090, blue: 0.102)
    static let panelStrong = Color(red: 0.117, green: 0.122, blue: 0.137)
    static let readerBackground = Color(red: 0.020, green: 0.020, blue: 0.024)

    static let stroke = Color.white.opacity(0.075)
    static let strokeStrong = Color.white.opacity(0.14)

    static let textPrimary = Color(white: 0.95)
    static let textSecondary = Color(white: 0.64)
    static let textTertiary = Color(white: 0.42)

    static let accent = Color(red: 0.910, green: 0.322, blue: 0.227)
    static let accentSoft = Color(red: 0.980, green: 0.478, blue: 0.322)
    static let mint = Color(red: 0.420, green: 0.827, blue: 0.694)

    static let corner: CGFloat = 14
    static let spring = Animation.spring(response: 0.36, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.24, dampingFraction: 0.86)
    static let smooth = Animation.smooth(duration: 0.26)

    static let pageLabelFont = Font.system(size: 11, weight: .semibold, design: .monospaced)

    static func hue(for string: String) -> Double {
        let value = string.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Double(value % 360) / 360
    }
}

enum Format {
    static func pages(_ count: Int) -> String {
        "\(count) \(plural(count, "страница", "страницы", "страниц"))"
    }

    static func chapters(_ count: Int) -> String {
        "\(count) \(plural(count, "глава", "главы", "глав"))"
    }

    static func pagesCompact(_ count: Int) -> String { "\(count) стр." }
    static func chaptersCompact(_ count: Int) -> String { "\(count) гл." }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod100 = abs(count) % 100
        let mod10 = abs(count) % 10
        if mod100 >= 11, mod100 <= 14 { return many }
        if mod10 == 1 { return one }
        if mod10 >= 2, mod10 <= 4 { return few }
        return many
    }
}

// MARK: - Shared visual components

struct LogoMark: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accentSoft, Theme.accent, Color(red: 0.56, green: 0.11, blue: 0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "book.pages.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.35, y: size * 0.12)
    }
}

struct Wordmark: View {
    var body: some View {
        Text("MANGLA")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(3.2)
            .foregroundStyle(Theme.textPrimary)
    }
}

struct SidebarToggleButton: View {
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.055)))
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Показать панель (⌘\\)" : "Скрыть панель (⌘\\)")
    }
}

struct SVGArrow: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.textTertiary)
    }
}

struct StatusBadge: View {
    let status: ReadingStatus

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.58)))
            .overlay(Capsule().strokeBorder(foreground.opacity(0.38), lineWidth: 1))
    }

    private var label: String {
        switch status {
        case .unread: "НОВОЕ"
        case .reading: "ЧИТАЮ"
        case .completed: "ПРОЧИТАНО"
        }
    }

    private var foreground: Color {
        switch status {
        case .unread: Theme.textSecondary
        case .reading: Theme.accentSoft
        case .completed: Theme.mint
        }
    }

}

struct ProgressTrack: View {
    let fraction: Double
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Theme.accentSoft, Theme.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

struct ThumbnailImage: View {
    let url: URL?
    var maxPixel: Int = 512
    var contentMode: ContentMode = .fill

    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.panel)

            if let image {
                SwiftUI.Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                placeholder(icon: "photo.badge.exclamationmark")
            } else {
                placeholder(icon: "book.closed")
            }
        }
        .clipped()
        .task(id: url) {
            image = nil
            failed = false
            guard let url else {
                failed = true
                return
            }
            let loaded = await ThumbnailProvider.shared.thumbnail(for: url, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            if let loaded {
                image = loaded
            } else {
                failed = true
            }
        }
    }

    private func placeholder(icon: String) -> some View {
        ZStack {
            LinearGradient(
                colors: [Theme.panelStrong, Theme.panel],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.textTertiary.opacity(0.5))
        }
    }
}

/// Deterministic, pleasant placeholder used when a manga has no cover.
struct TitlePlaceholder: View {
    let title: String
    var symbol: String = "text.book.closed"

    var body: some View {
        let hue = Theme.hue(for: title)
        ZStack {
            LinearGradient(
                colors: [
                    Color(hue: hue, saturation: 0.42, brightness: 0.30),
                    Color(hue: (hue + 0.06).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

// MARK: - Hover

struct HoverLift: ViewModifier {
    @State private var hovering = false
    var scale: CGFloat = 1.028
    var corner: CGFloat = Theme.corner

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? scale : 1)
            .shadow(color: .black.opacity(hovering ? 0.45 : 0.2), radius: hovering ? 22 : 10, y: hovering ? 12 : 6)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        hovering ? Theme.accent.opacity(0.4) : Theme.stroke,
                        lineWidth: 1
                    )
            )
            .animation(Theme.spring, value: hovering)
            .onHover { hovering = $0 }
    }
}
