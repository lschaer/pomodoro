import SwiftUI
import AppKit

/// A ring of dots (like the marks on a clock face) that fills clockwise from the top.
/// It is also the app's visual identity: the idle menu bar icon and the app icon.
enum SecondDots {
    static let count = PomodoroTimer.dotCount

    /// The whole menu bar label — [cup] minutes ◌ — drawn as one template image, so the
    /// ring sits to the right of the number (macOS always puts a separate icon on the left).
    /// Pass `minutes: nil` for the idle icon (just the ring).
    static func menuBarLabel(minutes: Int?, lit: Int, showCup: Bool) -> NSImage {
        let height: CGFloat = 18, ring: CGFloat = 16, gap: CGFloat = 4
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13.5, weight: .regular)
        let text = minutes.map {
            NSAttributedString(string: "\($0)", attributes: [.font: font, .foregroundColor: NSColor.black])
        }
        let textWidth = text.map { ceil($0.size().width) + gap } ?? 0
        let cup = showCup
            ? NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: "Break")?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            : nil
        let cupWidth = cup.map { $0.size.width + gap } ?? 0
        let width = cupWidth + textWidth + ring

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            if let cup {
                cup.draw(in: CGRect(x: 0, y: (height - cup.size.height) / 2,
                                    width: cup.size.width, height: cup.size.height))
                x += cupWidth
            }
            if let text {
                text.draw(at: CGPoint(x: x, y: (height - text.size().height) / 2))
                x += textWidth
            }
            drawRing(in: CGRect(x: x, y: (height - ring) / 2, width: ring, height: ring),
                     lit: lit, dot: 1.35, color: .black, dim: 0.22)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = minutes.map { "\($0) minutes left" } ?? "Pomodoro"
        return image
    }

    /// Draws `count` dots on a circle inside `rect`. The last `lit` (clockwise from the top)
    /// are full strength, so as `lit` drops the empty part sweeps clockwise like a clock hand.
    static func drawRing(in rect: CGRect, lit: Int, dot: CGFloat, color: NSColor, dim: CGFloat) {
        let radius = rect.width / 2 - dot - 0.3
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0..<count {
            let angle = CGFloat.pi / 2 - CGFloat(i) * 2 * .pi / CGFloat(count)   // clockwise from top
            let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            color.withAlphaComponent(i >= count - lit ? 1 : dim).setFill()
            NSBezierPath(ovalIn: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2)).fill()
        }
    }
}

/// Larger version of the ring for the popover.
struct SecondDotsRing: View {
    let lit: Int
    let color: Color
    var size: CGFloat = 40
    var dot: CGFloat = 5

    var body: some View {
        ZStack {
            ForEach(0..<SecondDots.count, id: \.self) { i in
                let angle = Double(i) * 2 * .pi / Double(SecondDots.count) - .pi / 2
                let r = size / 2 - dot / 2
                Circle()
                    .fill(i >= SecondDots.count - lit ? color : Color.secondary.opacity(0.25))
                    .frame(width: dot, height: dot)
                    .offset(x: cos(angle) * r, y: sin(angle) * r)
                    .animation(.easeOut(duration: 0.3), value: lit)
            }
        }
        .frame(width: size, height: size)
    }
}
