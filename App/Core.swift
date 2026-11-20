import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox

// MARK: - Palette

extension Color {
    static let accentBlue = Color(red: 0.31, green: 0.55, blue: 1.0)
    static let good = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let bad = Color(red: 1.0, green: 0.36, blue: 0.32)
    static let mint = Color(red: 0.24, green: 0.86, blue: 0.59)
    static let confettiColors: [Color] = [
        Color(red: 1, green: 0.85, blue: 0.3), .mint, Color(red: 1, green: 0.42, blue: 0.55),
        .accentBlue, Color(red: 0.55, green: 0.42, blue: 1)]
}

// MARK: - Settings (UserDefaults-backed, observed)

@Observable final class Settings {
    static let shared = Settings()
    @ObservationIgnored private let d = UserDefaults.standard

    var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    var sounds: Bool { didSet { d.set(sounds, forKey: "sounds") } }
    var animations: Bool { didSet { d.set(animations, forKey: "animations") } }
    var hideInBackground: Bool { didSet { d.set(hideInBackground, forKey: "hide") } }
    var theme: Int { didSet { d.set(theme, forKey: "theme") } }          // 0 system, 1 light, 2 dark
    var dailyGoal: Int { didSet { d.set(dailyGoal, forKey: "goal") } }

    private init() {
        d.register(defaults: ["haptics": true, "sounds": true, "animations": true, "hide": false, "theme": 0, "goal": 20])
        haptics = d.bool(forKey: "haptics")
        sounds = d.bool(forKey: "sounds")
        animations = d.bool(forKey: "animations")
        hideInBackground = d.bool(forKey: "hide")
        theme = d.integer(forKey: "theme")
        dailyGoal = d.integer(forKey: "goal")
        if ProcessInfo.processInfo.arguments.contains("-uiTour") { theme = 2 }
    }
}

// MARK: - Motion policy

enum Motion {
    /// UI tour (UI tests): infinite loops are paused so XCTest can reach idle.
    static let tour = ProcessInfo.processInfo.arguments.contains("-uiTour")
    static var enabled: Bool { !UIAccessibility.isReduceMotionEnabled && Settings.shared.animations }
    static var lowPower: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
    static var fps: Double { lowPower ? 30 : 60 }
    static var spring: Animation? { enabled ? .spring(response: 0.42, dampingFraction: 0.8) : nil }
    static var snappy: Animation? { enabled ? .spring(response: 0.35, dampingFraction: 0.85) : nil }
}

/// Stable pseudo-random 0..<1 from an index and a seed (no per-particle state needed).
func hash01(_ i: Int, _ seed: Int) -> Double {
    var x = UInt64(truncatingIfNeeded: i) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(truncatingIfNeeded: seed) &* 0xBF58_476D_1CE4_E5B9
    x ^= x >> 31; x = x &* 0x94D0_49BB_1331_11EB; x ^= x >> 29
    return Double(x >> 11) / Double(UInt64(1) << 53)
}

// MARK: - Haptics & sounds

enum Haptics {
    static func tap() { guard Settings.shared.haptics else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { guard Settings.shared.haptics else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { guard Settings.shared.haptics else { return }; UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

enum Sound {
    /// Effects: silent on mute switch, never stop the user's music.
    static func ambient() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    /// Podcast: real playback (works with mute switch, keeps playing in background).
    static func podcast() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    // System sounds follow the ringer switch by themselves.
    static func correct() { if Settings.shared.sounds { AudioServicesPlaySystemSound(1057) } }
    static func wrong() { if Settings.shared.sounds { AudioServicesPlaySystemSound(1521) } }
}

enum Speech {
    static let synth = AVSpeechSynthesizer()
    static var player: AVPlayer?
    /// Pronunciation is an explicit request, so it mixes with music instead of stopping it.
    static func say(_ text: String, audio: URL? = nil) {
        if !LessonPlayer.shared.isPlaying {
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        if let audio {
            player = AVPlayer(url: audio); player?.play(); return
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        u.rate = 0.42
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }
}

// MARK: - Styles

struct PrimaryButton: ButtonStyle {
    var tint: Color = .accentBlue
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(LinearGradient(colors: [tint.mix(with: .white, by: 0.22), tint], startPoint: .top, endPoint: .bottom), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
            .shadow(color: tint.opacity(0.35), radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct GlassButton: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .subheadline.bold() : .headline)
            .padding(.vertical, compact ? 9 : 14)
            .padding(.horizontal, compact ? 14 : 18)
            .glassEffect(.regular, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

extension View {
    /// Non-interactive glass card (interactive glass steals neighbours' taps).
    func glassCard(radius: CGFloat = 26, padding: CGFloat = 16, tint: Color? = nil) -> some View {
        let glass: Glass = tint.map { Glass.regular.tint($0) } ?? Glass.regular
        return self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
    }

    /// Spring-in appearance with a small stagger; instant when motion is off.
    func appear(_ index: Int = 0) -> some View { modifier(AppearIn(index: index)) }
}

struct AppearIn: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .onAppear {
                guard !shown else { return }
                guard let a = Motion.spring else { shown = true; return }
                withAnimation(a.delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

/// Positions in `a` and `b` that belong to their longest common subsequence (case-insensitive).
/// Lets a single missing letter be marked alone instead of everything after it.
func lcsMatch(_ a: [Character], _ b: [Character]) -> (a: Set<Int>, b: Set<Int>) {
    let x = a.map { String($0).lowercased() }, y = b.map { String($0).lowercased() }
    var dp = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
    for i in stride(from: x.count - 1, through: 0, by: -1) {
        for j in stride(from: y.count - 1, through: 0, by: -1) {
            dp[i][j] = x[i] == y[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
        }
    }
    var i = 0, j = 0, ma = Set<Int>(), mb = Set<Int>()
    while i < x.count, j < y.count {
        if x[i] == y[j] { ma.insert(i); mb.insert(j); i += 1; j += 1 }
        else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 } else { j += 1 }
    }
    return (ma, mb)
}

func normalized(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        .replacingOccurrences(of: "’", with: "'")
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

func greeting(_ date: Date = .now) -> String {
    switch Calendar.current.component(.hour, from: date) {
    case 5..<12: "Доброе утро"
    case 12..<18: "Добрый день"
    case 18..<23: "Добрый вечер"
    default: "Доброй ночи"
    }
}
