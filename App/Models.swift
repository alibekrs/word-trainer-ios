import Foundation

struct Word: Codable, Identifiable, Hashable {
    var id = UUID()
    var en: String
    var ru: String
    var lastSeen: Date? = nil
    var right = 0
    var wrong = 0

    static let samples: [Word] = [
        Word(en: "necessary", ru: "необходимый"), Word(en: "rhythm", ru: "ритм"),
        Word(en: "separate", ru: "отдельный"), Word(en: "definitely", ru: "определённо"),
        Word(en: "accommodate", ru: "размещать")]
}

/// One shared list. Every mutation is a single assignment, so screens redraw once per change,
/// never per keystroke (editing happens on local drafts and is committed on save).
@Observable final class WordStore {
    private(set) var words: [Word]
    @ObservationIgnored private let demo = Motion.tour
    @ObservationIgnored private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("words.json")

    init() {
        if !Motion.tour, let d = try? Data(contentsOf: url), let w = try? JSONDecoder().decode([Word].self, from: d) {
            words = w
        } else {
            words = Word.samples
        }
    }

    private func commit(_ new: [Word]) {
        words = new
        guard !demo else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(new).write(to: url, options: .atomic)
    }

    func contains(_ en: String) -> Bool { let n = normalized(en); return words.contains { normalized($0.en) == n } }

    @discardableResult
    func add(_ items: [(en: String, ru: String)]) -> [Word] {
        var seen = Set(words.map { normalized($0.en) })
        let fresh = items.compactMap { item -> Word? in
            let en = item.en.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !en.isEmpty, seen.insert(normalized(en)).inserted else { return nil }
            return Word(en: en, ru: item.ru)
        }
        if !fresh.isEmpty { commit(words + fresh) }
        return fresh
    }

    func update(_ id: UUID, en: String, ru: String) {
        var w = words
        guard let i = w.firstIndex(where: { $0.id == id }) else { return }
        w[i].en = en; w[i].ru = ru
        commit(w)
    }

    func remove(_ ids: Set<UUID>) { commit(words.filter { !ids.contains($0.id) }) }
    func clear() { commit([]) }

    func setTranslations(_ map: [UUID: String]) {
        guard !map.isEmpty else { return }
        commit(words.map { var w = $0; if let t = map[w.id], w.ru.isEmpty { w.ru = t }; return w })
    }

    /// First-attempt results of a finished session, applied in one write.
    func record(_ results: [UUID: Bool]) {
        guard !results.isEmpty else { return }
        let now = Date()
        commit(words.map { w in
            guard let ok = results[w.id] else { return w }
            var w = w; w.lastSeen = now
            if ok { w.right += 1 } else { w.wrong += 1 }
            return w
        })
    }

    var due: [Word] {
        let limit = Date().addingTimeInterval(-20 * 3600)
        return words.filter { !$0.en.isEmpty && ($0.lastSeen ?? .distantPast) < limit }
    }

    /// Least recently seen first, then the most mistaken; shuffled so the order isn't predictable.
    func session(size: Int = 20) -> [Word] {
        let pool = words.filter { !$0.en.isEmpty }
        if Motion.tour { return Array(pool.prefix(3)) }
        let picked = pool.sorted { a, b in
            let da = a.lastSeen ?? .distantPast, db = b.lastSeen ?? .distantPast
            return da != db ? da < db : a.wrong > b.wrong
        }.prefix(size)
        return picked.shuffled()
    }

    /// Adds words, translates the new ones in parallel, then writes translations once. Returns how many failed.
    @discardableResult
    func addAndTranslate(_ ens: [String]) async -> (added: Int, failed: Int) {
        let fresh = add(ens.map { (en: $0, ru: "") })
        var map: [UUID: String] = [:]
        await withTaskGroup(of: (UUID, String?).self) { group in
            for w in fresh { group.addTask { (w.id, await Net.translate(w.en)) } }
            for await (id, t) in group { if let t { map[id] = t } }
        }
        setTranslations(map)
        return (fresh.count, fresh.count - map.count)
    }
}

/// Daily goal and streak. Changes once per finished session.
@Observable final class DayProgress {
    private(set) var today = 0
    private(set) var streak = 0
    @ObservationIgnored private let d = UserDefaults.standard

    init() {
        if Motion.tour { today = 12; streak = 5 } else { load() }
    }

    private static func key(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
    private var todayKey: String { Self.key(.now) }
    private var yesterdayKey: String { Self.key(Calendar.current.date(byAdding: .day, value: -1, to: .now)!) }

    func load() {
        if d.string(forKey: "day") != todayKey { d.set(todayKey, forKey: "day"); d.set(0, forKey: "todayCount") }
        today = d.integer(forKey: "todayCount")
        let last = d.string(forKey: "lastGoalDay")
        streak = (last == todayKey || last == yesterdayKey) ? d.integer(forKey: "streak") : 0
    }

    func add(_ n: Int, goal: Int) {
        guard !Motion.tour, n > 0 else { return }
        load()
        let before = today
        let now = today + n
        d.set(now, forKey: "todayCount")
        if before < goal && now >= goal {
            let last = d.string(forKey: "lastGoalDay")
            let s = last == yesterdayKey ? d.integer(forKey: "streak") + 1 : (last == todayKey ? d.integer(forKey: "streak") : 1)
            d.set(s, forKey: "streak"); d.set(todayKey, forKey: "lastGoalDay")
        }
        load()
    }
}

enum NGSL {
    /// 2 809 most useful English words, by frequency.
    static let words: [String] = {
        guard let url = Bundle.main.url(forResource: "ngsl", withExtension: "txt"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").map(String.init)
    }()
    static let levelCount = 7
    static var levelSize: Int { Int((Double(words.count) / Double(levelCount)).rounded(.up)) }
    static let levelNames = ["Основа", "Повседневное", "Уверенно", "Свободно", "Продвинутый", "Мастер", "Эксперт"]
    static func level(_ i: Int) -> ArraySlice<String> {
        let a = i * levelSize, b = min(words.count, a + levelSize)
        return a < b ? words[a..<b] : []
    }
    /// Skips the 400 most basic words.
    static func wordOfDay(_ date: Date = .now) -> String {
        guard words.count > 400 else { return "climate" }
        let day = Int((date.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: date))) / 86400)
        return words[400 + day % (words.count - 400)]
    }
}
