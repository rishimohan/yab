import AppKit
import Testing
@testable import Fast

/// #877: Settings › Field looks for pinned and kept tabs apart from the
/// other open tabs, so each, and History, can be left out on its own.
@MainActor @Suite(.serialized)
struct FieldPinnedMatchTests {
    private func withBrowser(_ body: (Browser, _ kept: Tab, _ open: Tab) throws -> Void) rethrows {
        _ = NSApplication.shared
        let browser = Browser(windowID: UUID())
        let kept = Tab(later: .nonPersistent())
        kept.restore(url: URL(string: "https://fonts.pinned877.test/specimen/Space+Grotesk")!, title: "Space Grotesk pinned877")
        kept.kept = true
        let open = Tab(later: .nonPersistent())
        open.restore(url: URL(string: "https://docs.pinned877.test/")!, title: "Docs pinned877")
        browser.lay([kept, open])
        browser.activeID = nil
        let suggest = browser.prefs.searchSuggest, requests = browser.prefs.fieldRequests
        let under = FieldUnder.shared
        let matches = (under.tabs, under.pins, under.pages)
        browser.prefs.searchSuggest = false
        browser.prefs.fieldRequests = false
        under.tabs = true; under.pins = true; under.pages = true
        browser.history = History([Visit(url: "https://history.pinned877.test/", key: "history.pinned877.test",
                                         title: "History pinned877", count: 5, last: Date(), typed: 1)])
        browser.openFresh()
        defer {
            kept.close(); open.close(); browser.dismiss(); browser.letGo()
            browser.dozing?.invalidate(); browser.stuck.timer?.invalidate(); browser.pressure?.cancel()
            browser.prefs.searchSuggest = suggest
            browser.prefs.fieldRequests = requests
            under.tabs = matches.0; under.pins = matches.1; under.pages = matches.2
            if let id = browser.windowID {
                try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json"))
            }
        }
        try body(browser, kept, open)
    }

    private func found(_ browser: Browser, kept: Tab, open: Tab) -> (kept: Bool, open: Bool, history: Bool) {
        browser.replaceTyped("pinned877")
        let offers = browser.offers
        return (offers.contains { $0.tab == kept.id },
                offers.contains { $0.tab == open.id },
                offers.contains { $0.tab == nil && $0.url?.host() == "history.pinned877.test" })
    }

    @Test func openPagesMarkPinnedAndKeptTabs() {
        withBrowser { browser, kept, open in
            let rows = browser.openPages(matching: "pinned877")
            #expect(rows.first { $0.tab == kept.id }?.pinned == true)
            #expect(rows.first { $0.tab == open.id }?.pinned == false)
        }
    }

    @Test(arguments: [(true, true, true), (false, true, true), (true, false, true), (true, true, false), (false, false, true)])
    func eachMatchTurnsOffOnItsOwn(pins: Bool, tabs: Bool, pages: Bool) {
        withBrowser { browser, kept, open in
            let under = FieldUnder.shared
            under.pins = pins; under.tabs = tabs; under.pages = pages
            let shown = found(browser, kept: kept, open: open)
            #expect(shown.kept == pins)
            #expect(shown.open == tabs)
            #expect(shown.history == pages)
        }
    }
}
