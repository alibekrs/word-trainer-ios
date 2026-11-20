import SwiftUI

/// What the user types changes every keystroke, so it lives in its own tiny object that only
/// the answer slots read. The quiz screen itself redraws once per question, not per letter.
@Observable final class Typing { var text = "" }

@Observable final class QuizModel {
    private(set) var queue: [Word]
    let total: Int
    private(set) var checked = false
    private(set) var lastOK = false
    private(set) var answered: Word?
    private(set) var lastTyped = ""
    private(set) var finished = false
    private(set) var wrong: [Word] = []
    var hinted = false
    @ObservationIgnored private(set) var results: [UUID: Bool] = [:]
    @ObservationIgnored var recorded = false

    init(_ words: [Word]) { queue = words; total = words.count; finished = words.isEmpty }

    var current: Word? { queue.first }
    var done: Int { total - Set(queue.map(\.id)).count }
    var firstTry: Int { results.values.filter { $0 }.count }

    func check(_ typed: String) {
        guard !checked, let w = current else { return }
        let ok = normalized(typed) == normalized(w.en)
        if results[w.id] == nil { results[w.id] = ok && !hinted }
        queue.removeFirst()
        if !ok {
            if !wrong.contains(where: { $0.id == w.id }) { wrong.append(w) }
            queue.insert(w, at: min(queue.count, 3))   // comes back a few cards later
        }
        answered = w; lastTyped = typed; lastOK = ok; checked = true
    }

    func next() {
        checked = false; hinted = false; answered = nil
        if queue.isEmpty { finished = true }
    }
}

struct QuizView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordStore.self) private var store
    @Environment(DayProgress.self) private var progress
    @Environment(Settings.self) private var settings
    @State private var quiz: QuizModel
    @State private var typing = Typing()
    @FocusState private var focused: Bool

    init(words: [Word]) { _quiz = State(initialValue: QuizModel(words)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenBackground()
            if quiz.finished {
                ResultView(total: quiz.total, firstTry: quiz.firstTry, wrong: quiz.wrong,
                           onRepeat: repeatMistakes, onDone: close)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if let w = quiz.current ?? quiz.answered {
                question(w)
            }
            if quiz.checked, let w = quiz.answered {
                FeedbackCard(word: w, typed: quiz.lastTyped, ok: quiz.lastOK, onNext: next)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .onAppear { focused = true }
        .onChange(of: quiz.finished) { _, f in if f { record() } }
    }

    private func question(_ w: Word) -> some View {
        let shown = quiz.checked ? (quiz.answered ?? w) : w
        return VStack(spacing: 18) {
            HStack(spacing: 12) {
                Button { close() } label: { Image(systemName: "xmark").font(.headline).frame(width: 22, height: 22) }
                    .buttonStyle(GlassButton(compact: true))
                    .accessibilityLabel("Закрыть")
                    .accessibilityIdentifier("closeQuiz")
                ProgressBar(value: Double(quiz.done) / Double(max(quiz.total, 1)))
                Text("\(quiz.done)/\(quiz.total)").font(.subheadline.weight(.heavy)).monospacedDigit().foregroundStyle(.secondary)
            }
            Text("НАПИШИ ПО-АНГЛИЙСКИ").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(.secondary).padding(.top, 14)
            Text(shown.ru.isEmpty ? "🔊 послушай слово" : shown.ru)
                .font(.system(size: 36, weight: .black)).multilineTextAlignment(.center)
                .minimumScaleFactor(0.6).lineLimit(3)
                .contentTransition(.opacity)
                .id(shown.id)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            HStack(spacing: 10) {
                Button { Speech.say(shown.en) } label: { Label("Послушать", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(GlassButton(compact: true))
                    .accessibilityIdentifier("listenButton")
                Button { hint() } label: { Label("Подсказка", systemImage: "lightbulb.fill") }
                    .buttonStyle(GlassButton(compact: true))
                    .disabled(quiz.checked)
                    .accessibilityIdentifier("hintButton")
            }
            AnswerInput(word: shown.en, typing: typing, focused: $focused, checked: quiz.checked, onSubmit: submit)
                .padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .onAppear { if shown.ru.isEmpty { Speech.say(shown.en) } }
    }

    private func submit() {
        if quiz.checked { next(); return }
        guard !typing.text.trimmingCharacters(in: .whitespaces).isEmpty else { focused = true; return }
        withAnimation(Motion.spring) { quiz.check(typing.text) }
        focused = false
        if quiz.lastOK { Haptics.success(); Sound.correct() } else { Haptics.error(); Sound.wrong() }
    }

    private func next() {
        typing.text = ""
        withAnimation(Motion.spring) { quiz.next() }
        if !quiz.finished { focused = true }
    }

    private func hint() {
        guard let w = quiz.current else { return }
        let c = Array(w.en), t = Array(typing.text)
        var i = 0
        while i < t.count, i < c.count, String(t[i]).lowercased() == String(c[i]).lowercased() { i += 1 }
        guard i < c.count else { return }
        typing.text = String(c[0...i])
        quiz.hinted = true
        Haptics.tap()
    }

    private func record() {
        guard !quiz.recorded else { return }
        quiz.recorded = true
        store.record(quiz.results)
        progress.add(quiz.results.count, goal: settings.dailyGoal)
    }

    private func repeatMistakes() {
        record()
        let again = quiz.wrong
        typing.text = ""
        withAnimation(Motion.spring) { quiz = QuizModel(again.shuffled()) }
        focused = true
    }

    private func close() { record(); dismiss() }
}

struct ProgressBar: View {
    var value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.37, green: 0.78, blue: 1), .accentBlue], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(12, geo.size.width * value))
                    .shadow(color: .accentBlue.opacity(0.5), radius: 6)
                    .animation(Motion.spring, value: value)
            }
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityLabel("Прогресс")
        .accessibilityValue("\(Int(value * 100)) процентов")
    }
}

/// Hidden text field + letter slots. The only view that reads `typing.text`.
struct AnswerInput: View {
    let word: String
    @Bindable var typing: Typing
    var focused: FocusState<Bool>.Binding
    let checked: Bool
    let onSubmit: () -> Void

    var body: some View {
        let target = Array(word), typed = Array(typing.text)
        ZStack {
            TextField("", text: $typing.text)
                .focused(focused)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .frame(width: 1, height: 1)
                .opacity(0.02)
                .accessibilityLabel("Ответ")
                .accessibilityIdentifier("quizAnswer")
                .onChange(of: typing.text) { _, v in
                    let limit = target.count > 14 ? target.count + 6 : target.count
                    if v.count > limit { typing.text = String(v.prefix(limit)) }
                }
            if target.count > 14 {
                Text(typing.text.isEmpty ? " " : typing.text)
                    .font(.title.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(checked ? Color.bad : Color.accentBlue, lineWidth: 1.5))
                    .accessibilityHidden(true)
            } else {
                let side = min(36, max(20, 320 / CGFloat(max(target.count, 1)) - 6))
                HStack(spacing: 6) {
                    ForEach(target.indices, id: \.self) { i in
                        let ch = i < typed.count ? String(typed[i]) : ""
                        let right = ch.lowercased() == String(target[i]).lowercased()
                        let isCursor = !checked && i == typed.count
                        let border: Color = checked ? (right ? .good : .bad) : (isCursor ? .accentBlue : Color.primary.opacity(0.15))
                        Text(ch)
                            .font(.system(size: side * 0.62, weight: .heavy, design: .rounded))
                            .foregroundStyle(checked && !right ? Color.bad : Color.primary)
                            .frame(width: side, height: side * 1.32)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: side * 0.32, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
                                .strokeBorder(border, lineWidth: isCursor ? 2 : 1))
                            .scaleEffect(!checked && i == typed.count - 1 ? 1.08 : 1)
                            .opacity(target[i] == " " ? 0 : 1)
                    }
                }
                .animation(Motion.snappy, value: typed.count)
                .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}

struct FeedbackCard: View {
    let word: Word
    let typed: String
    let ok: Bool
    let onNext: () -> Void
    @State private var example: Example?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ok ? "Верно!" : "Почти! Правильно:")
                .font(.title3.weight(.heavy))
                .foregroundStyle(ok ? Color.good : Color.bad)
            Text(ok ? AttributedString(word.en) : highlighted)
                .font(.system(size: 28, weight: .black)).tracking(1)
                .accessibilityIdentifier("correctWord")
            if let example { ExampleRow(example: example).transition(.opacity) }
            Button("Дальше", action: onNext)
                .buttonStyle(PrimaryButton(tint: ok ? .good : .bad))
                .accessibilityIdentifier("nextButton")
        }
        .glassCard(radius: 34, padding: 20, tint: (ok ? Color.good : Color.bad).opacity(0.18))
        .padding(10)
        .task(id: word.id) {
            let e = await Net.examples(word.en, limit: 1).first
            withAnimation(Motion.snappy) { example = e }
        }
    }

    /// Correct spelling with the letters the user missed underlined in green.
    private var highlighted: AttributedString {
        let t = Array(typed.lowercased())
        var s = AttributedString()
        for (i, ch) in word.en.enumerated() {
            var part = AttributedString(String(ch))
            if i >= t.count || String(ch).lowercased() != String(t[i]) {
                part.foregroundColor = .good
                part.underlineStyle = .single
            }
            s += part
        }
        return s
    }
}

struct ExampleRow: View {
    let example: Example
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(example.en).fontWeight(.bold)
            Text(example.ru).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ResultView: View {
    let total: Int
    let firstTry: Int
    let wrong: [Word]
    let onRepeat: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 14) {
                Spacer(minLength: 30)
                Mascot(size: 104, happy: true).appear(0)
                Text("\(firstTry) / \(total)")
                    .font(.system(size: 60, weight: .black)).monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("score")
                    .appear(1)
                Text(wrong.isEmpty ? "Без единой ошибки!" : "с первой попытки")
                    .font(.headline).foregroundStyle(.secondary).appear(2)
                if !wrong.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(wrong) { w in
                            HStack { Text(w.en).fontWeight(.bold); Spacer(); Text(w.ru).foregroundStyle(.secondary) }
                                .padding(.vertical, 10)
                        }
                    }
                    .glassCard(padding: 16)
                    .appear(3)
                }
                Spacer()
                VStack(spacing: 10) {
                    if !wrong.isEmpty {
                        Button("Повторить ошибки", action: onRepeat).buttonStyle(PrimaryButton())
                            .accessibilityIdentifier("repeatMistakes")
                    }
                    Button(action: onDone) { Text("Готово").frame(maxWidth: .infinity) }
                        .buttonStyle(GlassButton())
                        .accessibilityIdentifier("doneButton")
                }
                .appear(4)
            }
            .padding(20)
            Confetti()
        }
        .onAppear { Haptics.success() }
    }
}
