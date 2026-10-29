import AppKit
import CoreGraphics
import Foundation

// Renders the Mangla app icon: a cream manga-volume cover with a sumi-ink "M"
// and a vermilion obi band, inside the standard macOS icon grid.
//
// Usage: swift Scripts/make-icon.swift [output.png]
//        Scripts/make-icon.sh builds the full AppIcon.icns from it.

let output = URL(
    fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "AppIcon.png"
)

// MARK: - Canvas

let side: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil,
    width: Int(side),
    height: Int(side),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

ctx.setShouldAntialias(true)
ctx.setAllowsAntialiasing(true)
// Work in SVG-style coordinates (origin top-left, y down).
ctx.translateBy(x: 0, y: side)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

// MARK: - Geometry

/// Body of the icon: 824 pt square on the standard 1024 pt macOS grid,
/// with Apple's continuous-corner curvature (corner extends 267.5 pt).
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerExtent: CGFloat = 267.5
let cornerHandle: CGFloat = 191.3

func squirclePath(_ r: CGRect, extent e: CGFloat, handle a: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let x0 = r.minX, y0 = r.minY, x1 = r.maxX, y1 = r.maxY
    p.move(to: CGPoint(x: x0 + e, y: y0))
    p.addLine(to: CGPoint(x: x1 - e, y: y0))
    p.addCurve(
        to: CGPoint(x: x1, y: y0 + e),
        control1: CGPoint(x: x1 - e + a, y: y0),
        control2: CGPoint(x: x1, y: y0 + e - a)
    )
    p.addLine(to: CGPoint(x: x1, y: y1 - e))
    p.addCurve(
        to: CGPoint(x: x1 - e, y: y1),
        control1: CGPoint(x: x1, y: y1 - e + a),
        control2: CGPoint(x: x1 - e + a, y: y1)
    )
    p.addLine(to: CGPoint(x: x0 + e, y: y1))
    p.addCurve(
        to: CGPoint(x: x0, y: y1 - e),
        control1: CGPoint(x: x0 + e - a, y: y1),
        control2: CGPoint(x: x0, y: y1 - e + a)
    )
    p.addLine(to: CGPoint(x: x0, y: y0 + e))
    p.addCurve(
        to: CGPoint(x: x0 + e, y: y0),
        control1: CGPoint(x: x0, y: y0 + e - a),
        control2: CGPoint(x: x0 + e - a, y: y0)
    )
    p.closeSubpath()
    return p
}

/// Polygon with each corner replaced by a quadratic curve of radius `radius`.
func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let n = points.count
    for index in 0..<n {
        let point = points[index]
        let previous = points[(index - 1 + n) % n]
        let next = points[(index + 1) % n]

        let v1 = CGPoint(x: previous.x - point.x, y: previous.y - point.y)
        let v2 = CGPoint(x: next.x - point.x, y: next.y - point.y)
        let l1 = hypot(v1.x, v1.y)
        let l2 = hypot(v2.x, v2.y)
        let radius = min(radius, l1 / 2, l2 / 2)

        let start = CGPoint(
            x: point.x + v1.x / l1 * radius,
            y: point.y + v1.y / l1 * radius
        )
        let end = CGPoint(
            x: point.x + v2.x / l2 * radius,
            y: point.y + v2.y / l2 * radius
        )

        if index == 0 {
            path.move(to: start)
        } else {
            path.addLine(to: start)
        }
        path.addQuadCurve(to: end, control: point)
    }
    path.closeSubpath()
    return path
}

let body = squirclePath(bodyRect, extent: cornerExtent, handle: cornerHandle)

// MARK: - Palette

let paperTop = color(0xFFFDF7)
let paperUpper = color(0xFBF5E8)
let paperMid = color(0xF4EAD6)
let paperBottom = color(0xE6D5B8)
let inkTop = color(0x2E2A26)
let inkMid = color(0x1A1613)
let inkBottom = color(0x0A0807)
let obiTop = color(0xF86440)
let obiMid = color(0xE24528)
let obiBottom = color(0xB92C15)
let obiEdge = color(0x7A1B08, 0.35)
let obiLight = color(0xFFB49B, 0.28)
let obiShade = color(0x5C1204, 0.22)
let paperShade = color(0x8A6A3E, 0.16)
let mShadow = color(0x3B2410, 0.20)

// MARK: - Gradients

func linearGradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(
        colorsSpace: space,
        colors: stops.map(\.1) as CFArray,
        locations: stops.map(\.0)
    )!
}

func fillLinear(
    _ path: CGPath,
    gradient: CGGradient,
    from start: CGPoint,
    to end: CGPoint
) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: start,
        end: end,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()
}

let paperGradient = linearGradient([
    (0.00, paperTop), (0.30, paperUpper), (0.66, paperMid), (1.00, paperBottom)
])
let inkGradient = linearGradient([
    (0.00, inkTop), (0.45, inkMid), (1.00, inkBottom)
])
let obiGradient = linearGradient([
    (0.00, obiTop), (0.42, obiMid), (1.00, obiBottom)
])
let obiShadeGradient = linearGradient([
    (0.00, color(0x5C1204, 0.30)), (1.00, color(0x5C1204, 0.00))
])
let paperShadeGradient = linearGradient([
    (0.55, color(0x8A6A3E, 0.00)), (1.00, paperShade)
])
let rimGradient = linearGradient([
    (0.00, color(0xFFFFFF, 0.62)),
    (0.42, color(0xFFFFFF, 0.16)),
    (1.00, color(0xFFFFFF, 0.34))
])

// MARK: - Outer shadow

ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: 8),
    blur: 18,
    color: color(0x000000, 0.30)
)
ctx.setFillColor(paperUpper)
ctx.addPath(body)
ctx.fillPath()
ctx.restoreGState()

// MARK: - Cover

ctx.saveGState()
ctx.addPath(body)
ctx.clip()

fillLinear(
    body,
    gradient: paperGradient,
    from: CGPoint(x: 1024 * 0.12, y: 0),
    to: CGPoint(x: 1024 * 0.72, y: 1024)
)

// Soft light falling across the upper-left of the paper.
if let glow = CGGradient(
    colorsSpace: space,
    colors: [
        color(0xFFFFFF, 0.78),
        color(0xFFFFFF, 0.28),
        color(0xFFFFFF, 0.0),
    ] as CFArray,
    locations: [0.0, 0.45, 1.0]
) {
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 1024 * 0.26, y: 1024 * 0.05),
        startRadius: 0,
        endCenter: CGPoint(x: 1024 * 0.26, y: 1024 * 0.05),
        endRadius: 1024 * 0.95,
        options: []
    )
}

fillLinear(
    body,
    gradient: paperShadeGradient,
    from: CGPoint(x: 0, y: 1024 * 0.55),
    to: CGPoint(x: 0, y: 1024)
)

// MARK: - Obi (the vermilion paper band around the bottom of the volume)

let obiTopY: CGFloat = 726
let obiRect = CGRect(x: 100, y: obiTopY, width: 824, height: 924 - obiTopY)
let obiPath = CGPath(rect: obiRect, transform: nil)

ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -6),
    blur: 16,
    color: obiShade
)
ctx.setFillColor(obiMid)
ctx.addPath(obiPath)
ctx.fillPath()
ctx.restoreGState()

// Gradient pass is clipped so the band stays crisp; the shadow was cast above
// by the solid pass, which would have been clipped away here.
ctx.saveGState()
ctx.addPath(obiPath)
ctx.clip()
ctx.drawLinearGradient(
    obiGradient,
    start: CGPoint(x: obiRect.minX + obiRect.width * 0.1, y: obiRect.minY),
    end: CGPoint(x: obiRect.minX + obiRect.width * 0.6, y: obiRect.maxY),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
ctx.restoreGState()

// Band edges: a soft shadow just above, a dark seam, a faint paper highlight.
fillLinear(
    CGPath(rect: CGRect(x: 100, y: obiTopY, width: 824, height: 10), transform: nil),
    gradient: obiShadeGradient,
    from: CGPoint(x: 0, y: obiTopY),
    to: CGPoint(x: 0, y: obiTopY + 10)
)
ctx.setFillColor(obiEdge)
ctx.fill(CGRect(x: 100, y: obiTopY + 1, width: 824, height: 1.5))
ctx.setFillColor(obiLight)
ctx.fill(CGRect(x: 100, y: obiTopY + 4, width: 824, height: 1))

// MARK: - Monogram

let mCenterX: CGFloat = 512
let mTop: CGFloat = 180
let mWidth: CGFloat = 500
let mHeight: CGFloat = 500
let mLeft = mCenterX - mWidth / 2
let mRight = mCenterX + mWidth / 2
let mStem = mWidth * 0.257
let mInnerLeft = mLeft + mStem
let mInnerRight = mRight - mStem
let mBottom = mTop + mHeight
let mValley = mTop + mHeight * 0.63
let mJunction = mTop + mHeight * 0.42

let mPoints: [CGPoint] = [
    CGPoint(x: mLeft, y: mBottom),
    CGPoint(x: mLeft, y: mTop),
    CGPoint(x: mInnerLeft, y: mTop),
    CGPoint(x: mCenterX, y: mValley),
    CGPoint(x: mInnerRight, y: mTop),
    CGPoint(x: mRight, y: mTop),
    CGPoint(x: mRight, y: mBottom),
    CGPoint(x: mInnerRight, y: mBottom),
    CGPoint(x: mInnerRight, y: mJunction),
    CGPoint(x: mCenterX, y: mBottom),
    CGPoint(x: mInnerLeft, y: mJunction),
    CGPoint(x: mInnerLeft, y: mBottom),
]
let monogram = roundedPolygon(mPoints, radius: 30)

ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: 10),
    blur: 16,
    color: mShadow
)
ctx.setFillColor(inkMid)
ctx.addPath(monogram)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(monogram)
ctx.clip()
ctx.drawLinearGradient(
    inkGradient,
    start: CGPoint(x: mLeft + mWidth * 0.15, y: mTop),
    end: CGPoint(x: mLeft + mWidth * 0.75, y: mBottom),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
ctx.restoreGState()

// Hairline key light on the ink, keeps the glyph from looking like a flat sticker.
ctx.saveGState()
ctx.addPath(monogram)
ctx.setStrokeColor(color(0xFFFFFF, 0.055))
ctx.setLineWidth(1.5)
ctx.strokePath()
ctx.restoreGState()

ctx.restoreGState() // end cover clip

// MARK: - Rim

// Core Graphics strokes cannot take a gradient directly, so clip to the
// stroked outline and paint the gradient through it.
let rimPath = body.copy(
    strokingWithWidth: 3,
    lineCap: .butt,
    lineJoin: .miter,
    miterLimit: 10
)
ctx.saveGState()
ctx.addPath(rimPath)
ctx.clip()
ctx.drawLinearGradient(
    rimGradient,
    start: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
    end: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
ctx.restoreGState()

// MARK: - Write

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("error: could not render icon\n".utf8))
    exit(1)
}
guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    "public.png" as CFString,
    1,
    nil
) else {
    FileHandle.standardError.write(Data("error: could not create \(output.path)\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("error: could not write \(output.path)\n".utf8))
    exit(1)
}
print("Wrote \(output.path)")
