// The icon, drawn (MANTRA_MANIFEST swift-apps.md 4): what the app does. A dark tile; on the left a rough, uneven
// waveform (a phone in a kitchen, a car, a hall); in the middle five equalizer bars in the profile's amber; on the
// right the same speech come out even and calm, every peak the same height. The version at the bottom.
import AppKit
let S: CGFloat = 1024
let version = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "1"
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 180, cornerHeight: 180, transform: nil))
ctx.setFillColor(NSColor(srgbRed: 0.04, green: 0.05, blue: 0.06, alpha: 1).cgColor); ctx.fillPath()
let mid: CGFloat = 560
let rough = NSColor(srgbRed: 0.62, green: 0.66, blue: 0.70, alpha: 1)
let even = NSColor(srgbRed: 0.30, green: 0.85, blue: 0.45, alpha: 1)
let amber = NSColor(srgbRed: 0.91, green: 0.64, blue: 0.24, alpha: 1)
// left: uneven bars of a raw recording
let raw: [CGFloat] = [60, 210, 90, 280, 140, 40, 230, 110, 300, 70]
for (i, h) in raw.enumerated() {
    let x = 170 + CGFloat(i) * 26
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: mid - h / 2, width: 14, height: h), cornerWidth: 7, cornerHeight: 7, transform: nil))
    ctx.setFillColor(rough.cgColor); ctx.fillPath()
}
// middle: the equalizer, five sliders with their knobs
let knobs: [CGFloat] = [0.35, 0.6, 0.45, 0.7, 0.5]
for (i, k) in knobs.enumerated() {
    let x = 452 + CGFloat(i) * 30
    ctx.setFillColor(NSColor(white: 0.25, alpha: 1).cgColor); ctx.fill(CGRect(x: x + 5, y: mid - 170, width: 6, height: 340))
    ctx.setFillColor(amber.cgColor)
    ctx.addPath(CGPath(roundedRect: CGRect(x: x - 4, y: mid - 170 + 340 * k - 14, width: 24, height: 28), cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
}
// right: the same speech, even
let calm: [CGFloat] = [120, 190, 150, 200, 160, 190, 130, 180]
for (i, h) in calm.enumerated() {
    let x = 625 + CGFloat(i) * 28
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: mid - h / 2, width: 14, height: h), cornerWidth: 7, cornerHeight: 7, transform: nil))
    ctx.setFillColor(even.cgColor); ctx.fillPath()
}
("FREE" as NSString).draw(at: NSPoint(x: 210, y: 760), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 96, weight: .bold), .foregroundColor: even])
("v" + version as NSString).draw(at: NSPoint(x: 210, y: 140), withAttributes: [.font: NSFont.systemFont(ofSize: 92, weight: .semibold), .foregroundColor: NSColor(white: 0.78, alpha: 1)])
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
print("icon_1024.png v" + version)
