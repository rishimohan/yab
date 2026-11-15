import SwiftUI

/// Settings › Field's While You Type, in the field's own order: the rows
/// always there for the words, then what the words match, then what Return
/// and ⇥ do. Under the pointer a row shows its grip where its mark was and
/// is dragged to its place. The search has no switch, Ask and Task do, and
/// what Add Command added has a minus at its end. Its list is the settings'
/// own (DropPopup), a search on top: Yab's places, then the sites.
struct FieldUnderSettings: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject private var under = FieldUnder.shared
    @State private var hovered: String?
    @State private var anchor = DropAnchor.Place()
    @State private var listing = false

    var body: some View {
        Section {
            ForEach(under.rows, id: \.self) { row in
                line(row)
                    .draggable(row)
                    .dropDestination(for: String.self) { dropped, _ in
                        guard let moved = dropped.first, moved != row,
                              let from = under.rows.firstIndex(of: moved), let to = under.rows.firstIndex(of: row) else { return false }
                        // Down the list it lands under the row, up it over.
                        let after = from < to ? under.rows.index(after: to) : to
                        under.move(moved, before: under.rows.indices.contains(after) ? under.rows[after] : nil)
                        return true
                    }
            }
            add
        } header: {
            Text("While You Type")
                .settingsAnchor("field-fallbacks")
        }
        Section {
            matches("Pinned and Kept Tabs", "pin", $under.pins)
            matches("Open Tabs", "browser.tabs", $under.tabs)
            matches("History and Bookmarks", "clock", $under.pages)
            if prefs.engine != .custom {
                matches(SettingsWords.format("%@ Suggestions", [prefs.engine.title]), "magnifyingglass", $prefs.searchSuggest)
                    .settingsAnchor("search-suggest")
            }
            matches("Commands and Settings", "command", $under.commands)
        } header: {
            Text("Matches")
        }
        Section {
            matches("Guess from Your Words", "wand.and.stars", Binding(get: { !under.firstRow }, set: { under.firstRow = !$0 }))
                .settingsAnchor("field-return")
            // ⇥ asks, so with Ask off it has nothing to do.
            matches("Tab Asks ⇥", "arrow.right.to.line", $under.tabAsks, off: under.off.contains(FieldUnder.ask))
                .settingsAnchor("field-tab-asks")
        } header: {
            Text("Keys")
        }
    }

    private func matches(_ title: String, _ symbol: String, _ on: Binding<Bool>, off: Bool = false) -> some View {
        FieldLine(title, off: off, mark: { FieldLineMark(symbol: symbol) }, status: { EmptyView() }, end: { FieldSwitch(title, isOn: on) })
    }

    private var add: some View {
        FieldAddLine("Add Command", press: openList)
            .overlay(DropAnchor(place: anchor, title: "Add Command", press: openList, hover: { _ in }))
    }

    /// What can be added, in the list's order: Yab's places, then every
    /// site but the one the search already is.
    private var addable: [String] {
        let places = FieldUnder.places.filter(FieldUnder.offered).map(FieldUnder.place).filter { !under.rows.contains($0) }
        let sites = Scopes.on.filter { $0.home != nil && $0.name != prefs.engine.title }.map(FieldUnder.site).filter { !under.rows.contains($0) }
        return places + sites
    }

    private func openList() {
        guard !listing, let view = anchor.view, view.window != nil else { return }
        let rows = addable
        guard !rows.isEmpty else { return }
        let firstSite = rows.firstIndex { FieldUnder.scope($0) != nil }
        let list = DropList(options: rows.map { DropList.Line(title: name($0), picture: picture($0)) },
                            chosen: 0, divideBefore: firstSite == 0 ? nil : firstSite, inset: DropFace.inset)
        listing = true
        DropPopup.show(list, under: view, trailing: true) { index in
            listing = false
            if let index, rows.indices.contains(index) { under.add(rows[index]) }
        }
    }

    /// A row's mark in the list, at the list's 16 points: a site's icon,
    /// or the line drawing a template takes the words' ink in.
    private func picture(_ row: String) -> NSImage? {
        if let scope = FieldUnder.scope(row) {
            guard let icon = scope.icon else { return nil }
            return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                icon.draw(in: rect)
                return true
            }
        }
        return Glyphs.image(FieldUnder.place(row)?.symbol ?? "magnifyingglass", side: 16)
    }

    /// Ask and Task while the field doesn't show them: Hide AI Rows in
    /// Field, or AI in Yab at When Asked or Off (AIUse).
    private func away(_ row: String) -> Bool {
        (row == FieldUnder.ask || row == FieldUnder.task)
            && !AIUse.allows(.field, level: prefs.aiUse, rowsHidden: prefs.aiRowsHidden)
    }

    private func line(_ row: String) -> some View {
        let over = hovered == row
        let away = away(row)
        let standard = FieldUnder.standard.contains(row)
        let off = under.off.contains(row)
        return FieldLine(name(row), detail: !away ? "" : prefs.aiUse == .on ? "Hidden from Field" : "Off in Settings › AI",
                         off: away || off, mark: {
            FieldGripMark(over: over) { mark(row) }
        }, status: { EmptyView() }, end: {
            if !standard {
                FieldLineRemove(shown: over, label: "Remove \(name(row))") { under.remove(row) }
            } else if row != FieldUnder.search {
                FieldSwitch(name(row), isOn: Binding(get: { !under.off.contains(row) }, set: { under.set(row, on: $0) }))
                    .disabled(away)
            }
        })
        .contentShape(Rectangle())
        .settingsRowHover { hovered = $0 ? row : (hovered == row ? nil : hovered) }
        .contextMenu {
            if !standard {
                Button(SettingsWords.text("Remove")) { under.remove(row) }
            } else if row != FieldUnder.search {
                Button(SettingsWords.text(off ? "Turn On" : "Turn Off")) { under.set(row, on: off) }
            }
            // The same as ⌘T's Hide or Show AI Rows in Field.
            if row == FieldUnder.ask || row == FieldUnder.task, prefs.aiUse == .on {
                Button(SettingsWords.text(prefs.aiRowsHidden ? "Show AI Rows in Field" : "Hide AI Rows in Field")) {
                    prefs.aiRowsHidden.toggle()
                }
            }
        }
    }

    @ViewBuilder private func mark(_ row: String) -> some View {
        // Bare, at a site's icon's size: a table's marks, not the field's wells.
        switch row {
        case FieldUnder.search: Symbol("magnifyingglass", size: 12).foregroundStyle(.secondary)
        case FieldUnder.ask: Symbol("bubble.sparkle", size: 12).foregroundStyle(.secondary)
        case FieldUnder.task: Symbol("agent.face", size: 12).foregroundStyle(Color(nsColor: .systemPurple))
        default:
            if let scope = FieldUnder.scope(row) {
                Mark(icon: scope.icon, letter: scope.letter, size: 16)
            } else if let place = FieldUnder.place(row) {
                Symbol(place.symbol, size: 12).foregroundStyle(Color(nsColor: place.tint))
            } else {
                Symbol("magnifyingglass", size: 12).foregroundStyle(.secondary)
            }
        }
    }

    private func name(_ row: String) -> String {
        switch row {
        case FieldUnder.search: return SettingsWords.format("Search %@", [prefs.engine.title])
        case FieldUnder.ask: return "Ask " + AgentSetupModel.name(ModelDefaults.shared.pickNow(.commands).cli)
        case FieldUnder.task: return "Task for " + Agents.preferredName
        default:
            if let place = FieldUnder.place(row) { return SettingsWords.format("Search %@", [place.title]) }
            return FieldUnder.scope(row).map { SettingsWords.format("Search %@", [$0.name]) } ?? row
        }
    }
}
