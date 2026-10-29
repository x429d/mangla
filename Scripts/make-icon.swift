import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png")

let size: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
let graphics = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = graphics
let ctx = graphics.cgContext

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func roundedRect(_ rect: CGRect, radius: CGFloat, fill: CGColor) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
}

// Background card
let background = CGRect(x: 32, y: 32, width: 960, height: 960)
ctx.saveGState()
let bgPath = CGPath(
    roundedRect: background,
    cornerWidth: 212,
    cornerHeight: 212,
    transform: nil
)
ctx.addPath(bgPath)
ctx.clip()
if let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [color(0.14, 0.145, 0.165), color(0.035, 0.037, 0.045)] as CFArray,
    locations: [0, 1]
) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 200, y: 1024),
        end: CGPoint(x: 800, y: 0),
        options: []
    )
}
if let glow = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [color(0.95, 0.32, 0.20, 0.50), color(0.95, 0.32, 0.20, 0)] as CFArray,
    locations: [0, 1]
) {
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 300, y: 760),
        startRadius: 0,
        endCenter: CGPoint(x: 300, y: 760),
        endRadius: 520,
        options: []
    )
}
ctx.restoreGState()

// Border
ctx.addPath(bgPath)
ctx.setStrokeColor(color(1, 1, 1, 0.09))
ctx.setLineWidth(3)
ctx.strokePath()

// Fanned pages behind
func pageCard(center: CGPoint, rotation: CGFloat, fill: CGColor, shadow: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation)
    let rect = CGRect(x: -245, y: -335, width: 490, height: 670)
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: shadow, color: color(0, 0, 0, 0.55))
    roundedRect(rect, radius: 34, fill: fill)
    ctx.restoreGState()
}

pageCard(center: CGPoint(x: 585, y: 500), rotation: 0.18, fill: color(0.16, 0.17, 0.20), shadow: 48)
pageCard(center: CGPoint(x: 470, y: 500), rotation: -0.10, fill: color(0.55, 0.55, 0.58), shadow: 48)

// Front page
ctx.saveGState()
ctx.translateBy(x: 512, y: 505)
ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 60, color: color(0, 0, 0, 0.65))
let page = CGRect(x: -245, y: -335, width: 490, height: 670)
roundedRect(page, radius: 34, fill: color(0.965, 0.945, 0.905))
ctx.restoreGState()

// Page content
ctx.saveGState()
ctx.translateBy(x: 512, y: 505)

// Header band
let header = CGRect(x: -215, y: 235, width: 430, height: 48)
roundedRect(header, radius: 16, fill: color(0.91, 0.32, 0.23))

// Panels
let panelColor = color(0.18, 0.19, 0.23)
let panel1 = CGRect(x: -215, y: 60, width: 430, height: 145)
roundedRect(panel1, radius: 16, fill: panelColor)

let panel2 = CGRect(x: -215, y: -105, width: 200, height: 140)
roundedRect(panel2, radius: 16, fill: panelColor)
let panel3 = CGRect(x: 15, y: -105, width: 200, height: 140)
roundedRect(panel3, radius: 16, fill: color(0.88, 0.30, 0.22))

// Speed lines inside panel 1
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: panel1, cornerWidth: 16, cornerHeight: 16, transform: nil))
ctx.clip()
ctx.setStrokeColor(color(0.9, 0.91, 0.95, 0.55))
ctx.setLineWidth(3)
for index in 0..<14 {
    let x = CGFloat(index) * 40 - 215
    ctx.move(to: CGPoint(x: x, y: 60))
    ctx.addLine(to: CGPoint(x: x + 90, y: 205))
}
ctx.strokePath()
ctx.restoreGState()

// Text lines
roundedRect(CGRect(x: -215, y: -270, width: 340, height: 16), radius: 8, fill: color(0.18, 0.19, 0.23, 0.85))
roundedRect(CGRect(x: -215, y: -305, width: 260, height: 16), radius: 8, fill: color(0.18, 0.19, 0.23, 0.55))

// Bookmark
let bookmark = CGMutablePath()
bookmark.move(to: CGPoint(x: 150, y: 335))
bookmark.addLine(to: CGPoint(x: 205, y: 335))
bookmark.addLine(to: CGPoint(x: 205, y: 200))
bookmark.addLine(to: CGPoint(x: 177, y: 228))
bookmark.addLine(to: CGPoint(x: 150, y: 200))
bookmark.closeSubpath()
ctx.addPath(bookmark)
ctx.setFillColor(color(0.91, 0.32, 0.23))
ctx.fillPath()

ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try png.write(to: output)
print("Wrote \(output.path)")
