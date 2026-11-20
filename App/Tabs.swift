import SwiftUI
import AVFoundation

// MARK: - Word of the day

struct WordOfDayView: View {
    @Environment(WordStore.self) private var store
    @State private var data: DayWord?
    @State private var failed = false
    private let word = NGSL.wordOfDay()

    struct DayWord { var tr: String?; var dict: DictEntry?; var examples: [Example] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ScreenTitle(title: "Слово дня", eyebrow: Date.now.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU"))))
                        .appear(0)
                    card.appear(1)
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .background(ScreenBackground())
            .toolbar(.hidden, for: .navigationBar)
            .task { if data == nil { await load() } }
        }
    }

    private var card: some View {
        let added = store.contains(word)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(word).font(.system(size: 42, weight: .black)).tracking(-0.5).minimumScaleFactor(0.6).lineLimit(1)
                    let pos = data?.dict?.meanings.first?.pos
                    Text([data?.dict?.phonetic, pos].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { Speech.say(word, audio: data?.dict?.audio) } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.title3).frame(width: 30, height: 30)
                }
                .buttonStyle(PrimaryCircle())
                .accessibilityLabel("Послушать")
                .accessibilityIdentifier("dayListen")
            }
            if let tr = data?.tr {
                Text(tr).font(.title3.weight(.heavy)).foregroundStyle(Color.accentBlue)
            }
            ForEach(data?.dict?.meanings ?? [], id: \.self) { m in
                Text("\(Text(m.pos).foregroundStyle(.secondary).font(.footnote.weight(.bold)))  \(m.def)").font(.subheadline)
            }
            ForEach(data?.examples ?? [], id: \.self) { ExampleRow(example: $0) }
            if data == nil && !failed { ProgressView().frame(maxWidth: .infinity).padding() }
            if failed {
                Text("Нет связи. Проверь интернет.").foregroundStyle(.secondary)
                Button("Повторить") { Task { await load() } }.buttonStyle(GlassButton(compact: true))
            }
            Button(added ? "Уже в моих словах" : "Добавить в мои слова") {
                store.add([(en: word, ru: data?.tr ?? "")]); Haptics.success()
            }
            .buttonStyle(PrimaryButton())
            .disabled(added)
            .accessibilityIdentifier("dayAdd")
        }
        .glassCard(padding: 18)
    }

    private func load() async {
        failed = false
        async let tr = Net.translate(word)
        async let dict = Net.dictionary(word)
        async let ex = Net.examples(word)
        let d = DayWord(tr: await tr, dict: await dict, examples: await ex)
        if d.tr == nil && d.dict == nil { failed = true; return }
        withAnimation(Motion.spring) { data = d }
    }
}

struct PrimaryCircle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(11)
            .background(LinearGradient(colors: [Color.accentBlue.mix(with: .white, by: 0.22), .accentBlue], startPoint: .top, endPoint: .bottom), in: Circle())
            .shadow(color: .accentBlue.opacity(0.4), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

// MARK: - Ready-made sets

struct SetsView: View {
    @Environment(WordStore.self) private var store
    @State private var busy: Int?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ScreenTitle(title: "Наборы", subtitle: "\(NGSL.words.count.formatted(.number.locale(Locale(identifier: "ru_RU")))) самых нужных слов, \(NGSL.levelCount) уровней")
                        .appear(0)
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    let have = Set(store.words.map { normalized($0.en) })
                    ForEach(0..<NGSL.levelCount, id: \.self) { i in
                        level(i, have: have).appear(i + 1)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .background(ScreenBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func level(_ i: Int, have: Set<String>) -> some View {
        let list = NGSL.level(i)
        let done = list.filter { have.contains($0) }.count
        let next = list.filter { !have.contains($0) }
        return HStack(spacing: 14) {
            ZStack {
                Ring(value: Double(done) / Double(max(list.count, 1)), lineWidth: 5, color: done == list.count ? .mint : .accentBlue)
                Text("\(i + 1)").font(.headline.weight(.black))
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(NGSL.levelNames[i]).font(.headline)
                Text("\(done) / \(list.count)" + (next.isEmpty ? " · пройден" : " · " + next.prefix(3).joined(separator: ", ") + "…"))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if next.isEmpty {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mint).font(.title2)
            } else if busy == i {
                ProgressView().frame(width: 52)
            } else {
                Button("+20") { add(i, Array(next.prefix(20))) }
                    .buttonStyle(GlassButton(compact: true))
                    .disabled(busy != nil)
                    .accessibilityLabel("Добавить 20 слов уровня \(i + 1)")
                    .accessibilityIdentifier("addLevel\(i + 1)")
            }
        }
        .glassCard(radius: 24, padding: 12)
    }

    private func add(_ i: Int, _ words: [String]) {
        busy = i; Haptics.tap()
        Task {
            let r = await store.addAndTranslate(words)
            withAnimation(Motion.spring) {
                busy = nil
                message = r.failed > 0 ? "Добавлено \(r.added). Без перевода: \(r.failed), впиши в «Мои слова»." : "Добавлено \(r.added) слов с переводом."
            }
            Haptics.success()
        }
    }
}

// MARK: - Lessons (weekly podcast)

@Observable final class LessonPlayer {
    static let shared = LessonPlayer()
    private(set) var current: Episode?
    private(set) var isPlaying = false
    /// Elapsed time ticks twice a second; only the time label reads it.
    @ObservationIgnored let clock = PlayerClock()
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var observer: Any?

    func play(_ e: Episode) {
        Sound.podcast()
        if current?.id != e.id {
            if let observer { player?.removeTimeObserver(observer) }
            let p = AVPlayer(url: e.audio)
            observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak p] t in
                guard let self, let p else { return }
                let s = t.seconds
                if abs(s - self.clock.seconds) >= 0.5 { self.clock.seconds = s }
                if let d = p.currentItem?.duration.seconds, d.isFinite, d != self.clock.duration { self.clock.duration = d }
            }
            player = p
            clock.seconds = 0; clock.duration = 0
            current = e
        }
        player?.play(); isPlaying = true
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { Sound.podcast(); player.play() }
        isPlaying.toggle()
        Haptics.tap()
    }
}

@Observable final class PlayerClock { var seconds = 0.0; var duration = 0.0 }

struct LessonsView: View {
    @Environment(LessonPlayer.self) private var player
    @State private var episodes: [Episode] = []
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ScreenTitle(title: "Уроки", subtitle: "Новый выпуск подкаста каждую неделю, 6 минут").appear(0)
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { i, e in
                        Button { player.play(e); Haptics.tap() } label: { row(e, isNew: i == 0) }
                            .buttonStyle(PressScale())
                            .accessibilityIdentifier("episode\(i)")
                            .appear(i + 1)
                    }
                    if episodes.isEmpty && !failed { ProgressView().padding(40) }
                    if failed {
                        VStack(spacing: 10) {
                            Text("Нет связи. Проверь интернет.").foregroundStyle(.secondary)
                            Button("Повторить") { Task { await load() } }.buttonStyle(GlassButton(compact: true))
                        }.padding(30)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .background(ScreenBackground())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if player.current != nil { MiniPlayer().padding(.horizontal, 14).padding(.bottom, 6).transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .animation(Motion.spring, value: player.current?.id)
            .task { if episodes.isEmpty { await load() } }
        }
    }

    private func row(_ e: Episode, isNew: Bool) -> some View {
        let playing = player.current?.id == e.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(((e.date?.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU")))) ?? "") + (isNew ? " · новый" : ""))
                    .font(.caption.weight(.heavy)).textCase(.uppercase).tracking(1).foregroundStyle(.secondary)
                Spacer()
                if playing { Image(systemName: "waveform").foregroundStyle(Color.accentBlue) }
            }
            Text(e.title).font(.headline).multilineTextAlignment(.leading)
            if !e.summary.isEmpty { Text(e.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading) }
        }
        .foregroundStyle(.primary)
        .glassCard(radius: 24)
    }

    private func load() async {
        failed = false
        let list = await Net.episodes()
        if list.isEmpty { failed = true } else { withAnimation(Motion.spring) { episodes = list } }
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct MiniPlayer: View {
    @Environment(LessonPlayer.self) private var player
    var body: some View {
        HStack(spacing: 12) {
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.headline).frame(width: 20, height: 20)
            }
            .buttonStyle(PrimaryCircle())
            .accessibilityLabel(player.isPlaying ? "Пауза" : "Играть")
            .accessibilityIdentifier("playerToggle")
            VStack(alignment: .leading, spacing: 4) {
                Text(player.current?.title ?? "").font(.subheadline.weight(.bold)).lineLimit(1)
                Waveform(playing: player.isPlaying).frame(height: 22)
            }
            ElapsedLabel(clock: player.clock)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }
}

private struct ElapsedLabel: View {
    let clock: PlayerClock
    var body: some View {
        let s = Int(clock.seconds)
        Text(String(format: "%d:%02d", s / 60, s % 60))
            .font(.footnote.weight(.bold)).monospacedDigit().foregroundStyle(.secondary)
    }
}

/// Bars computed from time + bar index; the timeline pauses with the player.
struct Waveform: View {
    let playing: Bool
    @State private var visible = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        let live = playing && visible && phase == .active && Motion.enabled && !Motion.tour
        TimelineView(.animation(minimumInterval: 1 / Motion.fps, paused: !live)) { tl in
            Canvas { g, sz in
                let t = tl.date.timeIntervalSinceReferenceDate
                let n = 28, gap: CGFloat = 3
                let w = (sz.width - gap * CGFloat(n - 1)) / CGFloat(n)
                for i in 0..<n {
                    let base = 0.25 + hash01(i, 7) * 0.5
                    let wave = live ? (sin(t * (3 + hash01(i, 8) * 4) + Double(i)) + 1) / 2 : 0.4
                    let h = max(3, sz.height * (base * 0.5 + wave * 0.5))
                    let r = CGRect(x: CGFloat(i) * (w + gap), y: (sz.height - h) / 2, width: w, height: h)
                    g.fill(Path(roundedRect: r, cornerRadius: w / 2), with: .color(Color.accentBlue.opacity(live ? 0.9 : 0.45)))
                }
            }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityHidden(true)
    }
}
