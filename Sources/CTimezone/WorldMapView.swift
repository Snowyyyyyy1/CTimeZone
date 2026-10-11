import CTimezoneKit
import SwiftUI

/// Monochrome dot-matrix world map with live day/night shading and markers
/// for the Mac and Claude time zones.
struct WorldMapView: View {
    let mac: GeoPoint?
    let claude: GeoPoint?

    @Environment(\.colorScheme) private var colorScheme

    private static let aspect = CGFloat(LandMask.columns) / CGFloat(LandMask.rows)
    private static let veilSteps = 6

    var body: some View {
        // The terminator moves ~0.25° a minute; redraw per minute, not per second.
        TimelineView(.everyMinute) { context in
            Canvas { gc, size in
                draw(in: &gc, size: size, sun: SolarPosition.subsolarPoint(at: context.date))
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("World map showing day and night, with the Mac and Claude time zones marked")
        .accessibilityIdentifier("ctz.worldMap")
    }

    private func draw(in gc: inout GraphicsContext, size: CGSize, sun: GeoPoint) {
        let pitch = size.width / CGFloat(LandMask.columns)
        let radius = pitch * 0.36

        var land = Path()
        // Night is a translucent black veil over every cell past the
        // terminator, ramped through twilight. Cells are bucketed by shade so
        // the veil stays a handful of fills.
        var veil = Array(repeating: Path(), count: Self.veilSteps)
        for row in 0..<LandMask.rows {
            for column in 0..<LandMask.columns {
                let c = LandMask.coordinate(column: column, row: row)
                let light = SolarPosition.daylight(at: GeoPoint(latitude: c.latitude, longitude: c.longitude), sun: sun)
                let cell = CGRect(x: CGFloat(column) * pitch, y: CGFloat(row) * pitch, width: pitch, height: pitch)
                let darkness = min(max((0.08 - light) / 0.16, 0), 1)
                let step = Int((darkness * Double(Self.veilSteps)).rounded(.up))
                if step > 0 { veil[step - 1].addRect(Self.bleed(cell, column: column, row: row, by: pitch * 4)) }
                if LandMask.isLand(column: column, row: row) {
                    land.addEllipse(in: cell.insetBy(dx: pitch / 2 - radius, dy: pitch / 2 - radius))
                }
            }
        }
        gc.fill(land, with: .color(.primary.opacity(0.5)))
        // A black veil barely shows on a dark card, so dark mode needs far more of it.
        let nightOpacity = colorScheme == .dark ? 0.6 : 0.28
        gc.drawLayer { clipped in
            // Night reaches the map's edges, so the veil ends there at full
            // strength; edge cells bleed outward so the blur cannot thin them.
            clipped.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: pitch * 2.5))
            clipped.drawLayer { layer in
                // Blurring hides the 2° grid steps and the seams between cells.
                layer.addFilter(.blur(radius: pitch * 1.2))
                for (index, path) in veil.enumerated() {
                    let opacity = nightOpacity * Double(index + 1) / Double(Self.veilSteps)
                    layer.fill(path, with: .color(.black.opacity(opacity)))
                }
            }
        }

        let macPoint = mac.map { project($0, size: size) }
        let claudePoint = claude.map { project($0, size: size) }

        if let a = macPoint, let b = claudePoint, hypot(a.x - b.x, a.y - b.y) > pitch * 3 {
            drawArc(in: &gc, from: a, to: b, pitch: pitch, height: size.height)
        }
        if let a = macPoint {
            let ring = CGRect(x: a.x - pitch * 1.4, y: a.y - pitch * 1.4, width: pitch * 2.8, height: pitch * 2.8)
            gc.stroke(Path(ellipseIn: ring), with: .color(.primary), lineWidth: max(1.5, pitch * 0.5))
            label("Mac", at: a, awayFrom: claudePoint, in: &gc, size: size, color: .secondary)
        }
        if let b = claudePoint {
            let halo = CGRect(x: b.x - pitch * 3, y: b.y - pitch * 3, width: pitch * 6, height: pitch * 6)
            gc.fill(Path(ellipseIn: halo), with: .color(.accentColor.opacity(0.22)))
            let dot = CGRect(x: b.x - pitch * 1.3, y: b.y - pitch * 1.3, width: pitch * 2.6, height: pitch * 2.6)
            gc.fill(Path(ellipseIn: dot), with: .color(.accentColor))
            label("Claude", at: b, awayFrom: macPoint, in: &gc, size: size, color: .accentColor)
        }
    }

    /// Extends a cell on the map's border outward by `amount`.
    private static func bleed(_ cell: CGRect, column: Int, row: Int, by amount: CGFloat) -> CGRect {
        var rect = cell
        if column == 0 { rect.origin.x -= amount; rect.size.width += amount }
        if column == LandMask.columns - 1 { rect.size.width += amount }
        if row == 0 { rect.origin.y -= amount; rect.size.height += amount }
        if row == LandMask.rows - 1 { rect.size.height += amount }
        return rect
    }

    /// Dotted arc from Mac to Claude, echoing the app icon's offset arc. It
    /// bows toward whichever map edge has more room.
    private func drawArc(in gc: inout GraphicsContext, from a: CGPoint, to b: CGPoint, pitch: CGFloat, height: CGFloat) {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let room = mid.y > height / 2 ? mid.y : height - mid.y
        let lift = min(max(hypot(b.x - a.x, b.y - a.y) * 0.28, pitch * 4), room - pitch * 2)
        let control = CGPoint(x: mid.x, y: mid.y > height / 2 ? mid.y - lift : mid.y + lift)
        var arc = Path()
        arc.move(to: a)
        arc.addQuadCurve(to: b, control: control)
        gc.stroke(
            arc,
            with: .color(.accentColor.opacity(0.85)),
            style: StrokeStyle(lineWidth: max(2.5, pitch * 0.8), lineCap: .round, dash: [0.1, pitch * 2])
        )
    }

    private func label(
        _ text: String, at point: CGPoint, awayFrom other: CGPoint?,
        in gc: inout GraphicsContext, size: CGSize, color: Color
    ) {
        let resolved = gc.resolve(Text(text).font(.caption.weight(.semibold)).foregroundStyle(color))
        let width = resolved.measure(in: size).width
        let offset = max(12, size.width / CGFloat(LandMask.columns) * 3 + 5)
        // Sit on the side away from the other marker so the arc stays clear,
        // then flip if that side would clip at the map edge.
        var leftSide = other.map { $0.x > point.x } ?? false
        if leftSide, point.x - offset - width < 0 { leftSide = false }
        if !leftSide, point.x + offset + width > size.width { leftSide = true }
        let anchor = CGPoint(x: leftSide ? point.x - offset : point.x + offset, y: point.y)
        gc.draw(resolved, at: anchor, anchor: leftSide ? .trailing : .leading)
    }

    private func project(_ point: GeoPoint, size: CGSize) -> CGPoint {
        let span = LandMask.northLatitude - LandMask.southLatitude
        let lat = min(max(point.latitude, LandMask.southLatitude), LandMask.northLatitude)
        return CGPoint(
            x: (point.longitude + 180) / 360 * size.width,
            y: (LandMask.northLatitude - lat) / span * size.height
        )
    }
}
