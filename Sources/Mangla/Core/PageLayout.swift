import CoreGraphics

enum SpreadBuilder {
    /// Builds reading spreads for single / double-page modes.
    ///
    /// Wide scans (width > height) always occupy a spread of their own and do
    /// not shift the parity of the following pages: pairing simply resumes with
    /// the next page.
    static func spreads(pages: [PageSlot], mode: LayoutMode) -> [ReaderSpread] {
        guard !pages.isEmpty else { return [] }

        if mode != .spread {
            return pages.indices.map { ReaderSpread(id: $0, pageIndices: [$0]) }
        }

        var result: [ReaderSpread] = []
        var index = 0
        while index < pages.count {
            if pages[index].isWide {
                result.append(ReaderSpread(id: index, pageIndices: [index]))
                index += 1
            } else if index + 1 < pages.count, !pages[index + 1].isWide {
                result.append(ReaderSpread(id: index, pageIndices: [index, index + 1]))
                index += 2
            } else {
                result.append(ReaderSpread(id: index, pageIndices: [index]))
                index += 1
            }
        }
        return result
    }
}

enum PageLayoutCalculator {
    /// Computes the page surface and the container (`documentView`) size.
    /// At magnification 1 the surface is fitted according to `fit`.
    static func layout(
        slots: [PageSlot],
        fit: FitMode,
        viewport: CGSize,
        gap: CGFloat = 0
    ) -> ComputedPageLayout {
        let viewport = CGSize(
            width: max(viewport.width.rounded(.down), 1),
            height: max(viewport.height.rounded(.down), 1)
        )

        guard !slots.isEmpty else {
            return ComputedPageLayout(
                containerSize: viewport,
                surfaceRect: CGRect(origin: .zero, size: viewport),
                pageRects: [],
                scale: 1
            )
        }

        let widths = slots.map { max($0.pixelSize.width, 1) }
        let heights = slots.map { max($0.pixelSize.height, 1) }
        let totalWidth = widths.reduce(0, +) + gap * CGFloat(max(0, slots.count - 1))
        let maxHeight = heights.max() ?? 1

        let scale: CGFloat
        switch fit {
        case .fitHeight:
            scale = min(viewport.height / maxHeight, viewport.width / totalWidth)
        case .fitWidth:
            scale = viewport.width / totalWidth
        case .original:
            scale = 1
        }

        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let surfaceWidth = max(1, totalWidth * safeScale)
        let surfaceHeight = max(1, maxHeight * safeScale)

        let containerWidth = max(viewport.width, surfaceWidth)
        let containerHeight = max(viewport.height, surfaceHeight)
        let originX = (containerWidth - surfaceWidth) / 2
        let originY = (containerHeight - surfaceHeight) / 2

        var pageRects: [CGRect] = []
        pageRects.reserveCapacity(slots.count)
        var x: CGFloat = 0
        for (index, width) in widths.enumerated() {
            let scaledWidth = width * safeScale
            let scaledHeight = heights[index] * safeScale
            pageRects.append(CGRect(
                x: x,
                y: (surfaceHeight - scaledHeight) / 2,
                width: scaledWidth,
                height: scaledHeight
            ))
            x += scaledWidth + gap * safeScale
        }

        return ComputedPageLayout(
            containerSize: CGSize(width: containerWidth, height: containerHeight),
            surfaceRect: CGRect(x: originX, y: originY, width: surfaceWidth, height: surfaceHeight),
            pageRects: pageRects,
            scale: safeScale
        )
    }
}
