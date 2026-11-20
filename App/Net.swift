import Foundation

struct Example: Hashable { let en: String; let ru: String }
struct Meaning: Hashable { let pos: String; let def: String }
struct DictEntry { var phonetic = ""; var audio: URL?; var meanings: [Meaning] = [] }
struct Episode: Identifiable, Hashable { let id: String; let title: String; let summary: String; let date: Date?; let audio: URL }

/// Free sources, no keys. Every call fails soft (nil / empty) so the UI just shows less.
enum Net {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 12
        return URLSession(configuration: c)
    }()

    static func data(_ url: URL) async throws -> Data {
        let (d, r) = try await session.data(from: url)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return d
    }
    static func json(_ url: URL) async throws -> Any { try JSONSerialization.jsonObject(with: try await data(url)) }

    static func url(_ base: String, _ q: [(String, String)]) -> URL {
        var c = URLComponents(string: base)!
        c.queryItems = q.map { URLQueryItem(name: $0.0, value: $0.1) }
        return c.url!
    }

    // MARK: Translation: web translator (better for single words), second service as fallback.
    static func translate(_ w: String) async -> String? {
        if Motion.tour, let s = Word.samples.first(where: { $0.en == w }) { return s.ru }
        let g = url("https://translate.googleapis.com/translate_a/single",
                    [("client", "gtx"), ("sl", "en"), ("tl", "ru"), ("dt", "t"), ("dt", "bd"), ("q", w)])
        if let j = try? await json(g) as? [Any] {
            var opts: [String] = []
            if let first = (j.first as? [Any])?.first as? [Any], let s = first.first as? String { opts.append(s.lowercased()) }
            if j.count > 1, let groups = j[1] as? [Any] {
                for p in groups { if let p = p as? [Any], p.count > 1, let terms = p[1] as? [String], let t = terms.first { opts.append(t.lowercased()) } }
            }
            var seen = Set<String>()
            let unique = opts.filter { !$0.isEmpty && seen.insert($0).inserted }
            if !unique.isEmpty { return unique.prefix(2).joined(separator: ", ") }
        }
        let m = url("https://api.mymemory.translated.net/get", [("langpair", "en|ru"), ("q", w)])
        if let j = try? await json(m) as? [String: Any], (j["responseStatus"] as? Int) == 200,
           let t = (j["responseData"] as? [String: Any])?["translatedText"] as? String, !t.isEmpty { return t }
        return nil
    }

    // MARK: Example sentences with Russian translations
    static func examples(_ w: String, limit: Int = 2) async -> [Example] {
        let u = url("https://api.tatoeba.org/unstable/sentences",
                    [("lang", "eng"), ("trans:lang", "rus"), ("sort", "relevance"), ("limit", "10"), ("q", w)])
        guard let j = try? await json(u) as? [String: Any], let data = j["data"] as? [[String: Any]] else { return [] }
        func flat(_ a: Any?) -> [[String: Any]] {
            if let d = a as? [String: Any] { return [d] }
            if let arr = a as? [Any] { return arr.flatMap { flat($0) } }
            return []
        }
        let list = data.compactMap { s -> Example? in
            guard let en = s["text"] as? String, en.count < 90,
                  let ru = flat(s["translations"]).first(where: { ($0["lang"] as? String) == "rus" })?["text"] as? String else { return nil }
            return Example(en: en, ru: ru)
        }
        return Array(list.prefix(limit))
    }

    // MARK: Dictionary (phonetics, audio, meanings)
    static func dictionary(_ w: String) async -> DictEntry? {
        guard let u = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/" + (w.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? w)),
              let arr = try? await json(u) as? [[String: Any]], let e = arr.first else { return nil }
        var d = DictEntry()
        let phon = e["phonetics"] as? [[String: Any]] ?? []
        d.phonetic = (e["phonetic"] as? String) ?? phon.compactMap { $0["text"] as? String }.first ?? ""
        d.audio = phon.compactMap { $0["audio"] as? String }.first { !$0.isEmpty }.flatMap(URL.init(string:))
        let ru = ["noun": "сущ.", "verb": "глаг.", "adjective": "прил.", "adverb": "нареч."]
        d.meanings = (e["meanings"] as? [[String: Any]] ?? []).prefix(3).compactMap { m in
            guard let pos = m["partOfSpeech"] as? String,
                  let def = (m["definitions"] as? [[String: Any]])?.first?["definition"] as? String else { return nil }
            return Meaning(pos: ru[pos] ?? pos, def: def)
        }
        return d
    }

    // MARK: Weekly 6-minute podcast (RSS)
    static func episodes() async -> [Episode] {
        guard let d = try? await data(URL(string: "https://podcasts.files.bbci.co.uk/p02pc9tn.rss")!) else { return [] }
        let p = RSS(); let x = XMLParser(data: d); x.delegate = p; x.parse()
        return Array(p.items.prefix(8))
    }
}

private final class RSS: NSObject, XMLParserDelegate {
    var items: [Episode] = []
    private var cur: [String: String]?
    private var text = ""
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"; return f
    }()

    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        if e == "item" { cur = [:] }
        if e == "enclosure", let u = a["url"] { cur?["audio"] = u }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ p: XMLParser, foundCDATA b: Data) { text += String(decoding: b, as: UTF8.self) }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        guard var c = cur else { return }
        switch e {
        case "title", "description", "pubDate", "guid": if c[e] == nil { c[e] = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        case "item":
            // Feed links use plain http; iOS requires https.
            let raw = (c["audio"] ?? "").replacingOccurrences(of: "/proto/http/", with: "/proto/https/")
                .replacingOccurrences(of: "http://", with: "https://")
            if let audio = URL(string: raw), let title = c["title"] {
                let summary = (c["description"] ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(Episode(id: c["guid"] ?? raw, title: title, summary: summary,
                                     date: Self.df.date(from: c["pubDate"] ?? ""), audio: audio))
            }
            cur = nil; return
        default: break
        }
        cur = c
    }
}
