import SwiftUI

struct MoreView: View {
    @Environment(Settings.self) private var settings
    @Environment(WordStore.self) private var store

    var body: some View {
        @Bindable var s = settings
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenTitle(title: "Ещё").appear(0)

                    section {
                        NavigationLink { MyWordsView() } label: { row("Мои слова", value: "\(store.words.count)", chevron: true) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("myWords")
                        Divider().opacity(0.5)
                        Stepper(value: $s.dailyGoal, in: 5...100, step: 5) {
                            row("Дневная цель", value: "\(settings.dailyGoal) слов")
                        }
                        .padding(.vertical, 4)
                    }
                    .appear(1)

                    section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Тема").fontWeight(.bold)
                            ThemeChips()
                        }
                        .padding(.vertical, 6)
                        Divider().opacity(0.5)
                        Toggle("Вибрация", isOn: $s.haptics).fontWeight(.bold).padding(.vertical, 4).accessibilityIdentifier("toggleHaptics")
                        Divider().opacity(0.5)
                        Toggle("Звуки", isOn: $s.sounds).fontWeight(.bold).padding(.vertical, 4)
                        Divider().opacity(0.5)
                        Toggle("Анимации", isOn: $s.animations).fontWeight(.bold).padding(.vertical, 4).accessibilityIdentifier("toggleAnimations")
                        Divider().opacity(0.5)
                        Toggle("Скрывать в фоне", isOn: $s.hideInBackground).fontWeight(.bold).padding(.vertical, 4)
                    }
                    .tint(.good)
                    .appear(2)

                    section {
                        NavigationLink { LicensesView() } label: { row("Источники и лицензии", chevron: true) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("licenses")
                    }
                    .appear(3)
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .background(ScreenBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func section<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }.glassCard(radius: 24)
    }

    private func row(_ title: String, value: String? = nil, chevron: Bool = false) -> some View {
        HStack {
            Text(title).fontWeight(.bold)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary) }
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Theme buttons (not a segmented picker). The tap point is where the "curtain" circle grows from.
struct ThemeChips: View {
    @Environment(Settings.self) private var settings
    private let names = ["Системная", "Светлая", "Тёмная"]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                let on = settings.theme == i
                Text(names[i])
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(on ? Color.accentBlue : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(on ? Color.accentBlue.opacity(0.18) : Color.primary.opacity(0.06), in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture(coordinateSpace: .global) { p in
                        guard !on else { return }
                        ThemeSwitcher.apply(i, from: p)      // snapshot first, then change state
                        settings.theme = i
                        Haptics.tap()
                    }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("theme\(i)")
            }
        }
    }
}

// MARK: - My words

struct MyWordsView: View {
    @Environment(WordStore.self) private var store
    @State private var editing: Word?
    @State private var adding = false

    var body: some View {
        List {
            ForEach(store.words) { w in
                Button { editing = w } label: {
                    HStack {
                        Text(w.en).fontWeight(.bold)
                        Spacer()
                        Text(w.ru.isEmpty ? "без перевода" : w.ru).foregroundStyle(w.ru.isEmpty ? Color.bad : .secondary).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .onDelete { idx in store.remove(Set(idx.map { store.words[$0].id })); Haptics.tap() }
        }
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .navigationTitle("Мои слова")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Добавить слова")
                    .accessibilityIdentifier("addWords")
            }
        }
        .overlay {
            if store.words.isEmpty {
                ContentUnavailableView("Пока пусто", systemImage: "text.book.closed", description: Text("Нажми «+» и впиши слова, или добавь готовый набор."))
            }
        }
        .sheet(item: $editing) { EditWordSheet(word: $0) }
        .sheet(isPresented: $adding) { AddWordsSheet() }
    }
}

struct EditWordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordStore.self) private var store
    let word: Word
    @State private var en = ""
    @State private var ru = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Слово", text: $en).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Перевод", text: $ru)
            }
            .navigationTitle("Слово")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { store.update(word.id, en: en, ru: ru); Haptics.success(); dismiss() }
                        .disabled(en.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { en = word.en; ru = word.ru }
        }
        .presentationDetents([.medium])
    }
}

struct AddWordsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordStore.self) private var store
    @State private var text = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("По одному в строке или через запятую. Перевод появится сам, его можно поправить.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(minHeight: 160)
                    .accessibilityIdentifier("addWordsText")
                Button(busy ? "Перевожу…" : "Добавить и перевести") { add() }
                    .buttonStyle(PrimaryButton())
                    .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("addWordsConfirm")
                Spacer()
            }
            .padding(20)
            .navigationTitle("Новые слова")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
    }

    private func add() {
        let list = text.split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" }).map { String($0) }
        busy = true
        Task {
            await store.addAndTranslate(list)
            Haptics.success()
            dismiss()
        }
    }
}

struct LicensesView: View {
    private let items: [(String, String)] = [
        ("Список слов", "New General Service List 1.2 — Browne, C., Culligan, B. & Phillips, J. Лицензия CC BY-SA 4.0. newgeneralservicelist.com"),
        ("Примеры предложений", "Tatoeba (tatoeba.org). Лицензия CC BY 2.0 FR."),
        ("Словарь и произношение", "Free Dictionary API (dictionaryapi.dev), данные Wiktionary. Лицензия CC BY-SA."),
        ("Подкаст", "6 Minute English, BBC Learning English. Воспроизводится из открытой ленты подкаста."),
        ("Перевод", "Translate.googleapis.com и MyMemory (mymemory.translated.net), бесплатный доступ без ключа.")]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(items, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.0).font(.headline)
                        Text(item.1).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .glassCard(radius: 22)
                }
            }
            .padding(20)
        }
        .background(ScreenBackground())
        .navigationTitle("Источники и лицензии")
        .navigationBarTitleDisplayMode(.inline)
    }
}
