import AppKit
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (px, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
  let s = CGFloat(px)
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let inset = s * 0.1, r = NSRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
  let bg = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
  NSGradient(starting: NSColor(white: 0.17, alpha: 1), ending: NSColor(white: 0.07, alpha: 1))!.draw(in: bg, angle: -90)
  // iPad outline
  let w = r.width * 0.56, h = w * 0.7
  let pad = NSRect(x: r.midX - w/2, y: r.midY - h/2 + r.height*0.06, width: w, height: h)
  let p = NSBezierPath(roundedRect: pad, xRadius: w*0.09, yRadius: w*0.09); p.lineWidth = max(1, s*0.028)
  NSColor.white.setStroke(); p.stroke()
  // cable
  let c = NSBezierPath(); c.lineWidth = max(1, s*0.028); c.lineCapStyle = .round
  c.move(to: NSPoint(x: pad.midX, y: pad.minY)); c.line(to: NSPoint(x: pad.midX, y: r.minY + r.height*0.13))
  NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.6, alpha: 1).setStroke(); c.stroke()
  NSGraphicsContext.restoreGraphicsState()
  try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
