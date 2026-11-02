/// A bounded range of page indices around the visible page.
///
/// Scroll windows move a few pages at a time, so the canvas only touches the
/// indices that enter or leave a window instead of walking every page.
struct PageWindow: Equatable, Sendable {
    let range: ClosedRange<Int>

    init?(center: Int, before: Int, after: Int, pageCount: Int) {
        guard pageCount > 0 else { return nil }
        let lower = max(0, center - max(0, before))
        let upper = min(pageCount - 1, center + max(0, after))
        guard lower <= upper else { return nil }
        range = lower...upper
    }

    func contains(_ index: Int) -> Bool {
        range.contains(index)
    }

    /// Indices that are in this window but not in `other`, in ascending order.
    func indices(excluding other: PageWindow) -> [Int] {
        range.filter { !other.contains($0) }
    }
}
