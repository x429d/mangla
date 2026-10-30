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

    static let spring = Animation.spring(response: 0.36, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.24, dampingFraction: 0.86)

    static func hue(for string: String) -> Double {
        let value = string.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Double(value % 360) / 360
    }
}

enum Format {
    static func pages(_ count: Int) -> String {
        Localization.current.counted(count, .page)
    }

    static func chapters(_ count: Int) -> String {
        Localization.current.counted(count, .chapter)
    }

    static func mangas(_ count: Int) -> String {
        Localization.current.counted(count, .manga)
    }

    static func collections(_ count: Int) -> String {
        Localization.current.counted(count, .collection)
    }

    static func pagesCompact(_ count: Int) -> String {
        Localization.current.counted(count, .page, compact: true)
    }

    static func chaptersCompact(_ count: Int) -> String {
        Localization.current.counted(count, .chapter, compact: true)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - Shared visual components

struct LogoMark: View {
    var size: CGFloat = 34

    private var cornerRadius: CGFloat { size * 0.2245 }
    private var monogramSize: CGFloat { size * 0.607 }
    private var obiHeight: CGFloat { size * 0.24 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 1.000, green: 0.992, blue: 0.969), location: 0),
                        .init(color: Color(red: 0.984, green: 0.961, blue: 0.910), location: 0.30),
                        .init(color: Color(red: 0.957, green: 0.918, blue: 0.839), location: 0.66),
                        .init(color: Color(red: 0.902, green: 0.835, blue: 0.722), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RadialGradient(
                    colors: [.white.opacity(0.55), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: size * 0.9
                )
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color(red: 0.973, green: 0.392, blue: 0.251),
                        Color(red: 0.886, green: 0.271, blue: 0.157),
                        Color(red: 0.725, green: 0.173, blue: 0.082),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: obiHeight)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.black.opacity(0.16))
                        .frame(height: max(0.5, size * 0.004))
                }
                .shadow(color: .black.opacity(0.18), radius: size * 0.02, y: -size * 0.004)
            }
            .overlay {
                LogoMonogram()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.180, green: 0.165, blue: 0.149),
                                Color(red: 0.102, green: 0.086, blue: 0.075),
                                Color(red: 0.039, green: 0.031, blue: 0.027),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: monogramSize, height: monogramSize)
                    .offset(y: -size * 0.0995)
                    .shadow(color: .black.opacity(0.18), radius: size * 0.02, y: size * 0.018)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(0.22), lineWidth: max(0.5, size * 0.005))
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: size * 0.10, y: size * 0.04)
            .shadow(color: Theme.accent.opacity(0.22), radius: size * 0.28, y: size * 0.10)
    }
}

/// The "M" of the app icon, drawn as the same rounded polygon so the in-app
/// mark and the Dock icon stay identical.
private struct LogoMonogram: Shape {
    func path(in rect: CGRect) -> Path {
        let stem: CGFloat = 0.257
        let valley: CGFloat = 0.63
        let junction: CGFloat = 0.42
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: stem, y: 0),
            CGPoint(x: 0.5, y: valley), CGPoint(x: 1 - stem, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 1 - stem, y: 1),
            CGPoint(x: 1 - stem, y: junction), CGPoint(x: 0.5, y: 1),
            CGPoint(x: stem, y: junction), CGPoint(x: stem, y: 1),
        ]
        return logoRoundedPolygon(points, radius: 0.06, in: rect)
    }

    private func logoRoundedPolygon(
        _ normalized: [CGPoint],
        radius: CGFloat,
        in rect: CGRect
    ) -> Path {
        let points = normalized.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
        }
        let r = radius * rect.width
        var path = Path()
        let n = points.count
        for index in 0..<n {
            let p = points[index]
            let previous = points[(index - 1 + n) % n]
            let next = points[(index + 1) % n]
            let v1 = CGPoint(x: previous.x - p.x, y: previous.y - p.y)
            let v2 = CGPoint(x: next.x - p.x, y: next.y - p.y)
            let l1 = sqrt(v1.x * v1.x + v1.y * v1.y)
            let l2 = sqrt(v2.x * v2.x + v2.y * v2.y)
            let rr = min(r, l1 / 2, l2 / 2)
            let start = CGPoint(x: p.x + v1.x / l1 * rr, y: p.y + v1.y / l1 * rr)
            let end = CGPoint(x: p.x + v2.x / l2 * rr, y: p.y + v2.y / l2 * rr)
            if index == 0 {
                path.move(to: start)
            } else {
                path.addLine(to: start)
            }
            path.addQuadCurve(to: end, control: p)
        }
        path.closeSubpath()
        return path
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
        .help(isCollapsed ? t(.showSidebarHelp) : t(.hideSidebarHelp))
        .accessibilityLabel(Text(isCollapsed ? t(.showSidebarHelp) : t(.hideSidebarHelp)))
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
        case .unread: t(.statusUnread)
        case .reading: t(.statusReading)
        case .completed: t(.statusCompleted)
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
                    .fill(
                        LinearGradient(
                            colors: [Theme.accentSoft, Theme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
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
                    Color(hue: (hue + 0.06).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 0.14),
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
