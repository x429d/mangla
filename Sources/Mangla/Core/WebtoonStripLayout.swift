import CoreGraphics

/// Geometry of the continuous vertical strip.
///
/// The layout only depends on the page aspect ratios and the strip width, so
/// the canvas can cache it and avoid walking every page on unrelated SwiftUI
/// updates.
struct WebtoonStripLayout: Equatable {
    static let minimumPageHeight: CGFloat = 160
    static let maximumStripWidth: CGFloat = 1000

    static let empty = WebtoonStripLayout(
        stripWidth: 0,
        heights: [],
        tops: [],
        totalHeight: 0
    )

    let stripWidth: CGFloat
    let heights: [CGFloat]
    let tops: [CGFloat]
    let totalHeight: CGFloat

    static func make(pages: [PageSlot], viewportWidth: CGFloat) -> WebtoonStripLayout {
        let width = max(viewportWidth, 1)
        let stripWidth = min(width, maximumStripWidth)

        var heights: [CGFloat] = []
        var tops: [CGFloat] = []
        heights.reserveCapacity(pages.count)
        tops.reserveCapacity(pages.count)

        var top: CGFloat = 0
        for page in pages {
            let height = max(minimumPageHeight, stripWidth / max(page.aspectRatio, 0.05))
            heights.append(height)
            tops.append(top)
            top += height
        }

        return WebtoonStripLayout(
            stripWidth: stripWidth,
            heights: heights,
            tops: tops,
            totalHeight: top
        )
    }

    /// Index of the page whose top is closest to, but not below, `y`.
    func pageIndex(containingY y: CGFloat) -> Int {
        guard !tops.isEmpty else { return 0 }
        var low = 0
        var high = tops.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            if tops[mid] <= y {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
