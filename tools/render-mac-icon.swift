import AppKit

// Renders the Orchestrator logo (the same geometry as OrchestratorLogo) on a transparent
// background, filling the macOS icon grid's content area.
let out = CommandLine.arguments[1]
let indigo = NSColor(srgbRed: 92 / 255, green: 106 / 255, blue: 196 / 255, alpha: 1)
let teal = NSColor(srgbRed: 71 / 255, green: 193 / 255, blue: 191 / 255, alpha: 1)
let hexagon = [CGPoint(x: 50, y: 20), CGPoint(x: 76, y: 35), CGPoint(x: 76, y: 65),
               CGPoint(x: 50, y: 80), CGPoint(x: 24, y: 65), CGPoint(x: 24, y: 35)]
let spokes = [CGPoint(x: 50, y: 20), CGPoint(x: 76, y: 65), CGPoint(x: 24, y: 65)]
let nodes: [(CGPoint, CGFloat)] = [(CGPoint(x: 76, y: 35), 6), (CGPoint(x: 76, y: 65), 6), (CGPoint(x: 50, y: 80), 6),
                                   (CGPoint(x: 24, y: 65), 6), (CGPoint(x: 24, y: 35), 6), (CGPoint(x: 50, y: 50), 5.5)]

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let side = CGFloat(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { fatalError() }
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: side, height: side))
    // The figure spans x 17…83 and y 13…86 (nodes included); fit that into 80% of the canvas.
    let scale = side * 0.80 / 73
    func p(_ point: CGPoint) -> CGPoint {
        // Flip y (Core Graphics starts at the bottom) and centre the figure's box (50, 49.5).
        CGPoint(x: side / 2 + (point.x - 50) * scale, y: side / 2 - (point.y - 49.5) * scale)
    }
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    // Inner spokes, faint.
    cg.setStrokeColor(indigo.withAlphaComponent(0.35).cgColor)
    cg.setLineWidth(2.4 * scale)
    for target in spokes {
        cg.move(to: p(CGPoint(x: 50, y: 50)))
        cg.addLine(to: p(target))
    }
    cg.strokePath()
    // Hexagon.
    cg.setStrokeColor(indigo.cgColor)
    cg.setLineWidth(3.4 * scale)
    cg.addLines(between: hexagon.map(p))
    cg.closePath()
    cg.strokePath()
    // Nodes and the teal head.
    cg.setFillColor(indigo.cgColor)
    for (point, radius) in nodes {
        let c = p(point), r = radius * scale
        cg.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
    cg.setFillColor(teal.cgColor)
    let head = p(CGPoint(x: 50, y: 20)), hr = 7 * scale
    cg.fillEllipse(in: CGRect(x: head.x - hr, y: head.y - hr, width: hr * 2, height: hr * 2))
    NSGraphicsContext.current = nil
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(size).png"))
}
print("rendered")
