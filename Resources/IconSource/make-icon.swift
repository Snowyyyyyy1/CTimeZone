// Generates the CTimezone app icon.
// Land data: Natural Earth 110m (public domain), same mask as LandMask.
// Usage: swiftc -O make-icon.swift -o /tmp/make-icon && /tmp/make-icon icon-1024.png
import AppKit
import CoreGraphics

let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex>>16)&255)/255, CGFloat((hex>>8)&255)/255, CGFloat(hex&255)/255, a])!
}
let bits = Array(Data(base64Encoded: "AAAAAAAAf4AP/AAAAAAAAAAAAAAAAAAAAAAAAX/z///+AAAAAAAABAAAAAAAAAAAAAYd8P///wAA+AAAAAA8AAAAAAAAAAAwAnw////4AAIAAAAAAGAAAAAAAAAAADivwAf//wAAAAADAAf/wAHYAAAAAADoi3sAP//gAAAAAMAD///sAAAAgBgACfwz/AD/+gAAAwAEHf///+/8gBAP/7/nJdjwD/+AAAH/AA7f///////f4P//////h8H/gAAAf/6//f////////Mf/////9H4D8AeAA+ev///////////AP/////4A0B4AAAD5/////////////Af3////gHgA4AAAH5///////////LwAHgH///gHkAAAAAH4/////////+CIAABAB///4D+AAAAGCx/////////4A8AAIAAf///n/gAAAOCD/////////wA4AAAAAf///n/wAAAbP///////////AgAAAAAP/////wAAADf//////////9AAAAAAAF////0YAAAB///////////9AAAAAAAD////8EAAAB///////////5AAAAAAAD////2AAAAB/f5f///////wAAAAAAAD////gAAAAfxnwP///////jAAAAAAAD////AAAAAPCb3///////+CAAAAAAAD///8AAAAAfALf//////+ECAAAAAAAB///8AAAAAGHQP///////mMAAAAAAAA///8AAAAAH+Ai///////E8AAAAAAAAf//wAAAAAP/AA///////BgAAAAAAAAP//gAAAAAf/73///////gAAAAAAAAAD/AQAAAAAf////f/////gAAAAAAAAAF+AQAAAAB///+/n/////AAAAAAAAAAC+AAAAAAB///+f0H////AAAAAAAAAAAeAwAAAAD////f/B///8gAAAAAAAAAAeGEAAAAH////v+B/z/AAAAAAAAAAAAPMAgAAAD////n+A/B+gAAAAAAAAAAAD8AAAAAD////n4AeB/AgAAAAAAAAAAAPAAAAAH////3gAcAfAgAAAAAAAAAAADAAAAAD////6AAcAfggAAAAAAAAAAABDwAAAD////8wAMATAIAAAAAAAAAAAAr/AAAB/////gAKASAAAAAAAAAAAAAAH/gAAA/////gACAAAIAAAAAAAAAAAAH/8AAAaH///AAAAsGAAAAAAAAAAAAAH/+AAAAB//+AAAAUOAAAAAAAAAAAAAP/+AAAAB//8AAAAYegAAAAAAAAAAAAP//gAAAD//4AAAAMeBgAAAAAAAAAAAP//8AAAB//wAAAAGdiuAAAAAAAAAAAf///AAAA//wAAAACAQHgAAAAAAAAAAP///gAAA//wAAAABwAHwgAAAAAAAAAH///AAAA//wAAAAACIDQIAAAAAAAAAH//+AAAAf/wAAAAAAAAAAAAAAAAAAAD//+AAAA//wgAAAAABxAAAAAAAAAAAD//+AAAA//wgAAAAAPxgBAAAAAAAAAA//8AAAA//jgAAAAAf5gAAAAAAAAAAAf/8AAAA//DgAAAAAf/gAAAAAAAAAAAf/8AAAAf/DAAAAAD//4CAAAAAAAAAAf/wAAAAf/DAAAAAH//4AAAAAAAAAAAf/AAAAAf+CAAAAAH//8AAAAAAAAAAAf/AAAAAP8AAAAAAH//+AAAAAAAAAAA/+AAAAAP8AAAAAAH//+AAAAAAAAAAA/+AAAAAH4AAAAAAD//+AAAAAAAAAAA/8AAAAAHwAAAAAADwf8AAAAAAAAAAA/gAAAAAAAAAAAAACAH4AIAAAAAAAAB/wAAAAAAAAAAAAAAAD4AEAAAAAAAAB+AAAAAAAAAAAAAAAAAAAGAAAAAAAAB6AAAAAAAAAAAAAAAAAwAMAAAAAAAAA8AAAAAAAAAAAAAAAAAQAYAAAAAAAAB4AAAAAAAAAAAAAAAAAAAwAAAAAAAAB4AAAAAAAAAAAAAAAAAAAAAAAAAAAADwAAAAAAAAAACAAAAAAAAAAAAAAAAADgAAAAAAAAAAAAAAAAAAAAAAAAAAAABwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")!)
func land(_ lat: Double, _ lon: Double) -> Bool {
    var lon = lon; while lon < -180 { lon += 360 }; while lon >= 180 { lon -= 360 }
    guard lat < 84, lat > -60 else { return false }
    let r = Int((84 - lat) / 2), col = Int((lon + 180) / 2), i = r * 180 + col
    return bits[i / 8] & (0x80 >> UInt8(i % 8)) != 0
}
let accent = c(0xE07A4B)
let rad = Double.pi / 180

func canvas(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)
    draw(ctx); return ctx.makeImage()!
}
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
func plate(_ ctx: CGContext, _ top: UInt32, _ bottom: UInt32, edge: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: c(0, 0.3))
    ctx.addPath(squircle); ctx.setFillColor(c(bottom)); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [c(top), c(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1, dy: 1), cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setStrokeColor(c(0xFFFFFF, edge)); ctx.setLineWidth(2); ctx.strokePath()
}

// Orthographic dotted globe. Returns a projector for markers.
func globe(_ ctx: CGContext, center: CGPoint, R: Double, lon0: Double, lat0: Double,
           landColor: UInt32, oceanAlpha: CGFloat, sunLon: Double, dayA: CGFloat, nightA: CGFloat,
           step: Double = 3.2) -> (Double, Double) -> CGPoint? {
    let sl0 = sin(lat0 * rad), cl0 = cos(lat0 * rad)
    func proj(_ lat: Double, _ lon: Double) -> (CGPoint, Double)? {
        let la = lat * rad, dl = (lon - lon0) * rad
        let cosc = sl0 * sin(la) + cl0 * cos(la) * cos(dl)
        guard cosc > 0.02 else { return nil }
        let x = R * cos(la) * sin(dl)
        let y = R * (cl0 * sin(la) - sl0 * cos(la) * cos(dl))
        return (CGPoint(x: center.x + x, y: center.y - y), cosc)
    }
    var lat = -58.0
    while lat <= 84 {
        let n = max(1, Int((360 * cos(lat * rad)) / step))
        for k in 0..<n {
            let lon = -180 + (Double(k) + 0.5) * 360 / Double(n)
            guard let (p, cosc) = proj(lat, lon) else { continue }
            let r = CGFloat(R * step * rad * 0.36 * (0.55 + 0.45 * cosc))
            let isLand = land(lat, lon)
            let day = cos((lon - sunLon) * rad) * cos(lat * rad) > -0.05
            let a = isLand ? (day ? dayA : nightA) : oceanAlpha
            guard a > 0 else { continue }
            ctx.setFillColor(c(landColor, a * CGFloat(0.5 + 0.5 * cosc)))
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
        lat += step
    }
    return { lat, lon in proj(lat, lon)?.0 }
}

func markers(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, ring: UInt32, bow: CGFloat) {
    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    ctx.setLineCap(.round); ctx.setStrokeColor(accent); ctx.setLineWidth(14)
    ctx.setLineDash(phase: 0, lengths: [0.1, 30])
    ctx.move(to: a); ctx.addQuadCurve(to: b, control: CGPoint(x: mid.x, y: mid.y - bow)); ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setStrokeColor(c(ring)); ctx.setLineWidth(11)
    ctx.strokeEllipse(in: CGRect(x: a.x - 22, y: a.y - 22, width: 44, height: 44))
    ctx.setFillColor(c(0xE07A4B, 0.25)); ctx.fillEllipse(in: CGRect(x: b.x - 50, y: b.y - 50, width: 100, height: 100))
    ctx.setFillColor(accent); ctx.fillEllipse(in: CGRect(x: b.x - 26, y: b.y - 26, width: 52, height: 52))
}

func save(_ img: CGImage, _ name: String) {
    try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
}


func centerHands(_ ctx: CGContext, center: CGPoint, toward targets: [(CGPoint, CGFloat, CGColor)]) {
    ctx.setLineCap(.round)
    for (target, length, color) in targets {
        let dx = target.x - center.x, dy = target.y - center.y, d = hypot(dx, dy)
        let end = CGPoint(x: center.x + dx / d * length, y: center.y + dy / d * length)
        ctx.setStrokeColor(c(0x161513)); ctx.setLineWidth(54); ctx.move(to: center); ctx.addLine(to: end); ctx.strokePath()
        ctx.setStrokeColor(color); ctx.setLineWidth(30); ctx.move(to: center); ctx.addLine(to: end); ctx.strokePath()
    }
    ctx.setFillColor(c(0x161513)); ctx.fillEllipse(in: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
    ctx.setFillColor(accent); ctx.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
    ctx.setFillColor(c(0x161513)); ctx.fillEllipse(in: CGRect(x: center.x - 10, y: center.y - 10, width: 20, height: 20))
}
// Night globe: dotted Earth with day/night shading; the orange hand aims at the
// Claude marker, the cream hand at the Mac marker.
save(canvas { ctx in
    plate(ctx, 0x2A2724, 0x161513, edge: 0.12)
    ctx.saveGState(); ctx.addPath(squircle); ctx.clip()
    let center = CGPoint(x: 512, y: 520)
    let g = CGGradient(colorsSpace: cs, colors: [c(0xF3EDE2, 0.10), c(0xF3EDE2, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 300, endCenter: center, endRadius: 380, options: [])
    let p = globe(ctx, center: center, R: 330, lon0: 62, lat0: 22, landColor: 0xF3EDE2, oceanAlpha: 0.07, sunLon: 20, dayA: 0.95, nightA: 0.32)
    let mac = p(31.2, 121.5)!, claude = p(52.4, 4.9)!
    markers(ctx, from: mac, to: claude, ring: 0xF3EDE2, bow: 120)
    centerHands(ctx, center: center, toward: [(mac, 150, c(0xF3EDE2)), (claude, 185, accent)])
    ctx.restoreGState()
}, CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png")

