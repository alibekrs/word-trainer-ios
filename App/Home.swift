import SwiftUI

struct HomeView: View {
    @Environment(WordStore.self) private var store
    @Environment(DayProgress.self) private var progress
    @Environment(Settings.self) private var settings
    @State private var session: QuizSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(greeting()).font(.headline).foregroundStyle(.secondary)
                            Text("Слова").font(.system(size: 34, weight: .black)).tracking(-0.5)
                        }
                        Spacer()
                        Mascot(size: 74)
                    }
                    .appear(0)

                    goalCard.appear(1)
                    repeatCard.appear(2)
                    if !store.words.isEmpty { wordsCard.appear(3) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(ScreenBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { _ in MyWordsView() }
        }
        .fullScreenCover(item: $session) { s in QuizView(words: s.words) }
    }

    private var goalCard: some View {
        let goal = settings.dailyGoal
        return HStack(spacing: 16) {
            ZStack {
                Ring(value: Double(progress.today) / Double(max(goal, 1)))
                Text("\(min(progress.today, goal))/\(goal)").font(.system(size: 15, weight: .black)).monospacedDigit()
            }
            .frame(width: 78, height: 78)
            VStack(alignment: .leading, spacing: 4) {
                Text("Цель на сегодня").font(.headline)
                Text(goalText(goal)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .glassCard()
        .accessibilityElement(children: .combine)
    }

    private func goalText(_ goal: Int) -> String {
        let left = max(0, goal - progress.today)
        let streak = progress.streak > 0 ? " Серия: \(progress.streak) дн." : ""
        return (left == 0 ? "Цель выполнена!" : "Ещё \(left) — и день засчитан.") + streak
    }

    private var repeatCard: some View {
        let due = store.due.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(due > 0 ? "Пора повторить" : "Тренировка").font(.headline)
                Spacer()
                Text(due > 0 ? "\(due) сл." : "\(store.words.count) сл.").foregroundStyle(.secondary)
            }
            Button("Начать тренировку") { Haptics.tap(); session = QuizSession(words: store.session()) }
                .buttonStyle(PrimaryButton())
                .disabled(store.words.isEmpty)
                .accessibilityIdentifier("startQuiz")
        }
        .glassCard()
    }

    private var wordsCard: some View {
        VStack(spacing: 0) {
            ForEach(store.words.prefix(5)) { w in
                HStack {
                    Text(w.en).fontWeight(.bold)
                    Spacer()
                    Text(w.ru.isEmpty ? "…" : w.ru).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.vertical, 11)
                Divider().opacity(0.5)
            }
            NavigationLink(value: "words") {
                HStack { Text("Все слова (\(store.words.count))").fontWeight(.bold); Spacer(); Image(systemName: "chevron.right") }
                    .padding(.top, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentBlue)
            .accessibilityIdentifier("allWords")
        }
        .glassCard(padding: 16)
    }
}

struct QuizSession: Identifiable {
    let id = UUID()
    let words: [Word]
}
