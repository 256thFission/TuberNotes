import SwiftUI
import UIKit

/// Process-stable clock. SwiftUI re-creates `AmbientBackground` on every publish
/// from the view model (zoom, drawing, page changes); a per-instance `Date()`
/// "start" would reset the animation phase each time — that was the "background
/// jumps when you zoom/pan" bug. Anchoring to one static epoch keeps the motion
/// continuous no matter how often the view is rebuilt.
enum AmbientClock {
    static let epoch = Date()
    static var now: TimeInterval { Date().timeIntervalSince(epoch) }
}

/// A ripple spawned by a touch somewhere over the page.
struct AmbientRipple: Identifiable {
    let id = UUID()
    let center: CGPoint
    let start: TimeInterval   // seconds since AmbientClock.epoch
}

/// Shared, observable ripple source. A passive touch observer higher up feeds
/// touch locations here; the backdrop renders them. Kept sparse and gentle.
@MainActor
final class AmbientRippleModel: ObservableObject {
    @Published private(set) var ripples: [AmbientRipple] = []
    private var lastPoint: CGPoint = .zero
    private var lastTime: TimeInterval = -1
    let lifetime: TimeInterval = 1.1

    func add(at point: CGPoint) {
        let now = AmbientClock.now
        // Fine cadence so a moving Pencil leaves a smooth, overlapping trail
        // rather than discrete pops.
        if now - lastTime < 0.035, hypot(point.x - lastPoint.x, point.y - lastPoint.y) < 16 {
            return
        }
        lastPoint = point
        lastTime = now
        ripples.removeAll { now - $0.start > lifetime }
        ripples.append(AmbientRipple(center: point, start: now))
        if ripples.count > 24 { ripples.removeFirst(ripples.count - 24) }
    }
}

/// Minimal, soothing backdrop: black with a few slow, breathing white/grey
/// blotches that drift, plus very soft ripples where the page is touched.
/// Frosted panels blur this, which is what gives them their glassy look.
struct AmbientBackground: View {
    @ObservedObject var rippleModel: AmbientRippleModel

    private let lifetime: TimeInterval = 1.1

    private struct Blob {
        let baseX, baseY, radius, driftX, driftY, driftSpeed, breathSpeed, phase, alpha: CGFloat
    }

    private let blobs: [Blob] = [
        Blob(baseX: 0.20, baseY: 0.18, radius: 320, driftX: 86, driftY: 64, driftSpeed: 0.075, breathSpeed: 0.55, phase: 0.0, alpha: 0.30),
        Blob(baseX: 0.82, baseY: 0.14, radius: 280, driftX: 74, driftY: 80, driftSpeed: 0.063, breathSpeed: 0.47, phase: 1.4, alpha: 0.20),
        Blob(baseX: 0.72, baseY: 0.72, radius: 360, driftX: 98, driftY: 88, driftSpeed: 0.057, breathSpeed: 0.41, phase: 2.6, alpha: 0.26),
        Blob(baseX: 0.24, baseY: 0.82, radius: 300, driftX: 80, driftY: 68, driftSpeed: 0.088, breathSpeed: 0.60, phase: 3.7, alpha: 0.18),
        Blob(baseX: 0.50, baseY: 0.46, radius: 420, driftX: 64, driftY: 98, driftSpeed: 0.049, breathSpeed: 0.35, phase: 5.0, alpha: 0.15),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(AmbientClock.epoch)
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

                // Breathing ombré blotches (heavily blurred).
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 48))
                    for blob in blobs {
                        let cx = blob.baseX * size.width + CGFloat(sin(t * blob.driftSpeed + blob.phase)) * blob.driftX
                        let cy = blob.baseY * size.height + CGFloat(cos(t * blob.driftSpeed * 0.9 + blob.phase)) * blob.driftY
                        let breath = 1 + 0.20 * CGFloat(sin(t * blob.breathSpeed + blob.phase))
                        let r = blob.radius * breath
                        let a = blob.alpha * (0.72 + 0.28 * CGFloat(sin(t * blob.breathSpeed * 0.8 + blob.phase)))
                        let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                        let shading = GraphicsContext.Shading.radialGradient(
                            Gradient(colors: [Color.white.opacity(Double(max(a, 0))), .clear]),
                            center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r
                        )
                        layer.fill(Path(ellipseIn: rect), with: shading)
                    }
                }

                // Ripples: soft blurred blooms with a smooth fade-in/out, spawned
                // closely along the Pencil so they overlap into a fluid glow that
                // melts into the ombré — no hard rings.
                if !rippleModel.ripples.isEmpty {
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 18))
                        for ripple in rippleModel.ripples {
                            let age = t - ripple.start
                            guard age >= 0, age <= lifetime else { continue }
                            let p = age / lifetime
                            let radius = 44 + CGFloat(p) * 70
                            let env = sin(p * .pi)          // smooth 0 → 1 → 0
                            let alpha = 0.06 * env
                            let rect = CGRect(x: ripple.center.x - radius, y: ripple.center.y - radius,
                                              width: radius * 2, height: radius * 2)
                            layer.fill(
                                Path(ellipseIn: rect),
                                with: .radialGradient(
                                    Gradient(colors: [
                                        .white.opacity(alpha),
                                        .white.opacity(alpha * 0.35),
                                        .clear,
                                    ]),
                                    center: ripple.center, startRadius: 0, endRadius: radius
                                )
                            )
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// A *passive* touch observer. It installs a gesture recognizer on the window
/// that reports every touch location (finger or Pencil) but never enters a
/// recognized state and never cancels touches — so the page, tools, scroll view,
/// and buttons all keep full priority and receive their touches normally.
struct AmbientTouchLayer: UIViewRepresentable {
    var onTouch: (CGPoint) -> Void

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onTouch = onTouch
        view.isUserInteractionEnabled = false   // never intercepts anything itself
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {
        uiView.onTouch = onTouch
    }

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var onTouch: ((CGPoint) -> Void)?
        private weak var observedWindow: UIWindow?
        private var recognizer: PassiveTouchRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()

            if let recognizer, let observedWindow {
                observedWindow.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            observedWindow = nil

            guard let window else { return }
            let recognizer = PassiveTouchRecognizer(target: self, action: #selector(noop))
            recognizer.referenceView = self
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.onTouch = { [weak self] point in self?.onTouch?(point) }
            window.addGestureRecognizer(recognizer)
            self.recognizer = recognizer
            self.observedWindow = window
        }

        @objc private func noop() {}

        // Never block or be blocked by anything else.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }
    }
}

/// Observes touches without ever recognizing, so it can't steal input.
final class PassiveTouchRecognizer: UIGestureRecognizer {
    var onTouch: ((CGPoint) -> Void)?
    weak var referenceView: UIView?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        report(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        report(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .failed   // reset cleanly; we never recognize
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .failed
    }

    private func report(_ touches: Set<UITouch>) {
        guard let referenceView else { return }
        // Pencil-only: finger touches are for scrolling/flipping and must not
        // spawn ripples. A Pencil touch does (it isn't used to scroll).
        guard let touch = touches.first(where: { $0.type == .pencil }) else { return }
        onTouch?(touch.location(in: referenceView))
    }
}
