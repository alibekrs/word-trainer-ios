import SwiftUI
import UIKit
import CoreMotion

// MARK: - Tilt (parallax input)

/// Device tilt, normalised to -1...1. Only the small background view reads it, so a tilt
/// update never redraws a whole screen. ~30 Hz, low-pass filtered, published only when it moves.
@Observable final class Tilt {
    static let shared = Tilt()
    private(set) var offset: CGSize = .zero
    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var smooth: CGSize = .zero

    func start() {
        users += 1
        guard users == 1, Motion.enabled, !Motion.tour, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let g = m?.gravity else { return }
            let target = CGSize(width: g.x, height: g.y + 0.6)   // phone held at a natural reading angle
            smooth.width += (target.width - smooth.width) * 0.18
            smooth.height += (target.height - smooth.height) * 0.18
            let next = CGSize(width: max(-1, min(1, smooth.width)), height: max(-1, min(1, smooth.height)))
            if abs(next.width - offset.width) > 0.008 || abs(next.height - offset.height) > 0.008 { offset = next }
        }
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 { manager.stopDeviceMotionUpdates() }
    }
}

// MARK: - Background art (rendered once per size/theme, cached)

enum BlobArt {
    private static var cache: [String: UIImage] = [:]

    static func layer(_ i: Int, dark: Bool, size: CGSize) -> UIImage {
        let key = "\(i)-\(dark)-\(Int(size.width))x\(Int(size.height))"
        if let c = cache[key] { return c }
        let w = size.width, h = size.height
        typealias Blob = (x: CGFloat, y: CGFloat, r: CGFloat, c: UIColor)
        let d: [[Blob]] = [
            [(0.1, 0.05, 0.75, UIColor(red: 0.11, green: 0.44, blue: 0.84, alpha: 0.9))],
            [(1.0, 0.42, 0.7, UIColor(red: 0.42, green: 0.24, blue: 0.88, alpha: 0.8))],
            [(0.05, 0.98, 0.65, UIColor(red: 0.06, green: 0.61, blue: 0.45, alpha: 0.55))]]
        let l: [[Blob]] = [
            [(0.1, 0.05, 0.75, UIColor(red: 0.56, green: 0.82, blue: 1.0, alpha: 0.9))],
            [(1.0, 0.42, 0.7, UIColor(red: 0.79, green: 0.72, blue: 1.0, alpha: 0.85))],
            [(0.05, 0.98, 0.65, UIColor(red: 0.62, green: 0.94, blue: 0.78, alpha: 0.8))]]
        let blobs = (dark ? d : l)[i]
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            if i == 0 {
                (dark ? UIColor(red: 0.03, green: 0.04, blue: 0.08, alpha: 1) : UIColor(red: 0.9, green: 0.93, blue: 0.97, alpha: 1)).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }
            for b in blobs {
                let center = CGPoint(x: b.x * w, y: b.y * h), radius = b.r * max(w, h) * 0.6
                let colors = [b.c.cgColor, b.c.withAlphaComponent(0).cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    cg.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
                }
            }
        }
        cache[key] = img
        return img
    }
}

struct ScreenBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geo in
            ParallaxLayers(size: CGSize(width: geo.size.width + 80, height: geo.size.height + 80), dark: scheme == .dark)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The only view that reads tilt: three cached images shifted by different amounts.
private struct ParallaxLayers: View {
    let size: CGSize
    let dark: Bool
    private let tilt = Tilt.shared
    var body: some View {
        let o = tilt.offset
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let k: CGFloat = [6, 14, 24][i]
                Image(uiImage: BlobArt.layer(i, dark: dark, size: size))
                    .offset(x: o.width * k, y: o.height * k)
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear { tilt.start() }
        .onDisappear { tilt.stop() }
    }
}

// MARK: - Mascot

enum MascotArt {
    private static var cache: [Int: UIImage] = [:]
    static func body(_ side: CGFloat) -> UIImage {
        let key = Int(side)
        if let c = cache[key] { return c }
        let s = CGSize(width: side, height: side)
        let img = UIGraphicsImageRenderer(size: s).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: s).insetBy(dx: side * 0.04, dy: side * 0.06)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: side * 0.08), blur: side * 0.18, color: UIColor(red: 0.31, green: 0.55, blue: 1, alpha: 0.45).cgColor)
            UIBezierPath(ovalIn: rect).addClip()
            let colors = [UIColor(red: 0.62, green: 0.82, blue: 1, alpha: 1).cgColor,
                          UIColor(red: 0.31, green: 0.55, blue: 1, alpha: 1).cgColor,
                          UIColor(red: 0.48, green: 0.36, blue: 1, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
            let c = CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.3)
            cg.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: rect.width * 0.85, options: [.drawsAfterEndLocation])
            cg.restoreGState()
            UIColor.white.withAlphaComponent(0.85).setFill()
            UIBezierPath(ovalIn: CGRect(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.14, width: rect.width * 0.14, height: rect.height * 0.1)).fill()
        }
        cache[key] = img
        return img
    }
}

/// Breathes and blinks from the clock; bounces on tap (damped sine from the tap time).
struct Mascot: View {
    var size: CGFloat = 74
    var happy = false
    @State private var tapTime = Date.distantPast
    @State private var visible = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        let tap = tapTime                         // read here so a tap redraws the Canvas
        let live = visible && phase == .active && Motion.enabled && !Motion.tour
        let isHappy = happy
        TimelineView(.animation(minimumInterval: 1 / Motion.fps, paused: !live)) { tl in
            Canvas { g, sz in
                let now = tl.date
                let t = now.timeIntervalSinceReferenceDate
                let since = now.timeIntervalSince(tap)
                let bounce = since < 1.4 ? sin(since * 16) * exp(-since * 4.5) : 0
                let breathe = live ? sin(t * 2.2) * 0.025 : 0
                let sx = 1 + bounce * 0.14 + breathe, sy = 1 - bounce * 0.14 - breathe
                var c = g
                c.translateBy(x: sz.width / 2, y: sz.height)
                c.scaleBy(x: sx, y: sy)
                c.translateBy(x: -sz.width / 2, y: -sz.height)
                c.draw(Image(uiImage: MascotArt.body(sz.width)), in: CGRect(origin: .zero, size: sz))

                let blinking = live && t.truncatingRemainder(dividingBy: 4.2) < 0.14
                let eyeH = sz.height * (blinking ? 0.03 : 0.16), eyeW = sz.width * 0.11
                let ink = GraphicsContext.Shading.color(Color(red: 0.06, green: 0.08, blue: 0.2))
                for x in [0.36, 0.58] {
                    c.fill(Path(ellipseIn: CGRect(x: sz.width * x, y: sz.height * 0.43 - eyeH / 2, width: eyeW, height: eyeH)), with: ink)
                }
                var smile = Path()
                let y0 = sz.height * 0.64, depth = sz.height * (isHappy || since < 1.4 ? 0.12 : 0.06)
                smile.move(to: CGPoint(x: sz.width * 0.38, y: y0))
                smile.addQuadCurve(to: CGPoint(x: sz.width * 0.64, y: y0), control: CGPoint(x: sz.width * 0.51, y: y0 + depth))
                c.stroke(smile, with: ink, style: StrokeStyle(lineWidth: sz.width * 0.045, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture { tapTime = .now; Haptics.tap() }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityLabel("Маскот")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("mascot")
    }
}

// MARK: - Confetti (positions from time + index hash, no particle state)

struct Confetti: View {
    @State private var start = Date()
    @State private var done = false
    var body: some View {
        if Motion.enabled && !done {
            let n = Motion.lowPower ? 40 : 80
            TimelineView(.animation(minimumInterval: 1 / Motion.fps, paused: done)) { tl in
                Canvas { g, sz in
                    let t = tl.date.timeIntervalSince(start)
                    for i in 0..<n {
                        let a = hash01(i, 1), b = hash01(i, 2), c = hash01(i, 3)
                        let x = a * sz.width + sin(t * 2.4 + b * 6.28) * 18
                        let y = -30 + t * (170 + b * 230) - c * 260
                        guard y > -20, y < sz.height + 20 else { continue }
                        var p = g
                        p.translateBy(x: x, y: y)
                        p.rotate(by: .radians(t * (2 + c * 5)))
                        p.fill(Path(roundedRect: CGRect(x: -4, y: -7, width: 8, height: 14), cornerRadius: 2),
                               with: .color(Color.confettiColors[i % Color.confettiColors.count]))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task { try? await Task.sleep(for: .seconds(4.5)); done = true }
        }
    }
}

// MARK: - Progress ring

struct Ring: View {
    var value: Double           // 0...1
    var lineWidth: CGFloat = 9
    var color: Color = .mint
    @State private var shown = 0.0
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [color.mix(with: .white, by: 0.25), color], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(Motion.spring?.delay(0.15)) { shown = min(1, value) } }
        .onChange(of: value) { _, v in withAnimation(Motion.spring) { shown = min(1, v) } }
    }
}

// MARK: - Theme change "curtain": snapshot of the old screen with a growing round window

enum ThemeSwitcher {
    static var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
    }
    static func style(_ t: Int) -> UIUserInterfaceStyle { [.unspecified, .light, .dark][max(0, min(2, t))] }

    static func apply(_ theme: Int, from point: CGPoint?) {
        guard let w = window else { return }
        let target = style(theme)
        guard let p = point, Motion.enabled, let snap = w.snapshotView(afterScreenUpdates: false) else {
            w.overrideUserInterfaceStyle = target; return
        }
        snap.isUserInteractionEnabled = false
        w.addSubview(snap)
        w.overrideUserInterfaceStyle = target
        let b = w.bounds
        let maxR = hypot(max(p.x, b.width - p.x), max(p.y, b.height - p.y)) + 4
        func path(_ r: CGFloat) -> CGPath {
            let path = UIBezierPath(rect: b)
            path.append(UIBezierPath(arcCenter: p, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true))
            return path.cgPath
        }
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        mask.path = path(maxR)
        snap.layer.mask = mask
        let a = CABasicAnimation(keyPath: "path")
        a.fromValue = path(1); a.toValue = path(maxR)
        a.duration = 0.6
        a.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.0, 0.2, 1)
        CATransaction.begin()
        CATransaction.setCompletionBlock { snap.removeFromSuperview() }
        mask.add(a, forKey: "reveal")
        CATransaction.commit()
    }
}
