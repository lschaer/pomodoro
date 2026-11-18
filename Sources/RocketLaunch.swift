import SwiftUI
import AppKit

/// A transparent, click-through overlay that flies a rocket from the bottom-left
/// to the top-right corner of the main screen.
@MainActor
enum RocketLaunch {
    private static var window: NSWindow?

    static func play(duration: TimeInterval = 3.0) {
        guard window == nil, let screen = NSScreen.main else { return }

        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                         backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: RocketView(start: Date(), duration: duration))
        w.setFrame(screen.frame, display: true)
        w.orderFrontRegardless()
        window = w

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.3) * 1_000_000_000))
            window?.orderOut(nil)
            window = nil
        }
    }
}

private struct RocketView: View {
    let start: Date
    let duration: TimeInterval

    /// Simple outline: pointed body, round window, two fins. Nose at +x, centered on the origin.
    static let rocketShape: Path = {
        var p = Path()
        // Body
        p.move(to: CGPoint(x: 30, y: 0))
        p.addQuadCurve(to: CGPoint(x: 8, y: -10), control: CGPoint(x: 22, y: -10))
        p.addLine(to: CGPoint(x: -18, y: -10))
        p.addLine(to: CGPoint(x: -18, y: 10))
        p.addLine(to: CGPoint(x: 8, y: 10))
        p.addQuadCurve(to: CGPoint(x: 30, y: 0), control: CGPoint(x: 22, y: 10))
        // Fins
        p.move(to: CGPoint(x: -8, y: -10))
        p.addLine(to: CGPoint(x: -22, y: -20))
        p.addLine(to: CGPoint(x: -18, y: -10))
        p.move(to: CGPoint(x: -8, y: 10))
        p.addLine(to: CGPoint(x: -22, y: 20))
        p.addLine(to: CGPoint(x: -18, y: 10))
        // Window
        p.addEllipse(in: CGRect(x: 2, y: -4, width: 8, height: 8))
        return p
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = min(1, timeline.date.timeIntervalSince(start) / duration)
                let progress = pow(t, 1.7)          // slow lift-off, then accelerate

                // Gentle arc: start off-screen bottom-left, end off-screen top-right.
                let p0 = CGPoint(x: -120, y: size.height + 120)
                let p1 = CGPoint(x: size.width * 0.55, y: size.height * 0.80)
                let p2 = CGPoint(x: size.width + 160, y: -160)
                func point(_ q: Double) -> CGPoint {
                    let a = (1 - q) * (1 - q), b = 2 * (1 - q) * q, c = q * q
                    return CGPoint(x: a * p0.x + b * p1.x + c * p2.x,
                                   y: a * p0.y + b * p1.y + c * p2.y)
                }
                func tangent(_ q: Double) -> CGVector {
                    CGVector(dx: 2 * (1 - q) * (p1.x - p0.x) + 2 * q * (p2.x - p1.x),
                             dy: 2 * (1 - q) * (p1.y - p0.y) + 2 * q * (p2.y - p1.y))
                }

                let ink = Color.primary   // black in light mode, white in dark mode
                let pos = point(progress)
                let dir = tangent(progress)

                // Thin trail that fades out behind the rocket.
                let tailStart = max(0, progress - 0.22)
                var trail = Path()
                trail.move(to: point(tailStart))
                for i in 1...30 { trail.addLine(to: point(tailStart + (progress - tailStart) * Double(i) / 30)) }
                ctx.stroke(trail,
                           with: .linearGradient(Gradient(colors: [ink.opacity(0), ink.opacity(0.35)]),
                                                 startPoint: point(tailStart), endPoint: pos),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

                // Line-art rocket, drawn pointing right and rotated to follow the path.
                var rocket = ctx
                rocket.translateBy(x: pos.x, y: pos.y)
                rocket.rotate(by: .radians(atan2(dir.dy, dir.dx)))
                rocket.stroke(Self.rocketShape, with: .color(ink.opacity(0.85)),
                              style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .ignoresSafeArea()
    }
}
