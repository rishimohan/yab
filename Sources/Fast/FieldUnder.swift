import Foundation

/// What the field offers for the words, Settings › Field: the rows always
/// there and their order, what Return takes, whether ⇥ asks, and which
/// matches the field looks for. The search stays: without it the engine's
/// suggestions go and Return has nowhere to go.
@MainActor
final class FieldUnder: ObservableObject {
    static let shared = FieldUnder()

    /// A row under the words: the search, Ask, the task, one of Yab's own
    /// places searched for the words ("place:mail"), or a site searched
    /// for them ("site:youtube.com").
    static let search = "search", ask = "ask", task = "task"
    static let standard = [search, ask, task]
    /// Yab's places a row can search: Mail, Files and History.
    static let places: [FieldPlace] = [.mail, .downloads, .history]
    static func site(_ scope: Scope) -> String { "site:" + scope.id }
    static func scope(_ row: String) -> Scope? {
        guard row.hasPrefix("site:") else { return nil }
        let id = row.dropFirst(5)
        return Scopes.all.first { $0.id == id }
    }
    static func place(_ place: FieldPlace) -> String { "place:" + place.rawValue }
    static func place(_ row: String) -> FieldPlace? {
        row.hasPrefix("place:") ? FieldPlace(rawValue: String(row.dropFirst(6))) : nil
    }
    /// Mail's row only once an account is there to search.
    static func offered(_ place: FieldPlace) -> Bool { place != .mail || MailCenter.shared.connected }

    /// The row of the field's list a row under the words is.
    static func row(of offer: Suggestion) -> String? {
        switch offer.kind {
        case .search: return search
        case .ask: return ask
        case .task: return task
        case .site(let id): return "site:" + id
        case .within(let place): return Self.place(place)
        default: return nil
        }
    }

    private enum Key {
        static let rows = "field.under", off = "field.under.off", firstRow = "field.firstRow", tabAsks = "field.tabAsks"
        static let tabs = "field.match.tabs", pins = "field.match.pins", pages = "field.match.pages", commands = "field.match.commands"
    }

    @Published var rows: [String] { didSet { Store.settings.set(rows, forKey: Key.rows) } }
    /// Ask or Task turned off, keeping their place in the order.
    @Published private(set) var off: Set<String> { didSet { Store.settings.set(off.sorted(), forKey: Key.off) } }
    /// Return takes the top row under the words, rather than the one the
    /// words read as (a verb the task, a question Ask).
    @Published var firstRow: Bool { didSet { Store.settings.set(firstRow, forKey: Key.firstRow) } }
    /// ⇥ sends plain words to Ask, whatever leads (Browser.tabAsks).
    @Published var tabAsks: Bool { didSet { Store.settings.set(tabAsks, forKey: Key.tabAsks) } }
    /// The matches the field looks for as you type.
    @Published var tabs: Bool { didSet { Store.settings.set(tabs, forKey: Key.tabs) } }
    /// Pinned and kept tabs, apart from the other open tabs: the words then
    /// find the pages you are in now without the ones you keep (#877).
    @Published var pins: Bool { didSet { Store.settings.set(pins, forKey: Key.pins) } }
    @Published var pages: Bool { didSet { Store.settings.set(pages, forKey: Key.pages) } }
    @Published var commands: Bool { didSet { Store.settings.set(commands, forKey: Key.commands) } }

    private init() {
        let store = Store.settings
        var rows = store.stringArray(forKey: Key.rows) ?? Self.standard
        var off = Set(store.stringArray(forKey: Key.off) ?? [])
        // Taken away before they had switches: back, and off. The search
        // comes back on.
        for row in Self.standard where !rows.contains(row) {
            if row == Self.search { rows.insert(row, at: 0) } else { rows.append(row); off.insert(row) }
        }
        off.remove(Self.search)
        self.rows = rows
        self.off = off
        firstRow = store.bool(forKey: Key.firstRow)
        tabAsks = store.object(forKey: Key.tabAsks) as? Bool ?? true
        tabs = store.object(forKey: Key.tabs) as? Bool ?? true
        // Open Tabs used to answer for pins too: off there, they stay off.
        pins = store.object(forKey: Key.pins) as? Bool ?? tabs
        pages = store.object(forKey: Key.pages) as? Bool ?? true
        commands = store.object(forKey: Key.commands) as? Bool ?? true
    }

    func add(_ row: String) { if !rows.contains(row) { rows.append(row) } }

    /// What was added goes. Search, Ask and Task stay: Ask and Task turn off.
    func remove(_ row: String) { if !Self.standard.contains(row) { rows.removeAll { $0 == row } } }

    func set(_ row: String, on: Bool) {
        guard row != Self.search else { return }
        if on { off.remove(row) } else { off.insert(row) }
    }

    func move(_ row: String, before other: String?) {
        guard row != other, let from = rows.firstIndex(of: row) else { return }
        var next = rows
        next.remove(at: from)
        next.insert(row, at: other.flatMap { next.firstIndex(of: $0) } ?? next.endIndex)
        rows = next
    }

    /// Whether a match of this kind is looked for.
    func wants(_ offer: Suggestion) -> Bool {
        if offer.opensHere || offer.tab != nil || offer.kind == .open { return offer.pinned ? pins : tabs }
        if offer.menuTargetID != nil { return commands }
        switch offer.kind {
        case .visited: return pages
        case .command, .setting, .place: return commands
        default: return true
        }
    }
}

extension Browser {
    /// The rows under the words, in Settings › Field's order: the search
    /// row the list already holds, the agent's, and each site searched for
    /// the words. With nothing of them left (no agent, a site gone), the
    /// search.
    func underRows(_ search: Suggestion, words: String) -> [Suggestion] {
        let agent = agentRows()
        let under = FieldUnder.shared
        let rows = under.rows.compactMap { row -> Suggestion? in
            guard !under.off.contains(row) else { return nil }
            switch row {
            case FieldUnder.search: return search
            case FieldUnder.ask: return agent.first { $0.kind == .ask }
            case FieldUnder.task: return agent.first { $0.kind == .task }
            default:
                if let place = FieldUnder.place(row) {
                    guard FieldUnder.offered(place) else { return nil }
                    return Suggestion(key: search.key, title: place.title, url: nil, kind: .within(place))
                }
                guard let scope = FieldUnder.scope(row), Scopes.isOn(scope), let url = scope.url(for: words) else { return nil }
                return Suggestion(key: search.key, title: scope.name, url: url, kind: .site(scope.id))
            }
        }
        return rows.isEmpty ? [search] : rows
    }
}

extension Browser {
    /// ⌘K on a row under the words: its place among them, changed from
    /// the field, and the way to Settings › Field.
    func fallbackActions(_ offer: Suggestion) -> [FieldAction] {
        let under = FieldUnder.shared
        guard let row = FieldUnder.row(of: offer), let at = under.rows.firstIndex(of: row) else { return [] }
        // The list read again, the row in its new place.
        let moved = { [weak self] in
            guard let self else { return }
            self.typed = self.typed
        }
        var out: [FieldAction] = []
        if at > 0 {
            out.append(FieldAction(id: "fallbackTop", title: "Move to Top", symbol: "yab.tabs.up", group: 3) {
                under.move(row, before: under.rows.first)
                moved()
            })
            out.append(FieldAction(id: "fallbackUp", title: "Move Up", symbol: "chevron.up", group: 3) {
                under.move(row, before: under.rows[at - 1])
                moved()
            })
        }
        if at < under.rows.count - 1 {
            out.append(FieldAction(id: "fallbackDown", title: "Move Down", symbol: "chevron.down", group: 3) {
                let after = at + 2
                under.move(row, before: under.rows.indices.contains(after) ? under.rows[after] : nil)
                moved()
            })
        }
        if row != FieldUnder.search {
            let standard = FieldUnder.standard.contains(row)
            out.append(FieldAction(id: "fallbackRemove", title: standard ? "Turn Off in Field" : "Remove from Field", symbol: "minus", group: 3, danger: true) {
                if standard { under.set(row, on: false) } else { under.remove(row) }
                moved()
            })
        }
        // Ask and Task: all the AI rows put away at once, ⇥ with them
        // (AIUse.rowsKey), or AI itself, at its switch in Settings › AI.
        let ai = row == FieldUnder.ask || row == FieldUnder.task
        if ai {
            out.append(FieldAction(id: "fallbackHideAI", title: "Hide AI Rows", symbol: "yab.sparkles.minus", group: 4) { [weak self] in
                self?.hideAIRows(true)
                moved()
            })
            out.append(FieldAction(id: "fallbackAIOff", title: "Turn Off AI…", symbol: "yab.sparkles.slash", group: 4) { [weak self] in
                self?.openAISwitch()
            })
        }
        out.append(FieldAction(id: "fallbackSettings", title: "While You Type Settings…", symbol: "gearshape", group: ai ? 5 : 3) { [weak self] in
            guard let self else { return }
            self.close()
            SettingsWindow.shared.show(.search, for: self)
        })
        return out
    }
}
