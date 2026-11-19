import Foundation
import Testing
@testable import Fast

/// A word of an address's path found nothing unless the page's title held
/// it too: "workflows" missed localhost/workspace/pika/workflows. Arc finds
/// a page by a word of its path ("appearance" finds the page at
/// localhost:4000/dashboard/appearance, titled Dashboard). The path's words now match
/// as a title's do: each word typed begins one, under any match on the
/// address's start.
@MainActor struct HistoryPathWordsTests {
    private let now = Date()

    private func visit(_ url: String, title: String, count: Int = 5) -> Visit {
        let key = History.key(for: URL(string: url)!)
        return Visit(url: url, key: key, title: title, count: count, last: now, typed: nil)
    }

    @Test func aWordOfThePathFindsThePage() {
        let history = History([
            visit("http://localhost:3000/workspace/pika/workflows", title: "Orshot"),
            visit("https://example.com/", title: "Example"),
        ])
        #expect(history.suggestions(for: "workflows", now: now).map(\.key) == ["localhost/workspace/pika/workflows"])
        #expect(history.suggestions(for: "workf", now: now).map(\.key) == ["localhost/workspace/pika/workflows"])
        // Every word typed, from the title or the path.
        #expect(history.suggestions(for: "pika work", now: now).map(\.key) == ["localhost/workspace/pika/workflows"])
        #expect(history.suggestions(for: "orshot workflows", now: now).map(\.key) == ["localhost/workspace/pika/workflows"])
        #expect(history.suggestions(for: "pika billing", now: now).isEmpty)
    }

    /// Only a word's start, as for a title: "log" doesn't find /blog.
    @Test func notTheMiddleOfAWord() {
        let history = History([visit("https://site.example/blog/launch", title: "Launch")])
        #expect(history.suggestions(for: "log", now: now).isEmpty)
        #expect(history.suggestions(for: "blog", now: now).map(\.key) == ["site.example/blog/launch"])
    }

    /// A page with no title is found by its path too.
    @Test func anUntitledPageByItsPath() {
        let history = History([visit("http://localhost:4000/dashboard/appearance", title: "")])
        #expect(history.suggestions(for: "appearance", now: now).map(\.key) == ["localhost/dashboard/appearance"])
    }

    /// A site whose address begins with the words is still the one the
    /// field finishes, Return's row, however often a page whose path holds
    /// them was seen.
    @Test func theAddressStartIsStillFinished() {
        let history = History([
            visit("https://studio.example/", title: "Studio", count: 2),
            visit("https://other.example/studio/upload", title: "Upload", count: 50),
        ])
        let rows = history.suggestions(for: "studio", now: now)
        #expect(Set(rows.map(\.key)) == ["studio.example", "other.example/studio/upload"])
        #expect(history.completion(for: "studio", among: rows) == ".example")
    }

    /// More pages with the words in their paths than rows to show, each
    /// seen far more often: the site whose address begins with them is
    /// still among the rows, and still the one the field finishes.
    @Test func busyPathPagesDontPushOutTheAddressStart() {
        var places = [visit("https://studio.example/", title: "Studio", count: 2)]
        for page in ["upload", "library", "analytics", "comments", "settings", "earnings"] {
            places.append(visit("https://other.example/studio/" + page, title: page.capitalized, count: 50))
        }
        let history = History(places)
        let rows = history.suggestions(for: "studio", now: now)
        #expect(rows.count == 5)
        #expect(rows.contains { $0.key == "studio.example" })
        #expect(history.completion(for: "studio", among: rows) == ".example")
    }

    /// A word written with escapes in the address is found as typed.
    @Test func anEscapedWordIsFoundAsTyped() {
        let history = History([visit("https://site.example/caf%C3%A9/menu", title: "Menu")])
        #expect(history.suggestions(for: "café", now: now).map(\.key) == ["site.example/caf%c3%a9/menu"])
        #expect(History.pathWords("site.example/caf%c3%a9/menu").map(String.init) == ["café", "menu"])
    }

    /// Ids aren't words: a long one, or one more digits than letters.
    @Test func idsAreNotWords() {
        #expect(History.pathWords("studio.youtube.com/channel/ucsyuezv9hlfufyopbtnqefg/videos").map(String.init)
            == ["channel", "videos"])
        #expect(History.pathWords("x.com/oddhash/status/2114815296892473772").map(String.init) == ["oddhash", "status"])
        #expect(History.pathWords("github.com/a1b2c3d4/v2").isEmpty)
        #expect(History.pathWords("example.com").isEmpty)
    }
}
