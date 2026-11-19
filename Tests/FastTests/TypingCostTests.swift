import Foundation
import Testing
@testable import Fast

// What a key typed into the address field costs: the history's guesses for
// every prefix of a few addresses and questions, over a history of 20,000
// places, and the calculator's reading of every prefix of 200 words. Timed
// and printed (YAB_TYPING=1 runs each many times over for steadier numbers),
// and the guesses held to what the plain way of making them gives.
//
// The suite runs side by side with every other in one process, and History
// lives on the main actor: these tests give the main actor back after every
// key, and the plain way, slow on purpose, works off it. Held in one piece
// (the plain way alone took the main thread for 17 s in a debug build),
// every WebKit reply to every page test waited behind it, and the N-Z
// shard's page tests failed around it (PasswordAutofillTests in the 0.0.30
// gate).
@MainActor
struct TypingCostTests {
    /// Sep 25 2026, noon in London.
    static let now = Date(timeIntervalSince1970: 1_790_334_000)

    /// A made-up history, the same every run: hosts of syllables, some
    /// pages under each, titles of words, counts and days since spread out.
    static let places: [Visit] = {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ n: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(n))
        }
        let parts = ["git", "hub", "news", "swift", "cloud", "ai", "doc", "mail", "shop", "code", "dev", "map", "play",
                     "pay", "net", "fig", "lin", "note", "tube", "gram", "book", "claude", "ycomb", "stack", "over", "flow",
                     "rice", "cook", "you", "go", "the", "app", "hi", "ka", "zo", "loc", "host", "web", "kit", "mo"]
        let ends = ["com", "org", "io", "app", "dev", "net", "co", "ai", "ru", "fr"]
        let words = ["how", "to", "cook", "rice", "swift", "concurrency", "design", "system", "figma", "news", "the", "a",
                     "guide", "best", "github", "pull", "request", "issue", "claude", "code", "review", "api", "docs",
                     "welcome", "home", "page", "search", "results", "map", "of", "paris", "tokyo", "time", "rates"]
        var out: [Visit] = []
        var hosts: [String] = []
        for _ in 0 ..< 2_500 {
            let host = (0 ..< 1 + next(3)).map { _ in parts[next(parts.count)] }.joined() + "." + ends[next(ends.count)]
            hosts.append(next(5) == 0 ? parts[next(parts.count)] + "." + host : host)
        }
        for host in Set(hosts).sorted() {
            out.append(Visit(url: "https://\(host)/", key: host, title: next(3) == 0 ? "" : words[next(words.count)].capitalized,
                             count: next(40), last: now.addingTimeInterval(-Double(next(200 * 86_400))),
                             typed: next(4) == 0 ? next(5) : nil))
        }
        while out.count < 20_000 {
            let host = hosts[next(hosts.count)]
            let path = (0 ..< 1 + next(3)).map { _ in words[next(words.count)] + (next(4) == 0 ? "\(next(900))" : "") }.joined(separator: "/")
            let title = (0 ..< 1 + next(7)).map { _ in words[next(words.count)] }.joined(separator: " ").capitalized
            out.append(Visit(url: "https://\(host)/\(path)", key: "\(host)/\(path)", title: next(10) == 0 ? "" : title,
                             count: next(12), last: now.addingTimeInterval(-Double(next(400 * 86_400))),
                             typed: next(10) == 0 ? next(3) : nil))
        }
        return out
    }()

    /// What gets typed into the field, a key at a time.
    static let typed = ["github.com/anthropics", "swift concurrency", "how to cook rice", "news.ycombinator.com",
                        "localhost:3000", "figma design system", "claude code review", "https://www.youtube.com",
                        "x", "go", "cloud", "hubkit", "tokyo time", "100 usd in eur"]

    static var keystrokes: [String] { typed.flatMap { words in (1 ... words.count).map { String(words.prefix($0)) } } }

    static var rounds: Int { ProcessInfo.processInfo.environment["YAB_TYPING"].map { Int($0) ?? 20 } ?? 1 }

    static func microseconds(_ took: Duration) -> Double {
        Double(took.components.attoseconds) / 1e12 + Double(took.components.seconds) * 1e6
    }

    /// One key's work timed alone, in microseconds, the main actor given
    /// back after it.
    static func timed(_ work: () -> Void) async -> Double {
        let start = ContinuousClock.now
        work()
        let took = microseconds(ContinuousClock.now - start)
        await Task.yield()
        return took
    }

    /// Every key once, untimed, the main actor given back after each.
    static func each(_ keys: [String], _ work: (String) -> Void) async {
        for key in keys {
            work(key)
            await Task.yield()
        }
    }

    /// How long a key costs, in microseconds, the median of the rounds: the
    /// keys' own times added up, not the time the main actor was away.
    static func time(_ label: String, keys: [String], _ work: (String) -> Void) async -> Double {
        var runs: [Double] = []
        for _ in 0 ..< rounds {
            var spent = 0.0
            for key in keys { spent += await timed { work(key) } }
            runs.append(spent)
        }
        let median = runs.sorted()[runs.count / 2] / Double(keys.count)
        print("typing cost: \(label): \(String(format: "%.1f", median)) µs a key over \(keys.count) keys")
        return median
    }

    @Test func historyGuessesAKeyAtATime() async {
        let history = History(Self.places)
        let keys = Self.keystrokes
        // Once to warm what is made lazily, titles cut into words.
        await Self.each(keys) { _ = history.suggestions(for: $0, limit: 5, now: Self.now) }
        _ = await Self.time("history, \(Self.places.count) places", keys: keys) {
            _ = history.suggestions(for: $0, limit: 5, now: Self.now)
        }
        // The dearest key, the first letter of a word most often: each key
        // timed alone, the least of the rounds for each.
        var dearest = [Double](repeating: .infinity, count: keys.count)
        for _ in 0 ..< Self.rounds {
            for (at, key) in keys.enumerated() {
                let took = await Self.timed { _ = history.suggestions(for: key, limit: 5, now: Self.now) }
                dearest[at] = min(dearest[at], took)
            }
        }
        if let worst = dearest.indices.max(by: { dearest[$0] < dearest[$1] }) {
            print("typing cost: history, dearest key \"\(keys[worst])\": \(String(format: "%.1f", dearest[worst])) µs")
        }
        // The field asks twice for one key (the list, then whether a clip
        // is one of its places): the second is the same answer.
        _ = await Self.time("history, asked twice a key", keys: keys) {
            _ = history.suggestions(for: $0, limit: 5, now: Self.now)
            _ = history.suggestions(for: $0, limit: 5, now: Self.now)
        }
    }

    @Test func historyGuessesAsThePlainWayMakesThem() async {
        // A quarter of the places, the plain way is slow; and some not in
        // plain ASCII, which are matched as they were.
        let t = Self.now
        let places = Array(Self.places.prefix(5_000)) + [
            Visit(url: "https://παράδειγμα.δοκιμή/", key: "παράδειγμα.δοκιμή", title: "Παράδειγμα", count: 4, last: t),
            Visit(url: "https://example.gr/el/articles/1", key: "example.gr/el/articles/1", title: "Πώς να μαγειρέψεις ρύζι", count: 2, last: t),
            Visit(url: "https://café.fr/", key: "café.fr", title: "Café de Flore", count: 3, last: t),
            Visit(url: "https://xn--caf-dma.fr/menu", key: "xn--caf-dma.fr/menu", title: "Menu du café", count: 1, last: t),
        ]
        let history = History(places)
        let keys = Self.keystrokes + ["", " ", "www.", "https://git", "GitHub", "rice cook", "a b c", "hub", "ycomb.co",
                                      "παρ", "παράδειγμα", "πώς παρ", "κak", "caf", "café", "cafe", "afé", "menu caf"]
        // Typed, then taken back, then typed differently.
        let back = ["githu", "git", "gi", "gin", "g", "", "swi", "swift c", "swift", "swift co"]
        // Every place scored for every key: off the main actor.
        let plain = Plain(places, known: History.known), now = Self.now
        let slow = await Task.detached(priority: .userInitiated) {
            (keys.map { (plain.suggestions(for: $0, limit: 5, now: now).map(\.key),
                         plain.suggestions(for: $0, limit: 40, now: now).map(\.key)) },
             back.map { plain.suggestions(for: $0, limit: 5, now: now).map(\.key) })
        }.value
        for (key, want) in zip(keys, slow.0) {
            #expect(history.suggestions(for: key, limit: 5, now: Self.now).map(\.key) == want.0, "\(key)")
            #expect(history.suggestions(for: key, limit: 40, now: Self.now).map(\.key) == want.1, "\(key)")
            await Task.yield()
        }
        for (key, want) in zip(back, slow.1) {
            #expect(history.suggestions(for: key, limit: 5, now: Self.now).map(\.key) == want, "\(key)")
        }
    }

    /// Three thousand bookmarks over the same history: a third at places
    /// been to, the rest never visited, in folders.
    @Test func historyWithBookmarksGuessesAKeyAtATime() async {
        let history = History(Self.places)
        let plainKeys = Self.keystrokes
        let bare = await Self.time("history, no bookmarks", keys: plainKeys) {
            _ = history.suggestions(for: $0, limit: 5, now: Self.now)
        }
        var sites: [Bookmark] = []
        for at in 0 ..< 3_000 {
            let place = Self.places[(at * 7) % Self.places.count]
            let url = at % 3 == 0 ? place.url : "https://mark\(at).example.org/page/\(at)"
            sites.append(.site(at % 3 == 0 ? place.title : "Saved Page \(at) Guide", URL(string: url)!))
        }
        let folders = stride(from: 0, to: sites.count, by: 100).map { Bookmark.folder("F\($0)", Array(sites[$0 ..< min($0 + 100, sites.count)])) }
        history.keep(bookmarks: folders, revision: 1)
        await Self.each(plainKeys) { _ = history.suggestions(for: $0, limit: 5, now: Self.now) }
        let marked = await Self.time("history, 3,000 bookmarks", keys: plainKeys) {
            history.keep(bookmarks: folders, revision: 1)
            _ = history.suggestions(for: $0, limit: 5, now: Self.now)
        }
        print("typing cost: bookmarks add \(String(format: "%.1f", marked - bare)) µs a key")
        // Where it goes: the bookmarks alone, never visited, and all visited.
        let alone = History([])
        alone.keep(bookmarks: folders, revision: 1)
        _ = await Self.time("bookmarks alone, 3,000", keys: plainKeys) {
            _ = alone.suggestions(for: $0, limit: 5, now: Self.now)
        }
        let visitedOnly = History(Self.places)
        let seenSites = (0 ..< 3_000).map { at -> Bookmark in
            let place = Self.places[(at * 7) % Self.places.count]
            return .site(place.title, URL(string: place.url)!)
        }
        visitedOnly.keep(bookmarks: seenSites, revision: 1)
        await Self.each(plainKeys) { _ = visitedOnly.suggestions(for: $0, limit: 5, now: Self.now) }
        _ = await Self.time("history, 3,000 visited bookmarks", keys: plainKeys) {
            _ = visitedOnly.suggestions(for: $0, limit: 5, now: Self.now)
        }
        #expect(history.suggestions(for: "mark12", limit: 5, now: Self.now).first?.bookmarked == true)
        #expect(history.suggestions(for: "saved page 7", limit: 5, now: Self.now).allSatisfy { $0.bookmarked })
    }

    @Test func historyGuessesFollowWhatIsRecorded() {
        let history = History(Array(Self.places.prefix(500)))
        let before = history.suggestions(for: "zzq", limit: 5, now: Self.now)
        #expect(before.isEmpty)
        history.take(URL(string: "https://zzqtop.com/")!, title: "Zzq", count: 3, last: Self.now)
        #expect(history.suggestions(for: "zzq", limit: 5, now: Self.now).map(\.key) == ["zzqtop.com"])
        history.retitle(URL(string: "https://zzqtop.com/")!, "Other")
        #expect(history.suggestions(for: "zzqt", limit: 5, now: Self.now).first?.title == "Other")
    }

    @Test func calculatorReadsAKeyAtATime() async {
        var words = ["github", "how to cook rice", "news.ycombinator.com", "swift concurrency", "figma", "localhost:3000",
                     "the best pizza in paris", "claude code", "apple.com/macbook-pro", "weather tomorrow",
                     "2400*12", "20% of 80", "5 km to mi", "100 usd in eur", "time in tokyo", "days until christmas",
                     "in 3 weeks", "3pm london in sf", "255 in hex", "what time is it in paris", "100 dollars in rubles", "tokyo time"]
        let filler = ["what is", "best", "cheap", "flights to", "recipe for", "youtube", "reddit", "wiki", "amazon",
                      "translate", "define", "stack overflow", "gmail", "maps", "linear", "notion", "vercel", "docs"]
        var i = 0
        while words.count < 200 {
            words.append(filler[i % filler.count] + (i % 3 == 0 ? "" : " " + filler[(i * 7) % filler.count]))
            i += 1
        }
        let keys = words.flatMap { word in (1 ... word.count).map { String(word.prefix($0)) } }
        let rates = CalcTests.rates
        _ = await Self.time("calculator, \(words.count) words", keys: keys) {
            _ = Calc.answer($0, now: Self.now, rates: rates)
        }
        let plain = words.filter { $0.allSatisfy { !$0.isNumber } }.flatMap { word in (1 ... word.count).map { String(word.prefix($0)) } }
        _ = await Self.time("calculator, words with no digit", keys: plain) {
            _ = Calc.answer($0, now: Self.now, rates: rates)
        }
    }
}

/// The history's guesses made the plain way, every place scored for every
/// key, as they were before they were made cheaper: what the cheap way has
/// to give, row for row. Made on the main actor, asked off it.
private struct Plain {
    let visits: [String: Visit]
    let known: [(String, String)]
    init(_ list: [Visit], known: [(String, String)]) {
        visits = Dictionary(list.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        self.known = known
    }

    func suggestions(for typed: String, limit: Int, now: Date) -> [Suggestion] {
        var needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        for scheme in ["https://", "http://"] where needle.hasPrefix(scheme) { needle = String(needle.dropFirst(scheme.count)) }
        if needle.hasPrefix("www.") { needle = String(needle.dropFirst(4)) }
        guard !needle.isEmpty else { return [] }
        func rank(_ key: String) -> Double? {
            if key.hasPrefix(needle) { return 6 }
            let host = key.split(separator: "/").first.map(String.init) ?? key
            if let dot = host.range(of: "."), host[dot.upperBound...].hasPrefix(needle) { return 3 }
            if needle.count >= 2, host.contains(needle) { return 2 }
            return nil
        }
        let words = needle.count >= 3 ? needle.split(whereSeparator: \.isWhitespace).map { " " + $0 } : []
        func titled(_ visit: Visit) -> Double? {
            // The title's words, then the path's (History.pathWords).
            let all = Wording.split(visit.title.lowercased()) + History.pathWords(visit.key)
            guard !words.isEmpty, !all.isEmpty else { return nil }
            let title = " " + all.joined(separator: " ")
            return words.allSatisfy { title.contains($0) } ? 1 : nil
        }
        func frecency(_ visit: Visit) -> Double {
            let days = max(0, now.timeIntervalSince(visit.last) / 86_400)
            return Double(visit.count + 2 * (visit.typed ?? 0)) * exp(-days / 30)
        }
        var scored: [(Suggestion, Double)] = []
        for visit in visits.values {
            guard let rank = rank(visit.key) ?? titled(visit), let url = URL(string: visit.url) else { continue }
            scored.append((Suggestion(key: visit.key, title: visit.title, url: url, kind: .visited),
                           rank + 4 + frecency(visit) + (visit.key.contains("/") ? 0 : 1.5)))
        }
        for known in known where visits[known.0] == nil {
            guard let rank = rank(known.0) ?? (known.1.lowercased().hasPrefix(needle) ? 2 : nil),
                  let url = URL(string: "https://" + known.0) else { continue }
            scored.append((Suggestion(key: known.0, title: known.1, url: url, kind: .known), rank))
        }
        // As it was, and then by the address when even its length is the
        // same, where before it fell to the order of a dictionary.
        return scored.sorted {
            $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.key.count != $1.0.key.count ? $0.0.key.count < $1.0.key.count : $0.0.key < $1.0.key
        }.prefix(limit).map(\.0)
    }
}
